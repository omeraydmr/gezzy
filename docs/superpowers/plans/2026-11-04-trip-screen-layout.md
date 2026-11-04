# Seyahat ekranı düzeni Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Seyahat ekranında içerik ilk ekranda başlasın: 180 pt kapak, tek satır bilet, dört eşit sekme (Plan · Rezervasyon · Para · Daha fazla) ve kaydırırken sabitlenen sekme çubuğu.

**Architecture:** Tüm değişiklik `Features/TripDetail/` altında. `TripSection` (7 değer) korunur; üstüne 4 değerli `TripTab` ve "Daha fazla" içindeki açık bölüm durumu gelir. Sabitleme `LazyVStack(pinnedViews: [.sectionHeaders])` ile.

**Tech Stack:** SwiftUI iOS 17, Swift 6.

**Spec:** `docs/superpowers/specs/2026-11-04-trip-screen-layout-design.md`

## Global Constraints

- Build: `cd ios && xcodebuild -project Gezzy.xcodeproj -scheme Gezzy -destination 'platform=iOS Simulator,name=iPhone Air' build` (no `-quiet`); yeni dosya eklenince önce `cd ios && xcodegen generate`.
- `TripDetailView.TripSection` değerleri ve `init(tripID:initialSection:)` aynen kalır (widget, bildirim ve `TripGlance` derin bağlantıları kullanıyor). `.packing/.visa/.crew/.memories` → "Daha fazla" sekmesinde o bölüm açık.
- Kapak yüksekliği 180 pt; esneme ve gezinme çubuğuna devretme davranışı korunur.
- Sekme düğmeleri ekran genişliğini eşit bölüşür, yatay kaydırma yok, yükseklik ≥ 44 pt, seçili olan `tint` dolgulu kapsül + beyaz metin, `.isSelected`; Reduce Motion açıksa kapsül geçişi animasyonsuz.
- Görüntüleyici (`!canEdit`) için sekme içerikleri bugünkü gibi `.disabled` (Anılar hariç).
- Yeni metinler Türkçe, `en` değeri `ios/Gezzy/Resources/Localizable.xcstrings`'e elle eklenir; derleme yüzlerce satır silerse dosyayı geri al, yalnız kendi anahtarlarını ekle.
- Kod yorumları Türkçe, kısa. Commit sonu: `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`. Yalnızca değiştirdiğin dosyaları stage et. Simülatöre dokunma (controller doğrular).

---

### Task 1: Kompakt kapak ve tek satır bilet

**Files:** Modify `ios/Gezzy/Features/TripDetail/TripDetailView.swift`, `Localizable.xcstrings`

- [ ] **Step 1:** `heroHeight` 300 → 180. `TripHero` içindeki alt karartmayı güçlendir: `LinearGradient(stops: [.init(color: .black.opacity(0.35), location: 0), .init(color: .clear, location: 0.3), .init(color: .clear, location: 0.45), .init(color: .black.opacity(0.6), location: 1)])`. Başlık bloğunun alt boşluğu (`.padding(.bottom, 60)`) bilet satırının bindirmesine göre ayarlanır (bilet `-44` yerine `-28` bindirilir; başlık `padding(.bottom, 40)`). Başlık tek satır (`lineLimit(1)`, `minimumScaleFactor(0.6)`); `onChange` çöküş eşiği `height - 140` → `height - 100`.
- [ ] **Step 2:** `TripStub` yerine `TripTicketRow(trip:)` (aynı dosyada): `tray` kart, 14 pt dikey dolgu, tek `HStack`:
  - Uçuş varsa: `fromCode` (semibold) + kalkış saati (`AppFormat.time(_, timeZone:)`) · küçük `airplane` simgesi (tint) · varış saati + `toCode`.
  - Ayırıcı nokta, sonra `"\(AppFormat.dateRange(start, end)) · \(trip.nights()) gece"` (`.footnote`, `ink2`, `lineLimit(1)`, `minimumScaleFactor(0.8)`).
  - `Spacer`, `AvatarStack(members:size: 26, limit: 3)`.
  - Uçuş yoksa ilk bölüm `calendar` simgesiyle yalnız tarih + gece.
  - Tüm satır `Button` → `openReservations()` (ortam değeri); erişilebilirlik etiketi "Rezervasyonları aç".
  - Üstteki `Capsule().fill(tint)` aksanı kalır.
- [ ] **Step 3:** "Kilit ekranında göster/kaldır" düğmesi `TripTicketRow`'dan kalkar; `coverMenu` içine `LiveActivityController.canStart(for:)` doğruysa `Button(running ? "Kilit ekranından kaldır" : "Kilit ekranında göster", systemImage: running ? "lock.slash" : "lock.iphone")` (durum `@State isLiveActivityRunning`, `onAppear`'da `isRunning(for:)`).
- [ ] **Step 4:** Build; commit `"Compact trip header with a one-line ticket row"`.

### Task 2: Dört sekme ve "Daha fazla"

**Files:** Modify `TripDetailView.swift`; Create `ios/Gezzy/Features/TripDetail/MoreSections.swift`; `Localizable.xcstrings`

**Interfaces — Produces:** `enum TripTab: CaseIterable { case plan, reservations, money, more }`; `TripSection.tab: TripTab` (`.plan→.plan`, `.reservations→.reservations`, `.money→.money`, diğerleri `.more`); `TripSection.moreItems: [TripSection] = [.packing, .visa, .crew, .memories]`; `MoreSections(trip:open:)`.

- [ ] **Step 1: Durum** — `TripDetailView`'da `@State section: TripSection` kalır (gerçek açık bölüm) ve `@State moreOpen: Bool` (Daha fazla'da bir bölüm açık mı). `init`: `initialSection` `.more` grubundansa `moreOpen = true`. Seçili sekme = `section.tab`; "Daha fazla" sekmesine dokununca: zaten `.more` ve `moreOpen` ise `moreOpen = false` (ızgaraya dön), değilse `section`'ı son açık more bölümü yerine ızgara göstermek için `moreOpen = false` ve `tab = .more` (bunu `@State selectedTab: TripTab` ile tut: `selectedTab` ve `section` birlikte güncellenir).
- [ ] **Step 2: `SectionTabs`** — 4 eşit düğme (`HStack(spacing: 4)` içinde `.frame(maxWidth: .infinity)`), `padding(4)` gri kapsül zemin (`Color.track`). Düğme: simge + etiket (`Label`), `.font(.system(.subheadline, weight: .semibold))`, `minHeight: 44`. Etiketler: "Plan", "Rezervasyon", "Para", "Daha fazla"; "Daha fazla" sekmesi `moreOpen` ise açık bölümün adı ve simgesi (`section.title`, `section.symbol`). Seçili: `tint` dolgulu kapsül (`matchedGeometryEffect`, Reduce Motion'da `animation(nil)`), metin/simge beyaz; değilse metin `ink2`, simge `ink3`. `dynamicTypeSize >= .accessibility1` ise yalnız simge, etiket `accessibilityLabel`. `.accessibilityAddTraits(isSelected ? .isSelected : [])`. `TripSection.money.title` "Para" olur (`Bütçe` başlığı Para sekmesinin kartında kalır).
- [ ] **Step 3: `MoreSections`** — `LazyVGrid` 2 sütun, 12 aralık; her karo `tray` 18 köşe, 14 dolgu: simge (`section.symbol`, palet `tripText` rengi, 32×32 `soft` zemin), ad (`tBodyStrong`), özet (`.footnote`, `ink2`, `lineLimit(1)`):
  - Valiz: boşsa "Liste boş", değilse "\(packed)/\(count) hazır".
  - Vize: `TripGlance`'taki kural (bekleyen yoksa "Hazır ✓", varsa "\(n) kişi bekliyor"); üye yoksa "Kişi ekle".
  - Ekip: "\(members.count) kişi".
  - Anılar: seyahat bittiyse "Fotoğraflar ve paylaşım kartı", değilse "Seyahatten sonra".
  Dokununca `open(section)`. `TripGlance`'taki vize/valiz özet mantığını küçük paylaşılan yardımcıya taşı (`TripSummaries` enum, `@MainActor` gerekirse `store` parametresiyle) ve iki yer de onu kullansın.
- [ ] **Step 4: İçerik** — `selectedTab == .more && !moreOpen` → `MoreSections`; `moreOpen` → üstte `Button { moreOpen = false } label: { Label("Daha fazla", systemImage: "chevron.left") }` (`.footnote` semibold, `tripText`) ve altında bugünkü bölüm görünümü.
- [ ] **Step 5:** Build; commit `"Four trip tabs with a More grid"`.

### Task 3: Sabitlenen sekme çubuğu

**Files:** Modify `TripDetailView.swift`

- [ ] **Step 1:** `ScrollView { VStack { ... } }` → `ScrollViewReader { proxy in ScrollView { LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) { hero; ticket; viewerNote; Section { content } header: { SectionTabs(...) } } } }`. Başlık arka planı: sabitlendiğinde cam (`.background(.bar)`) + alt `Divider().opacity(isPinned ? 1 : 0)`; sabitlenmemişken saydam. Sabitlenme durumu: başlığın `GeometryReader` ile `frame(in: .scrollView).minY <= navBarBottom` (bir `@State isTabsPinned`), ya da hero'nun çöküş durumu (`isHeroCollapsed`) ile birlikte.
- [ ] **Step 2:** Sekme değişince: `isTabsPinned` ise `proxy.scrollTo("tabs", anchor: .top)` (başlığa `id("tabs")`), değilse konum korunur. `withAnimation` Reduce Motion'da yok.
- [ ] **Step 3:** `.ignoresSafeArea(edges: .top)` ve gezinme çubuğu davranışı (başlık, `toolbarBackground`) korunur; sabit sekme çubuğu gezinme çubuğunun hemen altında oturur (üst güvenli alan + çubuk yüksekliği). Görüntüleyicide içerik `.disabled` kuralı aynen.
- [ ] **Step 4:** Build; commit `"Pin the trip tabs while scrolling"`.
