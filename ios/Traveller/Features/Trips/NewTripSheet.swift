import PhotosUI
import SwiftUI
import TravellerKit

struct NewTripSheet: View {
    @Environment(TripStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let onCreate: (Trip) -> Void

    @State private var name = ""
    @State private var countryCode = "PT"
    @State private var city = ""
    @State private var startDate = Calendar.current.date(byAdding: .day, value: 30, to: .now) ?? .now
    @State private var endDate = Calendar.current.date(byAdding: .day, value: 35, to: .now) ?? .now
    @State private var currency = "EUR"
    @State private var isDraft = false
    @State private var coverSeed = Int.random(in: 0..<100)
    @State private var photoItem: PhotosPickerItem?
    @State private var photoData: Data?
    @State private var previewImage: UIImage?
    @State private var ceremonyTrip: Trip?

    static let currencies = ["EUR", "USD", "GBP", "TRY", "JPY", "CHF", "GEL", "AZN", "RSD", "MAD", "AMD", "BRL"]

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    preview
                        .frame(maxWidth: .infinity)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
                }
                Section {
                    TextField("Seyahat adı (ör. Lizbon Kaçamağı)", text: $name)
                    NavigationLink {
                        CountryPicker(selection: $countryCode)
                    } label: {
                        LabeledContent("Ülke", value: "\(Countries.flag(countryCode)) \(Countries.name(countryCode))")
                    }
                    TextField("Şehir", text: $city)
                }
                Section {
                    DatePicker("Gidiş", selection: $startDate, displayedComponents: .date)
                    DatePicker("Dönüş", selection: $endDate, in: startDate..., displayedComponents: .date)
                }
                Section {
                    Picker("Para birimi", selection: $currency) {
                        ForEach(Self.currencies, id: \.self) { Text($0) }
                    }
                    Toggle("Taslak olarak kaydet", isOn: $isDraft)
                }
                Section {
                    VisaPreview(countryCode: countryCode, passport: store.me.passport, start: startDate, end: endDate)
                } header: {
                    Text("Senin için vize durumu")
                }
            }
            .navigationTitle("Yeni seyahat")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Vazgeç") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Oluştur", action: create)
                        .disabled(trimmedName.isEmpty)
                }
            }
            .onChange(of: startDate) { _, newValue in
                if endDate < newValue { endDate = newValue }
            }
            .onChange(of: photoItem) { _, item in
                guard let item else { return }
                Task {
                    // Önizleme için küçültülmüş görüntü: 12 MP fotoğraf her tuş vuruşunda yeniden çizilmesin.
                    if let data = try? await item.loadTransferable(type: Data.self),
                       let image = CoverImageStore.downsample(data: data, maxPixelSize: CoverImageStore.cardPixelSize) {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            photoData = data
                            previewImage = image
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(TintGlow(tint: Accent.cycle(coverSeed).base, offsetY: -200))
        }
        .overlay {
            if let ceremonyTrip {
                StampCeremony(trip: ceremonyTrip, coverImage: previewImage) {
                    onCreate(ceremonyTrip)
                    dismiss()
                }
            }
        }
        .interactiveDismissDisabled(ceremonyTrip != nil)
    }

    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    /// Formdaki değerlerle canlı önizleme kartı.
    private var preview: some View {
        TripTicketCard(trip: draftTrip, side: 230)
            .environment(\.coverOverride, previewImage)
            .overlay(alignment: .topLeading) {
                PhotosPicker(selection: $photoItem, matching: .images) {
                    Label(previewImage == nil ? "Fotoğraf ekle" : "Değiştir", systemImage: "camera.fill")
                        .font(.system(.footnote, weight: .semibold))
                        .foregroundStyle(Color.ink)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(.regularMaterial, in: Capsule())
                }
                .padding(12)
            }
            .rotationEffect(.degrees(-2))
            .padding(.vertical, 6)
    }

    private var draftTrip: Trip {
        var owner = store.me
        owner.role = .owner
        let trimmedCity = city.trimmingCharacters(in: .whitespacesAndNewlines)
        return Trip(name: trimmedName.isEmpty ? "Yeni seyahat" : trimmedName,
                    destination: Destination(countryCode: countryCode,
                                             city: trimmedCity.isEmpty ? Countries.name(countryCode) : trimmedCity),
                    startDate: Calendar.current.startOfDay(for: startDate),
                    endDate: Calendar.current.startOfDay(for: endDate),
                    status: isDraft ? .draft : .planned,
                    currency: currency,
                    coverSeed: coverSeed,
                    members: [owner])
    }

    private func create() {
        var trip = draftTrip
        trip.name = trimmedName
        if let photoData {
            trip.coverPhoto = try? CoverImageStore.shared.save(photoData)
        }
        ceremonyTrip = trip
    }
}

struct CountryPicker: View {
    @Binding var selection: String
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    var body: some View {
        List(filtered, id: \.self) { code in
            Button {
                selection = code
                dismiss()
            } label: {
                HStack {
                    Text(Countries.flag(code))
                    Text(Countries.name(code)).foregroundStyle(Color.ink)
                    Spacer()
                    if code == selection {
                        Image(systemName: "checkmark").foregroundStyle(Color.success)
                    }
                }
            }
        }
        .searchable(text: $query, prompt: "Ülke ara")
        .navigationTitle("Ülke")
    }

    private var filtered: [String] {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return Countries.all }
        return Countries.all.filter {
            Countries.name($0).range(of: q, options: [.caseInsensitive, .diacriticInsensitive], locale: AppFormat.locale) != nil
        }
    }
}
