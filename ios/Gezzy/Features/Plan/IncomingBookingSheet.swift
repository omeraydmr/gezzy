import SwiftUI
import GezzyKit

/// Başka uygulamadan Gezzy'ye paylaşılan dosya (Wallet kartı, PDF, görsel). Önce ne olduğu sorulur:
/// belge olarak saklanabilir, ulaşım bileti ya da konaklama olarak içe aktarılabilir. Sonra seyahat seçilir;
/// tarihi tutan seyahat önceden seçili gelir.
struct IncomingBookingSheet: View {
    @Environment(TripStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let url: URL

    enum Mode: CaseIterable, Hashable {
        case document, transport, lodging
    }

    @State private var result: BookingParser.Result?
    @State private var isReading = true
    @State private var mode: Mode?
    @State private var chosen: Trip.ID?
    /// "Devam" sonrası: seçilen akış açılır.
    @State private var isContinuing = false

    private var isPass: Bool { url.pathExtension.lowercased() == "pkpass" }

    var body: some View {
        if isContinuing, let mode, let chosen, let trip = store.trip(chosen) {
            destination(mode, trip: trip)
        } else {
            NavigationStack {
                List {
                    Section {
                        Label {
                            Text(url.deletingPathExtension().lastPathComponent
                                .replacingOccurrences(of: #"^[0-9A-F-]{36}-"#, with: "", options: .regularExpression))
                                .lineLimit(2)
                        } icon: {
                            Image(systemName: isPass ? "wallet.pass" : url.pathExtension.lowercased() == "pdf" ? "doc.richtext" : "photo")
                        }
                        .foregroundStyle(Color.ink)
                    }

                    Section {
                        ForEach(availableModes, id: \.self) { option in
                            modeRow(option)
                        }
                    } header: {
                        Text("Ne olarak eklensin?")
                    } footer: {
                        if isReading {
                            Label("Dosya okunuyor…", systemImage: "hourglass").font(.footnote)
                        }
                    }

                    if store.trips.isEmpty {
                        Section {
                            Text("Önce bir seyahat oluştur; sonra dosyayı tekrar paylaş.").foregroundStyle(Color.ink2)
                        }
                    } else {
                        Section("Hangi seyahate?") {
                            ForEach(store.upcoming + store.past) { trip in
                                Button {
                                    chosen = trip.id
                                } label: {
                                    HStack {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text("\(trip.countryCodes.map(Countries.flag).joined()) \(trip.name)").foregroundStyle(Color.ink)
                                            Text(AppFormat.dateRange(trip.startDate, trip.endDate)).font(.footnote).foregroundStyle(Color.ink2)
                                        }
                                        Spacer()
                                        if chosen == trip.id {
                                            Image(systemName: "checkmark").font(.body.weight(.semibold)).foregroundStyle(Color.success)
                                        }
                                    }
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .disabled(!store.canEdit(trip))
                            }
                        }
                    }
                }
                .navigationTitle("Gezzy'ye ekle")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Vazgeç") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Devam") { withAnimation { isContinuing = true } }
                            .disabled(mode == nil || chosen == nil)
                    }
                }
            }
            .task(id: url) { await read() }
        }
    }

    /// Wallet kartı yalnızca bilettir; belge olarak saklanacak bir görüntüsü yok.
    private var availableModes: [Mode] { isPass ? [.transport] : Mode.allCases }

    private func modeRow(_ option: Mode) -> some View {
        Button {
            mode = option
        } label: {
            HStack(spacing: 12) {
                Image(systemName: symbol(option))
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(accent(option).base)
                    .frame(width: 36, height: 36)
                    .background(accent(option).tint, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title(option)).font(.tBodyStrong).foregroundStyle(Color.ink)
                    Text(subtitle(option)).font(.caption).foregroundStyle(Color.ink2)
                }
                Spacer(minLength: 8)
                Image(systemName: mode == option ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(mode == option ? Color.success : Color.ink3)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func title(_ option: Mode) -> String {
        switch option {
        case .document: String(localized: "Belge olarak sakla")
        case .transport: String(localized: "Ulaşım bileti")
        case .lodging: String(localized: "Konaklama")
        }
    }

    private func subtitle(_ option: Mode) -> String {
        switch option {
        case .document:
            return String(localized: "Pasaport, vize, sigorta… Vize › Belgeler'de durur, internetsiz açılır.")
        case .transport:
            guard let result else { return String(localized: "Uçuş, tren ya da otobüs bileti") }
            return result.flights.isEmpty ? String(localized: "Bilet bilgisi bulunamadı; metni düzeltip deneyebilirsin.")
                                          : String(localized: "\(result.flights.count) bilet bulundu")
        case .lodging:
            guard let result else { return String(localized: "Otel, Airbnb ya da Booking.com onayı") }
            return result.lodgings.isEmpty ? String(localized: "Konaklama bilgisi bulunamadı.")
                                           : String(localized: "\(result.lodgings.count) konaklama bulundu")
        }
    }

    private func symbol(_ option: Mode) -> String {
        switch option {
        case .document: "doc.on.doc.fill"
        case .transport: "airplane"
        case .lodging: "bed.double.fill"
        }
    }

    private func accent(_ option: Mode) -> Accent {
        switch option {
        case .document: .gray
        case .transport: .blue
        case .lodging: .green
        }
    }

    @ViewBuilder
    private func destination(_ mode: Mode, trip: Trip) -> some View {
        switch mode {
        case .document:
            if let file = documentFile {
                DocumentDetailsSheet(trip: trip, file: file)
            } else {
                ContentUnavailableView("Dosya açılamadı", systemImage: "exclamationmark.triangle")
            }
        case .transport:
            BookingImportSheet(trip: trip, kind: .flights, preloaded: result)
        case .lodging:
            BookingImportSheet(trip: trip, kind: .lodgings, preloaded: result)
        }
    }

    private var documentFile: DocumentsCard.PendingFile? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        let name = url.deletingPathExtension().lastPathComponent
            .replacingOccurrences(of: #"^[0-9A-F-]{36}-"#, with: "", options: .regularExpression)
        return DocumentsCard.PendingFile(data: data, fileExtension: url.pathExtension.isEmpty ? "pdf" : url.pathExtension,
                                         suggestedTitle: name)
    }

    private func read() async {
        defer { isReading = false }
        let parsed = try? await BookingFileReader.read(url)
        result = parsed
        // Tarihi tutan seyahat ve okunanın türü önceden seçilir; kullanıcı değiştirebilir.
        if chosen == nil {
            chosen = parsed?.matchingTrip(in: store.trips)?.id ?? (store.upcoming.count == 1 ? store.upcoming.first?.id : nil)
        }
        if mode == nil {
            if isPass || !(parsed?.flights.isEmpty ?? true) {
                mode = .transport
            } else if !(parsed?.lodgings.isEmpty ?? true) {
                mode = .lodging
            } else {
                mode = .document
            }
        }
    }
}
