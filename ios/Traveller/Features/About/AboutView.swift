import SwiftUI
import TravellerKit

/// Uygulamanın kullandığı veri kaynakları ve lisans gereği gösterilmesi gereken atıflar.
struct Attribution: Identifiable, Hashable {
    let id: String
    let name: String
    let usage: String
    let notice: String
    let license: String
    let url: URL

    static let openStreetMap = Attribution(
        id: "osm", name: "OpenStreetMap", usage: "Durakların açılış saatleri (Overpass API)",
        notice: "© OpenStreetMap katkıcıları", license: "Open Database License (ODbL)",
        url: URL(string: "https://www.openstreetmap.org/copyright")!)

    static let openMeteo = Attribution(
        id: "open-meteo", name: "Open-Meteo", usage: "Valiz önerileri için hava tahmini ve geçmiş hava verisi",
        notice: "Weather data by Open-Meteo.com", license: "CC BY 4.0",
        url: URL(string: "https://open-meteo.com/")!)

    static let frankfurter = Attribution(
        id: "frankfurter", name: "Frankfurter · Avrupa Merkez Bankası", usage: "Döviz çevrimi için günlük referans kurlar",
        notice: "ECB euro foreign exchange reference rates", license: "Kaynak gösterilerek serbest kullanım",
        url: URL(string: "https://www.frankfurter.app/")!)

    static let appleMaps = Attribution(
        id: "apple-maps", name: "Apple Haritalar", usage: "Harita, yer arama ve şehir konumu",
        notice: "Harita verisi: Apple ve veri sağlayıcıları", license: "Apple MapKit koşulları",
        url: URL(string: "https://www.apple.com/legal/internet-services/maps/")!)

    static let all = [openStreetMap, openMeteo, frankfurter, appleMaps]
}

struct AboutView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(TripStore.self) private var store
    @State private var confirmReset = false
    private var notifications: NotificationScheduler { .shared }
    private var sync: CloudSync { .shared }

    private var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "—"
        let build = info?["CFBundleVersion"] as? String ?? "—"
        return "\(short) (\(build))"
    }

    private var syncText: String {
        switch sync.status {
        case .unknown: "Kontrol ediliyor"
        case .unavailable: "Kapalı (iCloud girişi yok)"
        case .syncing: "Eşitleniyor…"
        case let .synced(date): "Açık · \(AppFormat.time(date))"
        case .failed: "Sorun var"
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 14) {
                        Image(systemName: "suitcase.fill")
                            .font(.system(size: 26, weight: .semibold))
                            .foregroundStyle(Color.onInk)
                            .frame(width: 56, height: 56)
                            .background(Color.ink, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Traveller").font(.title3.weight(.semibold))
                            Text("Sürüm \(version)").font(.subheadline).foregroundStyle(Color.ink2)
                        }
                    }
                    .padding(.vertical, 4)
                }

                Section {
                    Toggle(isOn: Binding(get: { notifications.isEnabled },
                                         set: { value in Task { await notifications.setEnabled(value) } })) {
                        Label("Seyahat bildirimleri", systemImage: "bell.badge")
                    }
                    if notifications.authorizationDenied {
                        Text("Bildirim izni kapalı. Ayarlar > Traveller > Bildirimler'den açabilirsin.")
                            .font(.caption)
                            .foregroundStyle(Color.food)
                    }
                    HStack {
                        Label("iCloud eşitleme", systemImage: "icloud")
                        Spacer()
                        Text(syncText).font(.subheadline).foregroundStyle(Color.ink2).multilineTextAlignment(.trailing)
                    }
                    if sync.isAvailable {
                        Button("Şimdi eşitle") { Task { await sync.refresh() } }
                    }
                } header: {
                    Text("Ayarlar")
                } footer: {
                    Text("Bildirimler: gitmeden önceki akşam valiz hatırlatması, uçuştan 3 saat önce kapı ve koltuk, her sabah günün planı ve notlu duraklardan 45 dk önce.")
                }

                Section {
                    ForEach(Attribution.all) { source in
                        Link(destination: source.url) {
                            VStack(alignment: .leading, spacing: 3) {
                                HStack {
                                    Text(source.name).font(.tBodyStrong).foregroundStyle(Color.ink)
                                    Spacer()
                                    Image(systemName: "arrow.up.right").font(.caption).foregroundStyle(Color.ink3)
                                }
                                Text(source.usage).font(.subheadline).foregroundStyle(Color.ink2)
                                Text("\(source.notice) · \(source.license)").font(.caption).foregroundStyle(Color.ink3)
                            }
                            .padding(.vertical, 2)
                        }
                    }
                } header: {
                    Text("Veri kaynakları")
                }

                Section {
                    Label("Seyahatler bu cihazda ve iCloud hesabında saklanır; yalnızca davet ettiğin kişiler görebilir. Fotoğraflar cihazda kalır.", systemImage: "iphone")
                    Label("Makbuz metni cihaz üzerinde okunur; görüntü hiçbir yere gönderilmez.", systemImage: "doc.text.viewfinder")
                    Label("Kur, hava ve açılış saati sorgularında yalnızca para birimi, konum ve yer adı gönderilir.",
                          systemImage: "network")
                } header: {
                    Text("Gizlilik")
                }
                .font(.subheadline)
                .foregroundStyle(Color.ink2)

                Section {
                    Text("Vize bilgileri T.C. umuma mahsus (bordo) pasaport için elle derlenmiştir; son gözden geçirme \(VisaRules.lastReviewed). Seyahatten önce resmî kaynaktan doğrula.")
                        .font(.subheadline)
                        .foregroundStyle(Color.ink2)
                    Link("konsolosluk.gov.tr", destination: VisaRules.officialSourceURL)
                } header: {
                    Text("Vize bilgisi")
                }

                Section {
                    Button("Örnek seyahatleri yeniden yükle", role: .destructive) { confirmReset = true }
                }
            }
            .navigationTitle("Hakkında")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Tamam") { dismiss() }
                }
            }
            .confirmationDialog("Tüm seyahatler silinip örnek veriler yüklensin mi?", isPresented: $confirmReset,
                                titleVisibility: .visible) {
                Button("Sıfırla", role: .destructive) {
                    store.resetToSamples()
                    dismiss()
                }
            }
        }
    }
}
