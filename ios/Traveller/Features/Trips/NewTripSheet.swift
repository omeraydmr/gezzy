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

    static let currencies = ["EUR", "USD", "GBP", "TRY", "JPY", "CHF", "GEL", "AZN", "RSD", "MAD", "AMD", "BRL"]

    var body: some View {
        NavigationStack {
            Form {
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
        }
    }

    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    private func create() {
        var owner = store.me
        owner.role = .owner
        let trimmedCity = city.trimmingCharacters(in: .whitespacesAndNewlines)
        let trip = Trip(name: trimmedName,
                        destination: Destination(countryCode: countryCode,
                                                 city: trimmedCity.isEmpty ? Countries.name(countryCode) : trimmedCity),
                        startDate: Calendar.current.startOfDay(for: startDate),
                        endDate: Calendar.current.startOfDay(for: endDate),
                        status: isDraft ? .draft : .planned,
                        currency: currency,
                        coverSeed: Int.random(in: 0..<100),
                        members: [owner])
        onCreate(trip)
        dismiss()
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
