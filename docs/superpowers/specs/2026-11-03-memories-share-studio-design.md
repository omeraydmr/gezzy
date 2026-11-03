# Anılar ve paylaşım stüdyosu — tasarım

Tarih: 2026-11-03 · Durum: onay bekliyor

## Sorun

- Anılar sekmesi bir liste: özet posteri, ortak albüm, topluluk kartı, gün gün "anlar" ve ayrı bir kartpostal
  düğmesi. Fotoğrafları haritada görmek, beğenilenleri işaretlemek ya da en iyileri hızlıca bulmak mümkün değil.
- Paylaşılan iki görsel (istatistik posteri, kartpostal) sabit: biçim, fotoğraf, renk, metin değiştirilemiyor;
  marka işareti yalnızca küçük bir "Gezzy" yazısı.

## Hedef

1. Anılar'da üç kolaylık: **harita üzerinde günlük**, **favori / kapak / gizle**, **otomatik öne çıkanlar**.
2. Tek bir **Paylaşım stüdyosu**: 5 şablon (Kartpostal, İstatistik, Rota haritası, Foto kolajı, Bilet), her biri
   biçim, fotoğraf, renk, başlık/metin ve gösterilecek bilgiler açısından özelleştirilebilir.
3. Her kartta **"Gezzy ile planlandı"** işareti; Premium kullanıcı kapatabilir.

Kapsam dışı: video/reel, sunucuya fotoğraf yükleme, kartı Gezzy içinde herkese açık bağlantı olarak yayınlama.
Fotoğraflar cihazdan çıkmaz; kart görseli cihazda üretilir.

## 1. Anılar sekmesi yeni düzen

Yukarıdan aşağı:

1. **Öne çıkanlar şeridi** (fotoğraf izni ve en az bir an varsa): yatay kaydırılan büyük kareler, her gün için bir
   fotoğraf + gün etiketi ("1. gün · Nyhavn"). Dokununca fotoğraf görüntüleyici; şeridin başlığında
   "Kart oluştur" → Paylaşım stüdyosu (Kolaj şablonu, öne çıkanlar seçili).
2. **Günlük**: mevcut `DayChips` (seyahat günleri, her günde o günün fotoğraf sayısı kadar nokta) + harita + o günün
   anları.
   - Harita: o günün anları yuvarlak fotoğraf küçük resmi pin olarak (konumu olan anlar); planın durakları soluk
     numaralı pin ve ince rota çizgisi (palet rengi). Kamera o günün pinlerini çerçeveler (`MapFraming`).
   - Pine dokununca alttaki liste o ana kayar ve vurgulanır; listede ana dokununca harita o pine gider.
   - Konumu olmayan anlar listede kalır, haritada görünmez.
3. **Paylaş** kartı: tek satır "Seyahatini paylaş" + son kullanılan şablonun küçük önizlemesi; dokununca stüdyo.
   Mevcut `TripSummaryCard` ve kartpostal düğmesi kalkar (stüdyoda şablon olarak yaşar).
4. Ortak albüm ve topluluk kartı (değişmeden).

Fotoğraf izni yoksa bugünkü izin istemi; öne çıkanlar ve günlük gizli, Paylaş kartı yine görünür (fotoğrafsız
şablonlar: İstatistik, Rota, Bilet).

## 2. Favori, kapak, gizle

- `PhotoViewer` alt çubuğuna üç düğme: kalp (favori), "Kapak yap", göz-çizgi (gizle). Uzun basma menüsüyle de.
- **Favori:** öne çıkanlarda ve stüdyonun fotoğraf seçicisinde önce gelir.
- **Kapak yap:** fotoğrafı mevcut `TripStore.setCoverPhoto(_:for:)` ile seyahat kapağı yapar (palet fotoğraftan
  türer). Onay sorulmaz; geri almak için `•••` → "Fotoğrafı kaldır" zaten var.
- **Gizle:** anlardan, öne çıkanlardan ve seçiciden düşer; günlük listesinin sonunda "N gizli fotoğraf · Göster"
  satırı geri getirir.
- Saklama: fotoğraf kimlikleri (`PHAsset.localIdentifier`) cihaza özeldir; `Trip`'e yazılmaz. Cihazda
  `UserDefaults` `gezzy.memories.v1`: seyahat id → `{ favorites: [String], hidden: [String] }`.

## 3. Otomatik öne çıkanlar (GezzyKit, saf)

`MemoryHighlights.pick(moments:favorites:hidden:calendar:) -> [Highlight]`, `Highlight { day: Date, photoID: String, stopName: String? }`:

- Gün başına en çok bir fotoğraf, günler sırayla.
- Gizlenenler hiç seçilmez.
- O günün favorisi varsa en erken favori.
- Yoksa o günün en kalabalık anının (`count` en büyük; eşitlikte durak adı olan, sonra erken olan) ortadaki
  fotoğrafı.
- Hiç fotoğrafı olmayan gün atlanır.

## 4. Paylaşım stüdyosu

`ShareStudioView(trip:)`, `fullScreenCover`. Üstte canlı önizleme (seçili biçim oranında, ekrana sığar), altında:

1. **Şablon şeridi:** 5 küçük önizleme; seçili olan palet rengi kenarlıklı.
2. **Biçim:** `PillPicker` "Story 9:16" · "Gönderi 4:5" · "Kare 1:1".
3. **Düzenle** paneli (bölümler, şablona göre görünür):
   - **Fotoğraf:** favoriler + öne çıkanlar + tüm anlardan ızgara seçici. Kartpostal 1, Kolaj 4/6/9 (seçim sayısına
     göre yerleşim; en az 2), diğerleri yok.
   - **Renk:** seyahat paleti, 12 palet, "Fotoğraftan" (seçili fotoğraftan `TripPalette.derived`).
   - **Metin:** başlık (varsayılan seyahat adı), alt yazı (varsayılan "Kopenhag · 19–23 Kas"); her biri en çok 40
     karakter.
   - **Bilgiler:** anahtarlar: gün, durak, km, kişi, harcama, kişi başı. Varsayılan açık: gün, durak, km, kişi.
     Harcama ve kişi başı varsayılan kapalı (kişisel).
   - **Gezzy işareti:** anahtar. Ücretsiz kullanıcıda açık ve kilitli (dokununca `PaywallSheet(reason: .branding)`);
     Premium'da açılıp kapanır.
4. Alt çubuk: "Paylaş" (`.primary`, sistem paylaşım sayfası) ve "Kaydet" (Fotoğraflar'a, `PHPhotoLibrary`
   yalnızca ekleme izni).

Ayarlar seyahat başına cihazda saklanır (`UserDefaults` `gezzy.shareStudio.v1`, `ShareCardConfig` JSON); stüdyo
yeniden açılınca son durum gelir.

### Şablonlar

Hepsi aynı `ShareCardConfig` ve `TripSummary` verisini kullanır; biçime göre yerleşim değişir (story'de dikey
boşluk büyür, karede bilgi satırı tek sıra).

| Şablon | Görünüm |
|---|---|
| **Kartpostal** | Tam kaplayan fotoğraf, alt köşede posta pulu (bayrak + şehir + tarih, tırtıklı kenar), sol altta başlık, pul yanında mevcut `StampImprint` damgası soluk. |
| **İstatistik** | Palet gradyanı, büyük başlık, seçili bilgiler 2–3 sütun büyük rakam, "Öne çıkanlar: …" satırı (bugünkü posterin yenilenmiş hali). |
| **Rota haritası** | `MKMapSnapshotter` ile tüm seyahatin durakları; rota çizgisi gün gün palet pin renkleriyle, numaralı pinler; altta başlık bandı ve gün renk açıklaması. Konumlu durak yoksa şablon pasif ("Rota için konumlu durak gerekli"). |
| **Foto kolajı** | Seçili 4/6/9 fotoğraf ızgarası (2×2, 2×3, 3×3; story'de 2 sütun), aralarda ince boşluk, altta başlık ve tarih. |
| **Bilet** | Uygulamanın bilet dili (`TicketShape`, `FlightArc`): kalkış/varış kodları (birincil uçuş; yoksa şehir adları), tarih, gece, kişi, koltuk; delikli ayraç; QR yerine Gezzy rozeti. |

### Gezzy işareti

Kartın altında küçük uygulama simgesi + "Gezzy ile planlandı" (en: "Planned with Gezzy"); kart rengine göre beyaz
ya da mürekkep, %70 opaklık. Görsel çıktıda 1080 px genişlikte ~28 px yükseklik.

### Görüntü üretimi

`ImageRenderer`, genişlik 1080 px (`scale` = 1080 / önizleme genişliği). Fotoğraflar `PhotoLibrary` ile hedef
boyutta (≥ 1080 px kısa kenar) yüklenir; harita görüntüsü `MKMapSnapshotter` (1080 × gerekli yükseklik). Üretim
`Task` içinde, düğmede ilerleme göstergesi.

## 5. Kod düzeni

- GezzyKit: `MemoryHighlights.swift`, `ShareCardConfig.swift` (`Template`, `Format` + oran, `Stat`, varsayılanlar,
  `visibleStats`, `photoLimit(template)`) + testler.
- Uygulama:
  - `Store/MemoryPrefs.swift` (favori/gizli saklama).
  - `Features/Memories/MemoriesSection.swift` yeni düzen; `HighlightsStrip.swift`, `MemoryJournal.swift` (gün çipi +
    harita + liste).
  - `Features/Memories/Studio/ShareStudioView.swift`, `StudioControls.swift`, `CardTemplates.swift` (5 şablon
    görünümü), `CardRenderer.swift` (görsel üretimi, harita görüntüsü, fotoğraf yükleme), `GezzyMark.swift`.
  - `SharedAlbumViews.swift` (`PhotoViewer` düğmeleri).
  - Kaldırılır: `TripSummaryCard.swift` (`TripSummaryPoster` şablonlara taşınır), `PostcardView` ve kartpostal
    düğmesi.
  - `PaywallSheet.Reason` + `.branding` (başlık: "Kartlardan Gezzy işaretini kaldır").
  - `Localizable.xcstrings`.

## 6. Test ve doğrulama

- `MemoryHighlightsTests`: gün başına bir; favori önceliği; gizli asla; kalabalık an + ortadaki fotoğraf; boş gün
  atlanır.
- `ShareCardConfigTests`: varsayılanlar (harcama kapalı), Codable gidiş-dönüş, şablona göre fotoğraf sınırı, biçim
  oranları (9:16, 4:5, 1:1).
- Simülatör: Kopenhag seyahatine örnek fotoğraf ekleyerek (simülatöre `xcrun simctl addmedia` ile konumlu/tarihli
  görseller) Anılar düzeni, harita pinleri, favori/gizle, stüdyoda 5 şablon × 3 biçim önizleme, paylaşım ve
  kaydetme, ücretsizde işaret kilidi → paywall.
