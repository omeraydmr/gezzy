# Seyahat ekranı düzeni — tasarım

Tarih: 2026-11-04 · Durum: onay bekliyor

## Sorun

- Kapak (300 pt) ve iki satırlık bilet kartı ilk ekranı dolduruyor; sekme içeriği ancak kaydırınca başlıyor.
- 7 sekme yatay kayıyor; Valiz, Vize, Ekip, Anılar ekran dışında kalıyor, "Vali…" diye kesiliyor.
- Kaydırınca sekme çubuğu yukarıda kalıyor; başka sekmeye geçmek için en üste dönmek gerekiyor.

## Hedef

İlk ekranda sekme içeriğinin başı görünsün, tüm sekmeler tek bakışta seçilebilsin ve sekme çubuğu kaydırırken hep
erişilebilir olsun.

Kapsam dışı: sekmelerin kendi içerikleri (Plan, Bütçe vb.), Seyahatler listesi, "Bugün" modu.

## 1. Başlık

- **Kapak 180 pt** (`TripDetailView.heroHeight`): başlık, ülke/şehir satırı ve geri sayım etiketi aynı yerde.
  Başlığın okunması için alttaki karartma güçlenir (alt %55'te siyah %0 → %60). Aşağı çekince esneme ve yukarı
  kayınca gezinme çubuğuna devretme davranışı aynen kalır.
- **İnce bilet satırı** (`TripStub` yerine tek satır kart, ~64 pt):
  - Uçuş varsa: `IST 08:25 ✈ 10:45 CPH` · `19–23 Kas · 4 gece` · sağda avatar yığını (en çok 3).
  - Uçuş yoksa: `📅 19–23 Kas · 4 gece` · avatarlar.
  - Koltuk ve uçuş süresi satırdan kalkar (Rezervasyon sekmesinde zaten var). Dokununca Rezervasyon sekmesine
    geçer (`openReservations`).
  - "Kilit ekranında göster" düğmesi bilet satırının altında değil, `•••` menüsüne taşınır.
- Görüntüleyici uyarısı ("Bu seyahati yalnızca görüntüleyebilirsin") bilet satırının hemen altında küçük etiket olarak
  kalır.

## 2. Sekmeler

**Dört sekme:** `Plan` · `Rezervasyon` · `Para` · `Daha fazla`.

- `Para` = bugünkü Bütçe sekmesi (ad değişir, içerik aynı).
- `Daha fazla` içeriği: 2×2 ızgara, her karo simge + ad + tek satır özet:
  - Valiz — "3/7 hazır"
  - Vize — "Hazır ✓" ya da "2 kişi eksik"
  - Ekip — "3 kişi"
  - Anılar — "42 fotoğraf" (izin yoksa "Fotoğrafları bağla")
  Karoya dokununca o bölüm aynı yerde açılır; üstünde "‹ Daha fazla" geri bağlantısı ve bölüm adı. Sekme çubuğunun
  dördüncü düğmesi açık bölümün adını ve simgesini gösterir ("Valiz"), tekrar dokununca ızgaraya döner.
- Bugünkü `TripSection` değerleri korunur (`plan, reservations, money, packing, visa, crew, memories`); bildirim ve
  widget derin bağlantıları (`initialSection: .packing` vb.) `Daha fazla` sekmesinde ilgili bölümü açar.
- Dört düğme genişliği eşit bölüşür (yatay kaydırma yok); seçili düğme palet `tint` dolgulu kapsül, metin beyaz;
  diğerleri `ink2` metin + `ink3` simge.

## 3. Sabitlenen sekme çubuğu

- `ScrollView` içinde `LazyVStack(pinnedViews: [.sectionHeaders])`; sekme çubuğu bölüm başlığı olarak üstte
  sabitlenir.
- Sabitlenince arka plan sistem cam malzemesi (`.bar` / `.regularMaterial`), altında ince ayraç; gezinme çubuğu
  (başlık "Kopenhag") ile birlikte tek bir üst bant gibi görünür.
- Sekme değişince içerik başa kayar: sekme çubuğu sabitliyse içerik çubuğun hemen altından başlar (kapak yeniden
  görünmez); değilse konum korunur.

## 4. Erişilebilirlik ve hareket

- Sekme düğmeleri en az 44 pt yükseklik; `.isSelected` özelliği; Dynamic Type'ta etiket sığmazsa yalnız simge +
  erişilebilirlik etiketi.
- Seçili kapsül geçişi `matchedGeometryEffect`; Reduce Motion açıksa animasyonsuz.

## 5. Kod düzeni

- `Features/TripDetail/TripDetailView.swift`: `heroHeight` 180, pinned layout, yeni `SectionTabs` (4 düğme),
  `TripStub` → `TripTicketRow`, `•••` menüsüne kilit ekranı öğesi.
- Yeni: `Features/TripDetail/MoreSections.swift` (2×2 ızgara + özetler + iç gezinme).
- `Localizable.xcstrings`: "Para", "Daha fazla", özet metinleri (en karşılıklarıyla).

## 6. Doğrulama

- Simülatör (iPhone Air ve küçük ekran iPhone SE boyutu): ilk ekranda Plan'ın gün çipleri görünür; kaydırınca sekme
  çubuğu sabitlenir; Daha fazla → Valiz → geri; Rezervasyon'a bilet satırından geçiş; açık/koyu tema; en büyük
  Dynamic Type; görüntüleyici rolü.
