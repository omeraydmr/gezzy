# Rezervasyon sekmesi, günün başı/sonu ve uçuş günleri — tasarım

Tarih: 2026-11-02 · Durum: onaylandı

## Sorun

- Uçuşlar ve Konaklama kartları Plan sekmesinde, rotayla aynı yerde. Kullanıcıya mantıksız geliyor; Plan uzuyor.
- Kart boşken aynı iki işlem iki yerde: başlıktaki "+" menüsü ve alttaki iki büyük siyah düğme ("Elle ekle", "İçe
  aktar").
- Günün rotası sabah otelinden başlıyor ama akşam o gecenin oteline dönmüyor; otel değişen gün yeni otelde bitmiyor.
- Uçuş günleri plana yansımıyor: ilk gün iniş, pasaport, bagaj ve şehre ulaşım süresi; son gün havalimanına erken
  gitme gereği hesaba katılmıyor.

## Hedef

1. Rezervasyonlar (uçuş, konaklama) kendi sekmesinde; Plan yalnızca rota.
2. Her kartta tek, belirgin bir ekleme yolu.
3. Her gün o sabahın konaklamasından başlar, o gecenin konaklamasında biter.
4. İlk ve son gün havalimanıyla başlar/biter; zaman tamponları ve uyarılarla gerçekçi plan.

Kapsam dışı: canlı uçuş takibi, havalimanı bekleme süresi API'leri, toplu taşıma güzergâhı hesaplama.

## 1. Rezervasyon sekmesi

- `TripDetailView.Tab` sırası: **Plan · Rezervasyon · Bütçe · Valiz · Vize · Ekip · Anılar**. Yeni case `reservations`,
  başlık "Rezervasyon", ikon `suitcase.rolling.fill`.
- Yeni `ios/Gezzy/Features/Plan/ReservationsSection.swift`: `FlightsCard` ve `LodgingCard`'ı alt alta gösterir. Kartların
  içi (listeler, düzenleme, içe aktarma, konaklamasız gece uyarısı) aynen kalır.
- `PlanSection` bu iki kartı artık göstermez; Plan'da harita, gün seçici, gün listesi, "Durak ekle" ve Fikirler kalır.
- Plan'daki otel ve uçuş satırlarına (bkz. 3, 4) dokunmak Rezervasyon sekmesine geçirir. Sekme seçimi
  `TripDetailView`'da bir `@State`; geçiş, environment üzerinden verilen bir eylemle (`openReservations`) yapılır.
- Viewer yetkisi: Rezervasyon sekmesi Plan'daki aynı `canEdit` kuralına uyar (salt okunur kullanıcı ekleyemez).

## 2. Kartlarda ekleme

- Başlıktaki "+" daha belirgin: dolu, sekme renginde (`tripTint`) daire, beyaz ikon. Menü aynı: "Elle ekle" ve
  "Biletten içe aktar" (uçuş) / "Rezervasyondan içe aktar" (konaklama).
- Kart boşken iki büyük düğme kalkar. Yerine ortak bir `AddPlaceholder` satırı: kesik çizgili yuvarlak kenarlı kutu,
  "＋ Uçuş ekle" başlığı ve "elle ya da biletten" alt metni (konaklamada "＋ Konaklama ekle", "elle ya da
  rezervasyondan"). Satır, başlıktaki menünün aynısını açan bir `Menu`'dür.
- `EmptyHint` açıklama metni de kalkar; bilgi placeholder alt metninde.
- Kart doluyken yalnızca başlıktaki "+".

## 3. Günün başlangıç ve bitiş noktası

GezzyKit'e saf bir "gün çapası" hesabı eklenir.

```
DayAnchors(day) -> (start: Anchor?, end: Anchor?)
Anchor = .lodging(Lodging) | .airport(Airports.Airport, flight: FlightSegment)
```

Kurallar (öncelik sırasıyla):

- **start**
  1. O gün varış uçuşu varsa (uçuşun varış tarihi, varış saat diliminde bu gün; varış havalimanı seyahatin bu günkü
     ülkesinde) → `.airport(varış havalimanı)`.
  2. Yoksa `lodging(forMorningOf: day)` → `.lodging`.
- **end**
  1. Günün son uçuşu bu günün şehrinden (seyahatin bu günkü ülkesindeki havalimanından) kalkıyor ve bu günden sonra
     aynı gün başka bir varış uçuşu yoksa → `.airport(kalkış havalimanı)`. Örnek: dönüş günü LIS→IST.
     Şehir değiştirilen günde (sabah LIS→OPO) gün varılan şehre aittir (`Trip.leg(on:)`): start OPO havalimanı,
     end o gecenin Porto oteli; sabahki kalkış bu günün listesine çapa olarak girmez.
  2. Yoksa yeni `lodging(forNightOf: day)` → `.lodging`. Tanım: `checkIn ≤ gün < checkOut` (gün başlangıçlarıyla).
  3. Yoksa nil.
- Otel değişen gün: start eski otel (sabah), end yeni otel (gece).
- Havalimanı koordinatı `Airports.airport(code).coordinate`'tan; koordinatı olmayan havalimanı çapa olmaz (bir
  sonraki kurala düşülür).

Kullanıldığı yerler:

- **Gün listesi** (`PlanSection`): start satırı (`LodgingStartRow` ya da yeni havalimanı satırı) → duraklar →
  son duraktan end'e `HopRow` → end satırı (yeni `LodgingEndRow` ya da havalimanı satırı). Durak yoksa yalnızca
  başlangıç ve bitiş satırları ve aradaki hop.
- **Harita**: rota çizgisi start → duraklar → end. Start ve end pinleri: otel yeşil yatak, havalimanı mavi uçak ikonu.
- **Gün özeti** (`StatChip`'ler): toplam mesafe ve yürüme süresi start→…→end üzerinden.
- **En kısa rota** (`RouteOptimizer.order(_:from:dayStart:)`) ve **otomatik rota** (`ItineraryPlanner`): isteğe
  bağlı bitiş noktası `to:` alır. Sıralama maliyeti son duraktan bitişe dönüşü de içerir. Bitiş verilmezse
  davranış bugünküyle aynı.

## 4. Uçuş günleri

Yeni saf hesap `FlightDayTiming` (GezzyKit). Tüm saatler o günün yerel saatinde, gün başından itibaren dakika.

### Sabitler (tek yerde, `FlightDayTiming` içinde)

| Ad | Değer | Anlam |
|---|---|---|
| `departureLeadInternational` | 180 dk | Dış hat: kalkıştan önce havalimanında olma |
| `departureLeadShort` | 120 dk | Schengen içi ya da iç hat |
| `arrivalExitDomestic` | 30 dk | İnişten terminal çıkışına: iç hat / Schengen içi |
| `arrivalExitInternational` | 60 dk | Dış hat |
| `arrivalExitEES` | 90 dk | AB dışı yolcunun Schengen'e girişi |
| transfer tahmini | `20 + km × 2` dk, 5'e yuvarlanır | Havalimanı ↔ şehir yolu, "yaklaşık" |

Uçuş türü:

- **İç hat**: kalkış ve varış havalimanı aynı ülkede.
- **Schengen içi**: ikisi de Schengen ülkesi.
- **Dış hat**: diğerleri.
- **EES geçerli**: Schengen sınırı geçiliyor (biri Schengen, diğeri değil) **ve** yolcu AB/Schengen vatandaşı değil.
  Yolcu uyruğu: profildeki (`TripStore.me`) pasaportun `nationality`'si; yoksa "TR" kabul edilir. AB/Schengen kümesi:
  `VisaRules.schengenCountries` ∪ {IE, CY}.

### Varış günü (ilk gün ya da şehir değiştirilen gün, varış uçuşu olan gün)

- `readyAt = iniş + çıkış süresi (türe göre) + transfer(havalimanı → ilk çapa noktası)`. İlk çapa noktası: listedeki
  ilk durak, yoksa o gecenin oteli.
- Havalimanı satırı: "✈ LIS · iniş 11:20 · şehirde yaklaşık 13:00". EES geçerliyse satırın altında
  "Yeni AB sınır kaydı (EES) nedeniyle pasaport sırası uzun sürebilir."
- `readyAt`'ten önce başlayan (saati verilmiş ya da tahmin edilen) duraklar uyarı alır: "İnişten sonra şehre en erken
  13:00'te varırsın." Uyarılar günün mevcut "saat uyarısı" sayacına eklenir.
- **Otele uğrama önerisi**: o gece konaklama varsa ve günün duraklarında o otelin `.stay` durağı yoksa, havalimanı
  satırının altında öneri satırı: "🛏 Önce otele uğramak ister misin? · Ekle". "Ekle" otel adı, koordinatı, tür
  `.stay`, süre 30 dk ile listenin başına bir durak ekler. Kullanıcı onu basılı tutup sürükleyerek ara bir yere ya da
  sona taşıyabilir, silebilir. Öneri satırı, durak eklendikten ya da "×" ile kapatıldıktan sonra o oturumda görünmez
  (kalıcı bir alan eklenmez).

### Kalkış günü (son gün ya da şehirden ayrılınan gün, kalkış uçuşu olan gün)

- `beAtAirport = kalkış − lead (türe göre)`.
- `leaveBy = beAtAirport − transfer(son nokta → havalimanı)`. Son nokta: listedeki son durak, yoksa sabah oteli.
- Havalimanı satırı (günün sonu): "✈ LIS · kalkış 09:40 · en geç 06:40'ta orada ol". Altında "Havalimanına yaklaşık
  05:50'de çık" ve uçuş için "Kapı ve biniş saatini bilette kontrol et." EES geçerliyse EES notu.
- `leaveBy`'dan sonra biten duraklar uyarı alır: "Havalimanına çıkman gereken saatten (05:50) sonra bitiyor."
- `leaveBy` gün başından önceye düşerse (sabah erken uçuş) satır "Sabah erken uçuş; bu gün için durak planlama"
  der ve her durak uyarı alır.

### Durak saatleri

- Bir durağın planlanan başlangıcı: `startMinutes` varsa o, yoksa günün mevcut zamanlama hesabı
  (`RouteOptimizer.schedule`) ile tahmin. Varış gününde tahmin `readyAt`'ten başlar.

## 5. Kod düzeni

- GezzyKit:
  - `Models.swift` (ya da `TripLodging` uzantısı): `lodging(forNightOf:)`.
  - Yeni `DayAnchors.swift`: çapa hesabı.
  - Yeni `FlightDayTiming.swift`: uçuş türü, EES, sabitler, `readyAt`, `beAtAirport`, `leaveBy`, transfer tahmini,
    durak uyarıları.
  - `Geo.swift` `RouteOptimizer`: isteğe bağlı `to:`; `ItineraryPlanner`: bitiş çapası.
- Uygulama:
  - Yeni `Features/Plan/ReservationsSection.swift`, `DesignSystem` içinde `AddPlaceholder`.
  - `FlightsCard`, `LodgingCard`: başlık "+" görünümü, boş durum.
  - `PlanSection`: kartlar kalkar; start/end satırları, havalimanı satırları, otele uğrama önerisi, uyarılar, harita
    rotası ve pinler.
  - `TripDetailView`: yeni sekme ve sekmeye geçiş eylemi.
  - `Localizable.xcstrings`: yeni metinlerin İngilizcesi.

## 6. Test

- GezzyKit birim testleri:
  - `lodging(forNightOf:)`: tek otel, otel değişen gün, son gün (nil), konaklamasız gece.
  - `DayAnchors`: normal gün, otel değişen gün, varış günü (havalimanı → otel), kalkış günü (otel → havalimanı),
    koordinatsız havalimanı.
  - `FlightDayTiming`: iç hat / Schengen içi / dış hat sınıflandırması; EES (TR yolcu, IST→LIS evet; DE yolcu hayır;
    LIS→MAD hayır); `readyAt`, `beAtAirport`, `leaveBy` sayıları; saat dilimli uçuş; sabah erken uçuş; uyarı üreten
    duraklar.
  - `RouteOptimizer` bitişli sıralama: bitişe yakın durak sona gelir; bitişsiz davranış değişmez.
  - `ItineraryPlanner` bitiş çapası.
- Simülatörde elle: Rezervasyon sekmesi, boş kart placeholder'ı ve menüsü, otelli normal gün (başta ve sonda otel),
  otel değişen gün, IST→LIS varış günü (havalimanı satırı, EES notu, otele uğrama önerisi ve sürükleme), LIS→IST
  kalkış günü (havalimanında biten liste, uyarılar), otel/uçuş satırından Rezervasyon sekmesine geçiş.

## Kaynaklar (süre seçimleri)

- Dış hat 3 saat / kısa uçuş 2 saat: [Remitly](https://www.remitly.com/blog/travel/how-early-to-get-to-airport/),
  [Yahoo News](https://news.yahoo.com/arriving-airport-2-hours-flight-145556969.html).
- İnişten çıkışa 45–90 dk: [Transferhood](https://transferhood.com/journal/transferhood-how-to-plan-international-airport-transfers/).
- EES kuyrukları: [The Local](https://www.thelocal.com/20260330/european-airports-record-longer-border-waiting-times-as-ees-deadline-looms),
  [TravelPulse](https://www.travelpulse.ca/news/impacting-travel/ees-means-long-waits-when-landing-in-europe).
