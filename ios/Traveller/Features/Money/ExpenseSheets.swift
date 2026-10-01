import PhotosUI
import SwiftUI
import TravellerKit

struct AddExpenseSheet: View {
    @Environment(TripStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let trip: Trip

    @State private var entry = AmountEntry()
    @State private var title = ""
    @State private var category: SpendCategory = .food
    @State private var paidBy: UUID?
    @State private var splitAmong: Set<UUID> = []
    @State private var date = Date.now
    @FocusState private var isTitleFocused: Bool

    // Döviz
    @State private var inputCurrency: String?
    @State private var quote: CurrencyConverter.Quote?
    @State private var manualRate = ""
    @State private var isFetchingRate = false
    @State private var rateError: String?

    // Makbuz
    @State private var receiptImage: UIImage?
    @State private var receiptData: Data?
    @State private var isChoosingReceiptSource = false
    @State private var isShowingCamera = false
    @State private var isShowingLibrary = false
    @State private var libraryItem: PhotosPickerItem?
    @State private var scan: ReceiptScan = .idle

    enum ReceiptScan: Equatable {
        case idle, reading, notFound
        /// Okunan sonuç ve uygulanmadan önceki tutar (geri almak için); `applied` false ise kullanıcı onayı bekler.
        case found(ReceiptParser.Result, previous: AmountEntry, previousCurrency: String?, applied: Bool)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                amountDisplay
                    .padding(.top, 4)

                HStack(spacing: 10) {
                    TextField("Ne için? (ör. Akşam yemeği)", text: $title)
                        .focused($isTitleFocused)
                        .submitLabel(.done)
                        .multilineTextAlignment(.center)
                        .font(.system(.body, weight: .medium))
                        .padding(.horizontal, 16)
                        .frame(height: 44)
                        .background(Color.tray, in: Capsule())
                        .softShadow()
                    receiptButton
                }
                .padding(.horizontal, 16)

                categoryChips

                VStack(spacing: 10) {
                    peopleRow("Ödeyen", selected: { paidBy == $0 }) { paidBy = $0 }
                    peopleRow("Bölünecek", selected: { splitAmong.contains($0) }) { id in
                        if splitAmong.contains(id) {
                            if splitAmong.count > 1 { splitAmong.remove(id) }
                        } else {
                            splitAmong.insert(id)
                        }
                    }
                }
                .padding(.horizontal, 16)

                Spacer(minLength: 0)

                if !isTitleFocused {
                    Keypad(entry: $entry)
                        .padding(.horizontal, 16)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }

                Button(action: save) {
                    Label("Kaydet", systemImage: "checkmark")
                }
                .buttonStyle(.primary)
                .disabled(!isValid)
                .opacity(isValid ? 1 : 0.4)
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
            }
            .animation(.spring(duration: 0.3), value: isTitleFocused)
            .background(TintGlow(tint: category.accent.base, offsetY: -260))
            .navigationTitle("Masraf ekle")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Vazgeç") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    DatePicker("Tarih", selection: $date, displayedComponents: .date)
                        .labelsHidden()
                }
            }
            .onAppear {
                if paidBy == nil { paidBy = trip.members.first?.id }
                if splitAmong.isEmpty { splitAmong = Set(trip.members.map(\.id)) }
            }
        }
    }

    // MARK: Parts

    private var currency: String { inputCurrency ?? trip.currency }
    private var isForeign: Bool { currency != trip.currency }

    /// Girilen tutarın seyahat para birimindeki karşılığı (kur yoksa nil).
    private var tripAmount: Int? {
        guard isForeign else { return entry.minorUnits }
        guard let rate = effectiveRate else { return nil }
        return CurrencyConverter.convert(minorUnits: entry.minorUnits, rate: rate)
    }

    private var effectiveRate: Decimal? {
        let typed = manualRate.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")
        if !typed.isEmpty, let value = Decimal(string: typed, locale: Locale(identifier: "en_US_POSIX")), value > 0 {
            return value
        }
        return quote?.rate
    }

    private var currencyOptions: [String] {
        var options = [trip.currency, "TRY", "EUR", "USD", "GBP"] + (inputCurrency.map { [$0] } ?? [])
        if let local = Locale(identifier: "tr_\(trip.destination.countryCode)").currency?.identifier {
            options.insert(local, at: 1)
        }
        var seen = Set<String>()
        return options.filter { seen.insert($0).inserted }
    }

    private var amountDisplay: some View {
        VStack(spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Menu {
                    ForEach(currencyOptions, id: \.self) { code in
                        Button {
                            selectCurrency(code)
                        } label: {
                            if code == currency {
                                Label("\(code) · \(AppFormat.currencySymbol(code))", systemImage: "checkmark")
                            } else {
                                Text("\(code) · \(AppFormat.currencySymbol(code))")
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 2) {
                        Text(AppFormat.currencySymbol(currency))
                            .font(.system(size: 30, weight: .semibold))
                        Image(systemName: "chevron.down")
                            .font(.system(size: 11, weight: .bold))
                    }
                    .foregroundStyle(isForeign ? Color.food : Color.ink3)
                }
                .accessibilityLabel(Text("Para birimi \(currency)"))

                Text(entry.display)
                    .font(.system(size: 56, weight: .semibold))
                    .foregroundStyle(entry.isEmpty ? Color.ink3 : Color.ink)
                    .contentTransition(.numericText())
                    .animation(.spring(duration: 0.2), value: entry.display)
            }
            .lineLimit(1)
            .minimumScaleFactor(0.4)
            .padding(.horizontal, 24)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(Text("Tutar \(AppFormat.money(entry.minorUnits, currency))"))

            if isForeign {
                conversionLine
            }

            Text(shareText)
                .font(.system(.footnote, weight: .medium))
                .foregroundStyle(Color.ink2)

            scanBanner
                .animation(.spring(duration: 0.3), value: scan)
        }
    }

    // MARK: Receipt scan

    @ViewBuilder
    private var scanBanner: some View {
        switch scan {
        case .idle:
            EmptyView()
        case .reading:
            Label("Makbuz okunuyor…", systemImage: "text.viewfinder")
                .font(.system(.footnote, weight: .semibold))
                .foregroundStyle(Color.ink2)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.track, in: Capsule())
        case .notFound:
            Label("Makbuzda tutar bulunamadı", systemImage: "exclamationmark.magnifyingglass")
                .font(.system(.footnote, weight: .semibold))
                .foregroundStyle(Color.ink2)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.track, in: Capsule())
        case let .found(result, previous, previousCurrency, applied):
            let text = AppFormat.money(result.amount, result.currency ?? currency)
            HStack(spacing: 8) {
                Image(systemName: "doc.text.viewfinder")
                Text(applied ? "Makbuzdan okundu: \(text)" : "Makbuzdaki tutar: \(text)")
                    .lineLimit(1)
                if !result.isConfident {
                    Text("· kontrol et").foregroundStyle(Color.food)
                }
                Button(applied ? "Geri al" : "Kullan") {
                    if applied {
                        entry = previous
                        let target = previousCurrency ?? trip.currency
                        if target != currency { selectCurrency(target) }
                        scan = .found(result, previous: previous, previousCurrency: previousCurrency, applied: false)
                    } else {
                        apply(result)
                    }
                }
                .fontWeight(.bold)
            }
            .font(.system(.footnote, weight: .semibold))
            .foregroundStyle(Color.success)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color.staysTint, in: Capsule())
        }
    }

    private func scanReceipt(_ image: UIImage) {
        scan = .reading
        Task {
            guard let result = await ReceiptReader.read(image) else {
                scan = .notFound
                return
            }
            if entry.isEmpty {
                apply(result)
            } else {
                scan = .found(result, previous: entry, previousCurrency: inputCurrency, applied: false)
            }
        }
    }

    private func apply(_ result: ReceiptParser.Result) {
        let previous = entry
        let previousCurrency = inputCurrency
        withAnimation(.spring(duration: 0.3)) {
            entry = AmountEntry(minorUnits: result.amount)
        }
        if let code = result.currency, code != currency {
            selectCurrency(code)
        }
        scan = .found(result, previous: previous, previousCurrency: previousCurrency, applied: true)
    }

    @ViewBuilder
    private var conversionLine: some View {
        if isFetchingRate {
            ProgressView().controlSize(.small)
        } else if let tripAmount {
            VStack(spacing: 2) {
                Text("≈ \(AppFormat.money(tripAmount, trip.currency))")
                    .font(.system(.headline, weight: .semibold))
                    .foregroundStyle(Color.food)
                if let rate = effectiveRate {
                    Text(rateCaption(rate))
                        .font(.caption)
                        .foregroundStyle(Color.ink3)
                }
            }
        } else {
            HStack(spacing: 8) {
                Text("1 \(currency) =")
                TextField("kur", text: $manualRate)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.center)
                    .frame(width: 80, height: 30)
                    .background(Color.tray, in: Capsule())
                Text(trip.currency)
            }
            .font(.system(.subheadline, weight: .medium))
            .foregroundStyle(Color.ink2)
            if let rateError {
                Text(rateError).font(.caption).foregroundStyle(Color.food).multilineTextAlignment(.center)
            }
        }
    }

    private func rateCaption(_ rate: Decimal) -> String {
        let formatted = NSDecimalNumber(decimal: rate).doubleValue
            .formatted(.number.precision(.significantDigits(1...5)).locale(AppFormat.locale))
        if let quote, manualRate.isEmpty {
            return "1 \(currency) = \(formatted) \(trip.currency) · ECB \(quote.date)"
        }
        return "1 \(currency) = \(formatted) \(trip.currency) · elle girildi"
    }

    private func selectCurrency(_ code: String) {
        inputCurrency = code
        quote = nil
        manualRate = ""
        rateError = nil
        guard code != trip.currency else { return }
        isFetchingRate = true
        Task {
            defer { isFetchingRate = false }
            do {
                quote = try await RateService.shared.quote(from: code, to: trip.currency)
            } catch {
                rateError = error.localizedDescription
            }
        }
    }

    // MARK: Receipt

    private var receiptButton: some View {
        Button {
            isChoosingReceiptSource = true
        } label: {
            Group {
                if let receiptImage {
                    Image(uiImage: receiptImage)
                        .resizable()
                        .scaledToFill()
                } else {
                    Image(systemName: "doc.text.viewfinder")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Color.ink)
                }
            }
            .frame(width: 44, height: 44)
            .background(Color.tray)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .softShadow()
        }
        .buttonStyle(.plain)
        .accessibilityLabel(receiptImage == nil ? "Makbuz ekle" : "Makbuzu değiştir")
        .confirmationDialog("Makbuz", isPresented: $isChoosingReceiptSource, titleVisibility: .visible) {
            if UIImagePickerController.isSourceTypeAvailable(.camera) {
                Button("Fotoğraf çek") { isShowingCamera = true }
            }
            Button("Galeriden seç") { isShowingLibrary = true }
            if receiptImage != nil {
                Button("Makbuzu kaldır", role: .destructive) {
                    receiptImage = nil
                    receiptData = nil
                    scan = .idle
                }
            }
        }
        .photosPicker(isPresented: $isShowingLibrary, selection: $libraryItem, matching: .images)
        .onChange(of: libraryItem) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) {
                    receiptData = data
                    receiptImage = image
                    scanReceipt(image)
                }
                libraryItem = nil
            }
        }
        .fullScreenCover(isPresented: $isShowingCamera) {
            CameraPicker(onCapture: { image in
                receiptImage = image
                receiptData = image.jpegData(compressionQuality: 0.85)
                scanReceipt(image)
            }, onClose: { isShowingCamera = false })
            .ignoresSafeArea()
        }
    }

    private var shareText: String {
        let count = splitAmong.count
        guard let amount = tripAmount, amount > 0, count > 0 else { return "\(count) kişi arasında bölünecek" }
        let share = Settlement.split(amount, into: count).first ?? 0
        return count == 1 ? "Tek kişiye ait" : "Kişi başı \(AppFormat.money(share, trip.currency)) · \(count) kişi"
    }

    private var categoryChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(SpendCategory.allCases, id: \.self) { item in
                    let isSelected = item == category
                    Button {
                        withAnimation(.spring(duration: 0.25)) { category = item }
                    } label: {
                        Label(item.title, systemImage: item.symbol)
                            .font(.system(.subheadline, weight: .semibold))
                            .foregroundStyle(isSelected ? Color.white : item.accent.base)
                            .padding(.horizontal, 14)
                            .frame(height: 38)
                            .background(isSelected ? item.accent.base : item.accent.tint, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                }
            }
            .padding(.horizontal, 16)
        }
    }

    private func peopleRow(_ label: String, selected: @escaping (UUID) -> Bool,
                           toggle: @escaping (UUID) -> Void) -> some View {
        HStack(spacing: 12) {
            Text(label)
                .font(.tCaption)
                .foregroundStyle(Color.ink3)
                .frame(width: 72, alignment: .leading)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(trip.members) { member in
                        let isOn = selected(member.id)
                        Button {
                            withAnimation(.spring(duration: 0.2)) { toggle(member.id) }
                        } label: {
                            AvatarView(member: member, size: 38)
                                .overlay(Circle().strokeBorder(isOn ? Color.ink : .clear, lineWidth: 2.5).padding(-4))
                                .opacity(isOn ? 1 : 0.35)
                                .saturation(isOn ? 1 : 0)
                                .padding(4)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(Text(member.name))
                        .accessibilityAddTraits(isOn ? .isSelected : [])
                    }
                }
            }
        }
    }

    private var isValid: Bool {
        (tripAmount ?? 0) > 0 && paidBy != nil && !splitAmong.isEmpty
    }

    private func save() {
        guard let paidBy, let amount = tripAmount, isValid else { return }
        let trimmed = title.trimmingCharacters(in: .whitespaces)
        // Üye sırasını koru ki artan kuruşların kime düştüğü tutarlı olsun.
        let split = trip.members.map(\.id).filter { splitAmong.contains($0) }
        let receipt = receiptData.flatMap { try? CoverImageStore.receipts.save($0) }
        let expense = Expense(title: trimmed.isEmpty ? category.title : trimmed, amount: amount,
                              category: category, paidBy: paidBy, splitAmong: split, date: date,
                              originalAmount: isForeign ? entry.minorUnits : nil,
                              originalCurrency: isForeign ? currency : nil,
                              receiptPhoto: receipt)
        store.update(trip.id) { $0.expenses.append(expense) }
        dismiss()
    }
}

/// Hesap makinesi tarzı rakam tuşları.
struct Keypad: View {
    @Binding var entry: AmountEntry

    private enum Key: Hashable {
        case digit(Int), decimal, backspace
    }

    private let rows: [[Key]] = [
        [.digit(1), .digit(2), .digit(3)],
        [.digit(4), .digit(5), .digit(6)],
        [.digit(7), .digit(8), .digit(9)],
        [.decimal, .digit(0), .backspace],
    ]

    var body: some View {
        VStack(spacing: 8) {
            ForEach(rows, id: \.self) { row in
                HStack(spacing: 8) {
                    ForEach(row, id: \.self) { key in
                        Button {
                            press(key)
                        } label: {
                            label(for: key)
                                .frame(maxWidth: .infinity)
                                .frame(height: 52)
                                .background(Color.tray, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                                .softShadow()
                        }
                        .buttonStyle(KeyPressStyle())
                    }
                }
            }
        }
        .sensoryFeedback(.impact(weight: .light), trigger: entry)
    }

    @ViewBuilder
    private func label(for key: Key) -> some View {
        switch key {
        case let .digit(value):
            Text("\(value)").font(.system(size: 24, weight: .medium)).foregroundStyle(Color.ink)
        case .decimal:
            Text(",").font(.system(size: 26, weight: .semibold)).foregroundStyle(Color.ink)
                .accessibilityLabel("Virgül")
        case .backspace:
            Image(systemName: "delete.left").font(.system(size: 20, weight: .medium)).foregroundStyle(Color.ink)
                .accessibilityLabel("Sil")
        }
    }

    private func press(_ key: Key) {
        switch key {
        case let .digit(value): entry.append(digit: value)
        case .decimal: entry.appendDecimalSeparator()
        case .backspace: entry.backspace()
        }
    }
}

private struct KeyPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .opacity(configuration.isPressed ? 0.8 : 1)
            .animation(.spring(duration: 0.15), value: configuration.isPressed)
    }
}

struct EditBudgetSheet: View {
    @Environment(TripStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let trip: Trip

    @State private var limits: [SpendCategory: String] = [:]

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ForEach(SpendCategory.allCases, id: \.self) { category in
                        HStack {
                            Label(category.title, systemImage: category.symbol)
                                .foregroundStyle(category.accent.base)
                            Spacer()
                            TextField("0", text: Binding(
                                get: { limits[category] ?? "" },
                                set: { limits[category] = $0 }
                            ))
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(maxWidth: 120)
                            Text(trip.currency).foregroundStyle(Color.ink2)
                        }
                    }
                } footer: {
                    Text("Boş bırakılan kategoriler bütçede gösterilmez (harcama olmadıkça).")
                }
            }
            .navigationTitle("Bütçe limitleri")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Vazgeç") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Kaydet", action: save)
                }
            }
            .onAppear {
                for line in trip.budget {
                    limits[line.category] = String(line.limit / 100)
                }
            }
        }
    }

    private func save() {
        let lines = SpendCategory.allCases.compactMap { category -> BudgetLine? in
            guard let text = limits[category], let minor = AppFormat.parseMinor(text), minor > 0 else { return nil }
            return BudgetLine(category: category, limit: minor)
        }
        store.update(trip.id) { $0.budget = lines }
        dismiss()
    }
}
