import CloudKit
import CoreTransferable
import Foundation
import Observation
import SwiftUI
import TravellerKit

/// iCloud (CloudKit) ile seyahat eşitleme ve ekip paylaşımı.
///
/// - Her seyahat, özel veritabanındaki "Trips" bölgesinde tek bir `Trip` kaydıdır; içerik JSON olarak `payload`
///   alanında durur (fotoğraflar eşitlenmez).
/// - Paylaşılan seyahat bir `CKShare` ile davet edilir; katılanlar onu paylaşılan veritabanında görür.
/// - Çakışmada iki kopya `Trip.merged(with:)` ile birleştirilir (silinenler geri gelmez).
@MainActor
@Observable
final class CloudSync {
    static let shared = CloudSync()

    enum Status: Equatable {
        case unknown
        case unavailable(String)
        case syncing
        case synced(Date)
        case failed(String)
    }

    private(set) var status: Status = .unknown
    /// Başkasının paylaştığı (bizim katıldığımız) seyahatler.
    private(set) var sharedWithMe: Set<UUID> = []
    /// Bizim paylaşıma açtığımız seyahatler.
    private(set) var sharedByMe: Set<UUID> = []
    /// Bize paylaşılan seyahatlerde iCloud'daki iznimiz (sahip "sadece görür" yaptıysa salt okunur).
    private(set) var myAccess: [UUID: ShareAccess] = [:]
    /// Bu cihazdaki iCloud kullanıcısının kayıt adı; ekipte kendimizi paylaşım katılımcısıyla eşleştirmek için.
    private(set) var currentUserID: String?
    /// Son uygulanan rol → izin eşlemesi; aynıysa paylaşım kaydı yeniden okunmaz.
    @ObservationIgnored private var appliedPermissions: [UUID: [String: ShareAccess]] = [:]

    var isAvailable: Bool {
        switch status {
        case .syncing, .synced, .failed: true
        default: false
        }
    }

    private weak var store: TripStore?
    private var pending: Set<UUID> = []
    private var pushTask: Task<Void, Never>?
    /// Seyahat → paylaşılan veritabanındaki bölgesi (bizim olmayanlar için).
    private var sharedZones: [UUID: CKRecordZone.ID] = [:]

    private var container: CKContainer { CloudConfig.container }
    private let zoneID = CKRecordZone.ID(zoneName: "Trips", ownerName: CKCurrentUserDefaultName)
    private static let recordType = "Trip"

    // MARK: Lifecycle

    func start(with store: TripStore) async {
        self.store = store
        do {
            let account = try await container.accountStatus()
            guard account == .available else {
                status = .unavailable("iCloud'a giriş yapılmamış. Ayarlar'dan giriş yapınca seyahatler eşitlenir.")
                return
            }
            _ = try await container.privateCloudDatabase.modifyRecordZones(saving: [CKRecordZone(zoneID: zoneID)], deleting: [])
            currentUserID = try? await container.userRecordID().recordName
            await ensureSubscriptions()
            await pull()
            // İlk açılışta yerel seyahatleri buluta gönder.
            pending.formUnion(store.trips.map(\.id))
            schedulePush(after: .milliseconds(200))
        } catch {
            status = .unavailable("iCloud'a ulaşılamadı: \(error.localizedDescription)")
        }
    }

    func tripChanged(_ id: UUID) {
        guard isAvailable else { return }
        pending.insert(id)
        schedulePush(after: .seconds(1.5))
    }

    func tripDeleted(_ id: UUID) {
        guard isAvailable else { return }
        pending.remove(id)
        Task {
            if sharedZones[id] != nil {
                // Başkasının seyahati: kaydı silemeyiz, paylaşımdan ayrılırız (CKShare'i kendi tarafımızda sileriz).
                let database = container.sharedCloudDatabase
                if let root = try? await database.record(for: recordID(for: id)), let share = root.share {
                    _ = try? await database.modifyRecords(saving: [], deleting: [share.recordID])
                }
                sharedZones[id] = nil
                sharedWithMe.remove(id)
                return
            }
            _ = try? await container.privateCloudDatabase.modifyRecords(saving: [], deleting: [recordID(for: id)])
            sharedByMe.remove(id)
        }
    }

    /// Öne gelince ya da kullanıcı yenileyince çağrılır.
    func refresh() async {
        guard isAvailable else { return }
        await pull()
    }

    /// CloudKit'in sessiz bildirimi geldiğinde (başka bir cihazda değişiklik): çek ve değişiklikleri bildir.
    func handleRemoteNotification() async -> Bool {
        guard isAvailable else { return false }
        await pull(notifyChanges: true)
        return true
    }

    private static let subscriptionsKey = "traveller.cloud.subscriptions.v1"

    /// Özel ve paylaşılan veritabanındaki her değişiklikte sessiz bildirim gelmesi için abonelikler (bir kez).
    private func ensureSubscriptions() async {
        guard !UserDefaults.standard.bool(forKey: Self.subscriptionsKey) else { return }
        let info = CKSubscription.NotificationInfo()
        info.shouldSendContentAvailable = true
        do {
            for (database, id) in [(container.privateCloudDatabase, "private-changes"), (container.sharedCloudDatabase, "shared-changes")] {
                let subscription = CKDatabaseSubscription(subscriptionID: id)
                subscription.notificationInfo = info
                _ = try await database.modifySubscriptions(saving: [subscription], deleting: [])
            }
            UserDefaults.standard.set(true, forKey: Self.subscriptionsKey)
        } catch {
            // Bir sonraki açılışta yeniden denenir; eşitleme yine açılış/öne gelişte çalışır.
        }
    }

    // MARK: Pull

    private func pull(notifyChanges: Bool = false) async {
        guard let store else { return }
        status = .syncing
        do {
            var needsPush: Set<UUID> = []
            var summaries: [TripChanges.Summary] = []
            func merge(_ remote: Trip) {
                let before = store.trip(remote.id)
                if store.mergeFromCloud(remote) { needsPush.insert(remote.id) }
                guard let after = store.trip(remote.id),
                      let summary = TripChanges.summarize(old: before, new: after, me: store.me.id, money: AppFormat.money)
                else { return }
                // Akışa yalnızca var olan seyahatteki değişiklikler yazılır (ilk indirme değil).
                if before != nil { store.recordActivity(summary) }
                if notifyChanges { summaries.append(summary) }
            }
            // Kendi seyahatlerimiz.
            var ownShares: [UUID: CKShare] = [:]
            for trip in try await fetchTrips(in: container.privateCloudDatabase, zone: zoneID) {
                merge(trip.trip)
                if trip.isShared { sharedByMe.insert(trip.trip.id) }
                if let share = trip.share { ownShares[trip.trip.id] = share }
            }
            // Bize paylaşılanlar.
            var seenShared: Set<UUID> = []
            for zone in try await container.sharedCloudDatabase.allRecordZones() {
                for trip in try await fetchTrips(in: container.sharedCloudDatabase, zone: zone.zoneID) {
                    sharedZones[trip.trip.id] = zone.zoneID
                    seenShared.insert(trip.trip.id)
                    var share = trip.share
                    if share == nil, let shareID = trip.shareID {
                        share = try? await container.sharedCloudDatabase.record(for: shareID) as? CKShare
                    }
                    myAccess[trip.trip.id] = share.flatMap { Self.access(of: $0.currentUserParticipant) }
                    merge(trip.trip)
                }
            }
            for summary in summaries {
                await NotificationScheduler.shared.notifyCloudChange(summary)
            }
            // Paylaşımdan çıkarıldığımız seyahatleri kaldır.
            for removed in sharedWithMe.subtracting(seenShared) {
                store.removeFromCloud(removed)
                sharedZones[removed] = nil
                myAccess[removed] = nil
            }
            sharedWithMe = seenShared
            // Sahibi olduğumuz paylaşımlarda iCloud izinlerini ekipteki rollere uydur.
            for tripID in sharedByMe {
                if let trip = store.trip(tripID) { await applyPermissions(of: trip, to: ownShares[tripID]) }
            }
            status = .synced(.now)
            if !needsPush.isEmpty {
                pending.formUnion(needsPush)
                schedulePush(after: .milliseconds(300))
            }
        } catch {
            status = .failed(error.localizedDescription)
        }
    }

    private struct FetchedTrip {
        let trip: Trip
        let isShared: Bool
        /// Seyahat kaydının paylaşım kaydı (aynı bölgede geldiyse).
        var share: CKShare?
        var shareID: CKRecord.ID?
    }

    private func fetchTrips(in database: CKDatabase, zone: CKRecordZone.ID) async throws -> [FetchedTrip] {
        var result: [FetchedTrip] = []
        var shares: [CKRecord.ID: CKShare] = [:]
        var token: CKServerChangeToken?
        var moreComing = true
        while moreComing {
            let changes = try await database.recordZoneChanges(inZoneWith: zone, since: token)
            for (_, change) in changes.modificationResultsByID {
                guard let modification = try? change.get() else { continue }
                let record = modification.record
                if let share = record as? CKShare {
                    shares[share.recordID] = share
                    continue
                }
                if record.recordType == Self.photoType {
                    importPhoto(record)
                    continue
                }
                guard record.recordType == Self.recordType, let trip = Self.decode(record) else { continue }
                if let name = record["coverName"] as? String, let asset = record["cover"] as? CKAsset, let url = asset.fileURL {
                    CoverImageStore.shared.importFile(at: url, named: name)
                    uploadedPhotos.insert("cover-\(name)")
                }
                result.append(FetchedTrip(trip: trip, isShared: record.share != nil, share: nil, shareID: record.share?.recordID))
            }
            token = changes.changeToken
            moreComing = changes.moreComing
        }
        return result.map { fetched in
            var fetched = fetched
            fetched.share = fetched.shareID.flatMap { shares[$0] }
            return fetched
        }
    }

    // MARK: Push

    private func schedulePush(after delay: Duration) {
        pushTask?.cancel()
        pushTask = Task {
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            await push()
        }
    }

    private func push() async {
        guard let store, !pending.isEmpty else { return }
        let ids = pending
        pending.removeAll()
        status = .syncing
        for id in ids {
            guard let trip = store.trip(id) else { continue }
            do {
                try await save(trip)
                if sharedByMe.contains(id) { await applyPermissions(of: trip) }
            } catch let error as CKError where error.code == .permissionFailure {
                // Sahip yetkimizi "sadece görür" yaptı: değişiklik sunucuya yazılamaz, tekrar denenmez.
                myAccess[id] = .readOnly
                status = .failed("Bu seyahatte yalnızca görüntüleme yetkin var; değişiklik kaydedilmedi.")
                await pull()
                return
            } catch {
                status = .failed(error.localizedDescription)
                pending.insert(id)
                return
            }
        }
        status = .synced(.now)
    }

    /// Kaydı yazar; sunucuda daha yeni bir kopya varsa birleştirip bir kez daha dener.
    private func save(_ trip: Trip, attempt: Int = 0) async throws {
        let database = database(for: trip.id)
        let id = recordID(for: trip.id)
        let record: CKRecord
        if let existing = try? await database.record(for: id) {
            record = existing
        } else {
            record = CKRecord(recordType: Self.recordType, recordID: id)
        }
        record["payload"] = try Self.encoder.encode(trip) as CKRecordValue
        record["name"] = trip.name as CKRecordValue
        record["updatedAt"] = (trip.updatedAt ?? .now) as CKRecordValue

        // Kapak fotoğrafı kaydın üzerinde varlık (asset) olarak; yalnızca değiştiyse yüklenir.
        if let cover = trip.coverPhoto {
            if (record["coverName"] as? String) != cover, let url = CoverImageStore.shared.fileURL(named: cover) {
                record["cover"] = CKAsset(fileURL: url)
                record["coverName"] = cover as CKRecordValue
            }
        } else if record["coverName"] != nil {
            record["cover"] = nil
            record["coverName"] = nil
        }

        // Makbuzlar ve belgeler seyahat kaydına bağlı ayrı kayıtlar; paylaşımla birlikte katılanlara da gider.
        // "Yalnızca bu cihazda" işaretli belgeler yüklenmez.
        let receiptFiles: [UploadFile] = trip.expenses.compactMap(\.receiptPhoto).compactMap { name -> UploadFile? in
            guard let url = CoverImageStore.receipts.fileURL(named: name) else { return nil }
            return UploadFile(kind: "receipt", name: name, url: url)
        }
        let documentFiles: [UploadFile] = trip.documentList.filter { !$0.isPrivate }.compactMap { document -> UploadFile? in
            guard let url = CoverImageStore.documents.fileURL(named: document.fileName) else { return nil }
            return UploadFile(kind: "document", name: document.fileName, url: url)
        }
        let files = receiptFiles + documentFiles
        let photoRecords: [CKRecord] = files
            .filter { !uploadedPhotos.contains("\($0.kind)-\($0.name)") }
            .map { file in
                let photo = CKRecord(recordType: Self.photoType,
                                     recordID: CKRecord.ID(recordName: "\(file.kind)-\(file.name)", zoneID: id.zoneID))
                photo["name"] = file.name as CKRecordValue
                photo["kind"] = file.kind as CKRecordValue
                photo["asset"] = CKAsset(fileURL: file.url)
                photo.setParent(id)
                return photo
            }

        let (results, _) = try await database.modifyRecords(saving: [record] + photoRecords, deleting: [],
                                                            savePolicy: .ifServerRecordUnchanged, atomically: false)
        for photo in photoRecords {
            if case .success? = results[photo.recordID] {
                uploadedPhotos.insert(photo.recordID.recordName)
            }
        }
        if case let .failure(error)? = results[id] {
            if let ckError = error as? CKError, ckError.code == .serverRecordChanged, attempt < 2,
               let server = ckError.serverRecord, let remote = Self.decode(server), let store {
                store.mergeFromCloud(remote)
                if let merged = store.trip(trip.id) {
                    try await save(merged, attempt: attempt + 1)
                }
                return
            }
            throw error
        }
    }

    // MARK: Sharing

    /// Seyahat için bir CKShare hazırlar (yoksa oluşturur). Paylaşım sayfası bunu kullanır.
    func share(for tripID: UUID) async throws -> CKShare {
        guard let trip = store?.trip(tripID) else { throw CKError(.unknownItem) }
        let database = container.privateCloudDatabase
        let id = recordID(for: tripID)
        try await save(trip)
        let record = try await database.record(for: id)
        if let reference = record.share, let existing = try await database.record(for: reference.recordID) as? CKShare {
            return existing
        }
        let share = CKShare(rootRecord: record)
        share[CKShare.SystemFieldKey.title] = trip.name as CKRecordValue
        share.publicPermission = .none
        _ = try await database.modifyRecords(saving: [record, share], deleting: [])
        sharedByMe.insert(tripID)
        return share
    }

    /// Ekipteki "sadece görür" / "düzenleyebilir" rollerini paylaşım katılımcılarının iCloud iznine yansıtır.
    /// Yalnızca sahip çağırır; iCloud kimliği bilinmeyen kişilere ve ekipte olmayan katılımcılara dokunulmaz.
    func applyPermissions(of trip: Trip, to knownShare: CKShare? = nil) async {
        let desired = SharePermissions.desired(for: trip.members)
        guard sharedWithMe.contains(trip.id) == false, appliedPermissions[trip.id] != desired else { return }
        let database = container.privateCloudDatabase
        let share: CKShare
        if let knownShare {
            share = knownShare
        } else {
            guard let record = try? await database.record(for: recordID(for: trip.id)), let reference = record.share,
                  let fetched = try? await database.record(for: reference.recordID) as? CKShare else { return }
            share = fetched
        }
        var current: [String: ShareAccess] = [:]
        var participants: [String: CKShare.Participant] = [:]
        for participant in share.participants where participant.role != .owner {
            guard let name = participant.userIdentity.userRecordID?.recordName,
                  let access = Self.access(of: participant) else { continue }
            current[name] = access
            participants[name] = participant
        }
        let changes = SharePermissions.changes(members: trip.members, participants: current)
        if !changes.isEmpty {
            for (name, access) in changes {
                participants[name]?.permission = access == .readOnly ? .readOnly : .readWrite
            }
            do {
                _ = try await database.modifyRecords(saving: [share], deleting: [])
            } catch {
                status = .failed("Paylaşım yetkileri güncellenemedi: \(error.localizedDescription)")
                return
            }
        }
        appliedPermissions[trip.id] = desired
    }

    private static func access(of participant: CKShare.Participant?) -> ShareAccess? {
        switch participant?.permission {
        case .readOnly: .readOnly
        case .readWrite: .readWrite
        default: nil
        }
    }

    /// Davet bağlantısına dokunulduğunda (SceneDelegate) çağrılır.
    func accept(_ metadata: CKShare.Metadata) async {
        do {
            _ = try await container.accept(metadata)
            await pull()
        } catch {
            status = .failed("Davet kabul edilemedi: \(error.localizedDescription)")
        }
    }

    // MARK: Photos

    private static let photoType = "Photo"

    private struct UploadFile {
        let kind: String
        let name: String
        let url: URL
    }
    private static let uploadedKey = "traveller.cloud.uploadedPhotos"

    /// Buluta yüklenmiş (ya da buluttan gelmiş) fotoğraf anahtarları; tekrar yüklenmez.
    @ObservationIgnored
    private var uploadedPhotos: Set<String> = Set(UserDefaults.standard.stringArray(forKey: CloudSync.uploadedKey) ?? []) {
        didSet { UserDefaults.standard.set(Array(uploadedPhotos), forKey: Self.uploadedKey) }
    }

    private func importPhoto(_ record: CKRecord) {
        guard let name = record["name"] as? String, let asset = record["asset"] as? CKAsset, let url = asset.fileURL else { return }
        let kind = record["kind"] as? String ?? "receipt"
        let store = kind == "document" ? CoverImageStore.documents : CoverImageStore.receipts
        store.importFile(at: url, named: name)
        uploadedPhotos.insert("\(kind)-\(name)")
    }

    // MARK: Helpers

    private func database(for tripID: UUID) -> CKDatabase {
        sharedZones[tripID] == nil ? container.privateCloudDatabase : container.sharedCloudDatabase
    }

    private func recordID(for tripID: UUID) -> CKRecord.ID {
        CKRecord.ID(recordName: tripID.uuidString, zoneID: sharedZones[tripID] ?? zoneID)
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    private static func decode(_ record: CKRecord) -> Trip? {
        guard let data = record["payload"] as? Data else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(Trip.self, from: data)
    }
}

enum CloudConfig {
    static let containerIdentifier = "iCloud.app.traveller.ios"
    static let container = CKContainer(identifier: containerIdentifier)
}

/// Paylaşım sayfasına (Mesajlar, Mail…) verilen öğe; iCloud davet bağlantısını oluşturur.
struct TripShareItem: Transferable {
    let tripID: UUID
    let title: String

    static var transferRepresentation: some TransferRepresentation {
        CKShareTransferRepresentation { item in
            .prepareShare(container: CloudConfig.container) {
                try await CloudSync.shared.share(for: item.tripID)
            }
        }
    }
}
