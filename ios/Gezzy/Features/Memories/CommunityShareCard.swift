import SwiftUI
import GezzyKit

/// Seyahat bitince: gidilen yerleri beğeni/beğenmeme ile topluluk öneri havuzuna paylaşma onayı.
/// Yalnızca yer adı, konumu, türü, oy ve aynı gün art arda gidilen yer çiftleri gider.
struct CommunityShareCard: View {
    @Environment(\.tripPalette) private var palette
    @Environment(\.tripText) private var tintText
    @Environment(Entitlements.self) private var entitlements
    @Environment(TripStore.self) private var store
    let trip: Trip
    /// Fotoğraflarla doğrulanan duraklar.
    let verified: Set<UUID>

    @State private var choice: CommunityService.Choice?
    @State private var ratings: [UUID: Int] = [:]
    @State private var excluded: Set<UUID> = []
    @State private var isExpanded = false
    @State private var isSending = false
    @State private var errorText: String?
    @State private var isWithdrawing = false
    @State private var withdrawError: String?
    @State private var votesSaved = false
    private var service: CommunityService { .shared }
    private var reporter: RouteReporter { .shared }

    /// Rota raporu durumu; nil ise bugünkü kart.
    private enum ReportStatus { case sent, pending, notSent }

    private var reportStatus: ReportStatus? {
        switch reporter.state(for: trip.id) {
        // Gönderilmiş rapor tercih ya da premium değişse de görünür ve geri alınabilir.
        case .sent: return .sent
        case .withdrawn, .skippedPremium: return .notSent
        case .rejected: return nil
        case .pending, nil:
            // Yalnızca bu cihazın gerçekten göndereceği seyahatlerde "Gönderilecek".
            guard reporter.choice == .yes, !entitlements.isPremium,
                  RouteReport.willSend(trip: trip, me: store.me.id) else { return nil }
            return .pending
        }
    }

    var body: some View {
        Group {
            switch reportStatus {
            case .sent: sentCard.tray()
            case .pending: pendingCard.tray(padding: 14)
            case .notSent:
                VStack(alignment: .leading, spacing: 8) {
                    Label("Gönderilmedi", systemImage: "nosign")
                        .font(.footnote)
                        .foregroundStyle(Color.ink2)
                        .padding(.horizontal, 4)
                    communityCard
                }
            case nil: communityCard
            }
        }
        .onAppear { choice = service.choice(for: trip) }
    }

    // MARK: Rota raporu

    private var sentCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Label("Rotan Gezzy'ye gönderildi", systemImage: "checkmark.circle.fill")
                    .font(.tBodyStrong)
                    .foregroundStyle(Color.ink)
                Spacer(minLength: 4)
                if isWithdrawing {
                    ProgressView()
                } else {
                    Button("Geri al") { Task { await withdraw() } }
                        .buttonStyle(PillButtonStyle())
                }
            }
            if let withdrawError {
                Label(withdrawError, systemImage: "exclamationmark.triangle").font(.footnote).foregroundStyle(Color.food)
            }
            votingSection(sendTitle: String(localized: "Oyları gönder"))
            if votesSaved {
                Label("Oyların kaydedildi.", systemImage: "heart.fill").font(.footnote).foregroundStyle(Color.ink2)
            }
        }
    }

    private var pendingCard: some View {
        HStack(spacing: 10) {
            Label("Gönderilecek", systemImage: "clock")
                .font(.tBody)
                .foregroundStyle(Color.ink2)
            Spacer(minLength: 4)
            Button("Bu seyahati gönderme") {
                withAnimation {
                    reporter.exclude(trip)
                    choice = service.choice(for: trip)
                }
            }
            .buttonStyle(PillButtonStyle())
        }
    }

    private func withdraw() async {
        isWithdrawing = true
        defer { isWithdrawing = false }
        withdrawError = nil
        do {
            try await reporter.withdraw(trip)
            withAnimation { choice = service.choice(for: trip) }
        } catch {
            withdrawError = String(localized: "Geri alınamadı; internet bağlantını kontrol et.")
        }
    }

    // MARK: Topluluk kartı

    @ViewBuilder
    private var communityCard: some View {
        Group {
            if choice == .shared {
                Label("Yerlerin topluluk önerilerine eklendi. Teşekkürler!", systemImage: "heart.fill")
                    .font(.tBody)
                    .foregroundStyle(Color.ink2)
                    .tray(padding: 14)
            } else if choice == nil {
                prompt.tray()
            }
        }
    }

    private var prompt: some View {
        let stops = CommunityPlaces.eligibleStops(in: trip)
        return VStack(alignment: .leading, spacing: 12) {
            Label("Gittiğin yerleri diğer gezginlere öner", systemImage: "person.3.sequence.fill")
                .font(.tBodyStrong)
                .foregroundStyle(Color.ink)
            Text("Beğendiklerini işaretle; en az üç gezginin gittiği yerler Önerilen yerler'de çıkar. Yalnızca yer adı, konumu, oyun ve aynı gün hangi yerden sonra nereye gittiğin paylaşılır — adın, tarihlerin, notların ve ekibin paylaşılmaz.")
                .font(.footnote)
                .foregroundStyle(Color.ink2)

            stopList(stops)

            if let errorText {
                Label(errorText, systemImage: "exclamationmark.triangle").font(.footnote).foregroundStyle(Color.food)
            }

            HStack(spacing: 10) {
                Button {
                    Task { await share() }
                } label: {
                    if isSending { ProgressView().tint(tintText) } else { Text("Paylaş") }
                }
                .buttonStyle(PillButtonStyle(tint: tintText, soft: .soft(palette)))
                .disabled(isSending || stops.count == excluded.count)
                Button("Paylaşma") {
                    service.setChoice(.declined, for: trip)
                    withAnimation { choice = .declined }
                }
                .buttonStyle(PillButtonStyle())
            }
        }
    }

    /// Gönderilmiş rotada oylar sonradan eklenebilir; sunucu aynı katkıyı günceller.
    private func votingSection(sendTitle: String) -> some View {
        let stops = CommunityPlaces.eligibleStops(in: trip)
        return VStack(alignment: .leading, spacing: 12) {
            stopList(stops)
            if let errorText {
                Label(errorText, systemImage: "exclamationmark.triangle").font(.footnote).foregroundStyle(Color.food)
            }
            if isExpanded {
                Button {
                    Task { await share() }
                } label: {
                    if isSending { ProgressView().tint(tintText) } else { Text(sendTitle) }
                }
                .buttonStyle(PillButtonStyle(tint: tintText, soft: .soft(palette)))
                .disabled(isSending || stops.count == excluded.count)
            }
        }
    }

    @ViewBuilder
    private func stopList(_ stops: [Stop]) -> some View {
            Button {
                withAnimation(.spring(duration: 0.3)) { isExpanded.toggle() }
            } label: {
                HStack {
                    Text("\(stops.count - excluded.count) yer · oyla")
                        .font(.system(.subheadline, weight: .semibold))
                    Spacer()
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down").font(.caption.weight(.semibold))
                }
                .foregroundStyle(Color.ink)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                ForEach(stops) { stop in
                    row(stop)
                }
            }
    }

    private func row(_ stop: Stop) -> some View {
        let isExcluded = excluded.contains(stop.id)
        let rating = ratings[stop.id] ?? 0
        return HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                Text(stop.name).font(.subheadline).foregroundStyle(isExcluded ? Color.ink3 : Color.ink).strikethrough(isExcluded)
                if verified.contains(stop.id) {
                    Label("Fotoğraflarla doğrulandı", systemImage: "checkmark.seal").font(.caption2).foregroundStyle(Color.success)
                }
            }
            Spacer(minLength: 4)
            vote(stop, value: 1, symbol: "hand.thumbsup", isOn: rating == 1, label: String(localized: "Beğendim"))
            vote(stop, value: -1, symbol: "hand.thumbsdown", isOn: rating == -1, label: String(localized: "Beğenmedim"))
            Button {
                if isExcluded { excluded.remove(stop.id) } else { excluded.insert(stop.id) }
            } label: {
                Image(systemName: isExcluded ? "eye.slash.fill" : "eye").frame(width: 32, height: 32)
            }
            .buttonStyle(.plain)
            .foregroundStyle(isExcluded ? Color.food : Color.ink3)
            .accessibilityLabel(isExcluded ? String(localized: "Paylaşıma ekle") : String(localized: "Paylaşma"))
        }
        .opacity(isExcluded ? 0.6 : 1)
    }

    private func vote(_ stop: Stop, value: Int, symbol: String, isOn: Bool, label: String) -> some View {
        Button {
            ratings[stop.id] = isOn ? 0 : value
        } label: {
            Image(systemName: isOn ? symbol + ".fill" : symbol).frame(width: 32, height: 32)
        }
        .buttonStyle(.plain)
        .foregroundStyle(isOn ? (value > 0 ? Color.success : Color.food) : Color.ink3)
        .disabled(excluded.contains(stop.id))
        .accessibilityLabel(label)
    }

    private func share() async {
        guard let contribution = CommunityPlaces.contribution(for: trip, ratings: ratings, verified: verified,
                                                              excluded: excluded) else { return }
        isSending = true
        defer { isSending = false }
        errorText = nil
        do {
            try await service.contribute(contribution)
            if reportStatus == .sent {
                withAnimation { votesSaved = true; isExpanded = false }
                return
            }
            service.setChoice(.shared, for: trip)
            withAnimation { choice = .shared }
        } catch CommunityService.Failure.rejected(429) {
            errorText = String(localized: "Bugün için paylaşım sınırına ulaştın; yarın tekrar dene.")
        } catch {
            errorText = String(localized: "Paylaşılamadı; internet bağlantını kontrol et.")
        }
    }
}
