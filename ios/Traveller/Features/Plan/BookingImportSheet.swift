import PDFKit
import PhotosUI
import SwiftUI
import TravellerKit
import UniformTypeIdentifiers

/// E-bilet ya da otel onayını (PDF, ekran görüntüsü ya da Wallet biniş kartı) okur, bulunan uçuş ve konaklamaları
/// gösterir; seçilenler seyahate eklenir. Metin tamamen cihazda okunur.
struct BookingImportSheet: View {
    @Environment(TripStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let trip: Trip

    @State private var isPickingFile = false
    @State private var photoItem: PhotosPickerItem?
    @State private var isReading = false
    @State private var result: BookingParser.Result?
    @State private var selectedFlights: Set<Int> = []
    @State private var selectedLodgings: Set<Int> = []
    @State private var errorText: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Button {
                        isPickingFile = true
                    } label: {
                        Label("PDF, Wallet kartı ya da dosya seç", systemImage: "doc.fill")
                    }
                    PhotosPicker(selection: $photoItem, matching: .images) {
                        Label("Ekran görüntüsü seç", systemImage: "photo")
                    }
                } footer: {
                    Text("E-bilet, otel onayı ya da Wallet biniş kartı (.pkpass). Metin cihazda okunur, hiçbir yere gönderilmez.")
                }

                if isReading {
                    Section { HStack { ProgressView(); Text("Okunuyor…").foregroundStyle(Color.ink2) } }
                }
                if let errorText {
                    Section { Label(errorText, systemImage: "exclamationmark.triangle").foregroundStyle(Color.food) }
                }

                if let result {
                    if result.isEmpty {
                        Section {
                            Text("Uçuş ya da konaklama bulunamadı. Başka bir sayfa ya da daha net bir ekran görüntüsü dene.")
                                .foregroundStyle(Color.ink2)
                        }
                    }
                    if !result.flights.isEmpty {
                        Section("Uçuşlar") {
                            ForEach(Array(result.flights.enumerated()), id: \.offset) { index, flight in
                                toggleRow(isOn: selectedFlights.contains(index)) {
                                    toggle(&selectedFlights, index)
                                } content: {
                                    flightSummary(flight)
                                }
                            }
                        }
                    }
                    if !result.lodgings.isEmpty {
                        Section("Konaklama") {
                            ForEach(Array(result.lodgings.enumerated()), id: \.offset) { index, lodging in
                                toggleRow(isOn: selectedLodgings.contains(index)) {
                                    toggle(&selectedLodgings, index)
                                } content: {
                                    lodgingSummary(lodging)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Rezervasyon içe aktar")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Vazgeç") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Ekle", action: add)
                        .disabled(selectedFlights.isEmpty && selectedLodgings.isEmpty)
                }
            }
            .fileImporter(isPresented: $isPickingFile, allowedContentTypes: [.pdf, .image, .walletPass]) { outcome in
                if case let .success(url) = outcome {
                    Task { await read(url: url) }
                }
            }
            .onChange(of: photoItem) { _, item in
                guard let item else { return }
                Task {
                    guard let data = try? await item.loadTransferable(type: Data.self),
                          let image = CoverImageStore.downsample(data: data, maxPixelSize: 2400) else {
                        errorText = String(localized: "Görüntü açılamadı.")
                        return
                    }
                    await read(lines: TextReader.lines(in: image))
                }
            }
        }
    }

    private func lodgingSummary(_ lodging: BookingParser.LodgingCandidate) -> some View {
        var detail = "\(AppFormat.dayPill(lodging.checkIn)) → \(AppFormat.dayPill(lodging.checkOut))"
        if !lodging.confirmation.isEmpty { detail += " · \(lodging.confirmation)" }
        return VStack(alignment: .leading, spacing: 2) {
            Text(lodging.name).foregroundStyle(Color.ink)
            Text(detail).font(.footnote).foregroundStyle(Color.ink2)
        }
    }

    private func flightSummary(_ flight: BookingParser.FlightCandidate) -> some View {
        let from = Airports.airport(flight.fromCode)
        let to = Airports.airport(flight.toCode)
        let departure = AppFormat.time(flight.departure, timeZone: from?.timeZone)
        let arrival = AppFormat.time(flight.arrival, timeZone: to?.timeZone)
        var detail = "\(AppFormat.dayPill(flight.departure)) · \(departure) → \(arrival)"
        if let seat = flight.seat { detail += " · koltuk \(seat)" }
        return VStack(alignment: .leading, spacing: 2) {
            Text("\(flight.flightNumber) · \(flight.fromCode) → \(flight.toCode)").foregroundStyle(Color.ink)
            Text(detail)
                .font(.footnote)
                .foregroundStyle(Color.ink2)
            if !flight.hasTimes {
                Text("Saat bulunamadı; ekledikten sonra kontrol et.").font(.caption).foregroundStyle(Color.food)
            }
        }
    }

    private func toggleRow<Content: View>(isOn: Bool, action: @escaping () -> Void,
                                          @ViewBuilder content: () -> Content) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isOn ? Color.success : Color.ink3)
                content()
            }
        }
        .buttonStyle(.plain)
    }

    private func toggle(_ set: inout Set<Int>, _ index: Int) {
        if set.contains(index) { set.remove(index) } else { set.insert(index) }
    }

    // MARK: Okuma

    private func read(url: URL) async {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        isReading = true
        defer { isReading = false }
        errorText = nil

        if url.pathExtension.lowercased() == "pkpass" {
            guard let data = try? Data(contentsOf: url), let parsed = PassParser.parse(pkpass: data) else {
                errorText = String(localized: "Wallet kartı okunamadı.")
                return
            }
            apply(parsed)
        } else if url.pathExtension.lowercased() == "pdf", let document = PDFDocument(url: url) {
            let text = document.string ?? ""
            if text.trimmingCharacters(in: .whitespacesAndNewlines).count > 40 {
                apply(BookingParser.parse(text))
                return
            }
            // Taranmış PDF: ilk sayfaları görüntüye çevirip oku.
            var lines: [String] = []
            for index in 0..<min(document.pageCount, 3) {
                guard let page = document.page(at: index) else { continue }
                let bounds = page.bounds(for: .mediaBox)
                let scale = 2000 / max(bounds.width, bounds.height)
                let image = page.thumbnail(of: CGSize(width: bounds.width * scale, height: bounds.height * scale), for: .mediaBox)
                lines += await TextReader.lines(in: image)
            }
            await read(lines: lines)
        } else if let data = try? Data(contentsOf: url),
                  let image = CoverImageStore.downsample(data: data, maxPixelSize: 2400) {
            await read(lines: TextReader.lines(in: image))
        } else {
            errorText = String(localized: "Dosya okunamadı.")
        }
    }

    private func read(lines: [String]) async {
        apply(BookingParser.parse(lines.joined(separator: "\n")))
    }

    private func apply(_ parsed: BookingParser.Result) {
        withAnimation {
            result = parsed
            selectedFlights = Set(parsed.flights.indices)
            selectedLodgings = Set(parsed.lodgings.indices)
        }
    }

    private func add() {
        guard let result else { return }
        let flights = selectedFlights.sorted().map { result.flights[$0].segment() }
        let lodgings = selectedLodgings.sorted().map { result.lodgings[$0].lodging() }
        store.update(trip.id) { trip in
            for flight in flights where !trip.flights.contains(where: {
                $0.flightNumber == flight.flightNumber && Calendar.current.isDate($0.departure, inSameDayAs: flight.departure)
            }) {
                trip.flights.append(flight)
            }
            if !lodgings.isEmpty { trip.lodgings = (trip.lodgings ?? []) + lodgings }
        }
        dismiss()
    }
}

private extension UTType {
    /// Wallet kartı. Info.plist'te içe aktarılan tür olarak bildirilir (UTImportedTypeDeclarations).
    static let walletPass = UTType(importedAs: "com.apple.pkpass", conformingTo: .data)
}
