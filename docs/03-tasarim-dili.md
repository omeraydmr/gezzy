# 03 · Tasarım Dili — "Kartpostal"

Referans görseller: [`design/references/`](../design/references/) · Token dosyası: [`design/tokens.json`](../design/tokens.json) · Canlı önizleme: [`design/preview.html`](../design/preview.html)

## 1. İlkeler

1. **Kâğıt üstüne kart.** Sakin gri bir zemin, üstünde yumuşak kenarlı kartlar, kartların içinde beyaz "tepsiler". Arayüz bir masaya yayılmış kartpostallar ve biletler gibi hissettirmeli.
2. **El yapımı sıcaklık, dijital netlik.** Yerler ve insanlar el çizimi pastel/pastel boya illüstrasyonlarla; veri, tipografi ve kontroller kusursuz ve keskin. Bu kontrast markanın imzası.
3. **Cümleyle anlat, sonra göster.** Her modül önce insan diliyle bir yargı cümlesi kurar ("İki transfer tüm seyahati kapatıyor."), sonra detayı verir.
4. **Renk = anlam.** Dört kategori rengi uygulamanın her yerinde aynı şeyi ifade eder. Dekoratif renk kullanımı yok.
5. **Tek ana eylem.** Her kartta en fazla bir siyah hap buton; yanında isteğe bağlı yuvarlak beyaz ikincil buton.
6. **AI sessizdir.** ✦ ikonuyla işaretlenir, öneri sunar, kullanıcı onaylar; asla kendiliğinden değiştirmez.

## 2. Renk

### Nötrler
| Token | Açık | Koyu | Kullanım |
|---|---|---|---|
| `canvas` | `#ECECEC` | `#0F1012` | Uygulama zemini |
| `surface` | `#F5F5F5` | `#1A1B1E` | Dış kart (modül kabı) |
| `tray` | `#FFFFFF` | `#24262A` | İç kart / tepsi |
| `ink` | `#1C1D21` | `#F2F2F3` | Başlıklar, ana metin, birincil buton |
| `ink-2` | `#6B6F78` | `#A3A7AF` | İkincil metin, modül başlığı |
| `ink-3` | `#A9ACB3` | `#6E727A` | Üçüncül metin, "/ 1,600" gibi limitler |
| `line` | `#E6E6E8` | `#33363B` | Ayraç, kesikli çizgi |
| `track` | `#E9E9EB` | `#2C2F34` | Boş ilerleme izi (taralı) |

### Kategori renkleri (anlamsal)
| Kategori | Ana | Zemin (tint) | Nerede |
|---|---|---|---|
| **Stays / Konaklama** — yeşil | `#3EC58F` | `#E3F6EE` | Bütçe, 1. durak, onay ✓, "All checked in" |
| **Flights / Ulaşım** — mavi | `#5B78EE` | `#E7ECFD` | Bütçe, 2. durak, "In 41 D" |
| **Food / Yemek** — turuncu | `#F2814A` | `#FDEDE4` | Bütçe, 3. durak, borç tutarı, "Draft", "Unassigned" |
| **Activities / Aktivite** — pembe-mor | `#D158D6` | `#F9E6FA` | Bütçe, 4. durak, "In 4 Mo" |

- Başarı rengi olarak **koyu yeşil** `#2E8B6A` (onay kutusu, açık toggle, "all square ✓").
- Kişilere de bu paletten sabit bir renk atanır (valiz ilerlemesi gibi kişi bazlı grafiklerde).
- Etiketler: tint zemin + ana renk metin, tam hap şekil.

## 3. Tipografi

- **Font:** Inter (Android/Web) · SF Pro (iOS sistem). Rakamlarda `font-variant-numeric: tabular-nums`.
- Hafif negatif harf aralığı büyük başlıklarda (`-0.02em`).

| Stil | Boyut / satır | Ağırlık | Örnek |
|---|---|---|---|
| `display` | 34 / 40 | 600 | CDG · LIS |
| `headline` | 28 / 34 | 500 | "Two transfers settle the whole trip." |
| `title` | 24 / 30 | 500, `ink-2` | Modül başlığı: "Budget" (ikonla birlikte) |
| `amount` | 28 / 34 | 600 | €2,900 *of €4,800* (ikinci kısım `ink-3`) |
| `body-strong` | 17 / 22 | 500 | Kyoto in Autumn |
| `body` | 15 / 20 | 400, `ink-2` | Nov 3 – 11 |
| `caption` | 13 / 16 | 500 | Date · Gate · Seat etiketleri |

## 4. Şekil, boşluk, derinlik

- **Köşe yarıçapı:** dış kart `32`, tepsi `24`, liste kartı `24`, küçük görsel `14`, buton/etiket `999` (hap).
- **Boşluk ölçeği (4'lük):** 4 · 8 · 12 · 16 · 20 · 24 · 32. Dış kart iç boşluğu 24; tepsi iç boşluğu 20.
- **Gölge:** çok yumuşak, geniş. `0 1px 2px rgba(0,0,0,.04), 0 8px 24px rgba(0,0,0,.06)`. Dış kartta ayrıca 1px beyaz iç kenar (cam/kâğıt hissi).
- **Doku:** boş ilerleme izleri ve dolu çubuklar ince **çapraz tarama** (45°) içerir — "el ile doldurulmuş" hissi.

## 5. Bileşen kataloğu

| Bileşen | Tanım | Görsel |
|---|---|---|
| **Modül kartı** | `surface` zemin, sol üstte gri ikon + `title`, isteğe bağlı segment kontrol sağda; içinde bir veya daha fazla `tray`. | Hepsi |
| **Segment kontrol** | Gri hap kap, seçili öğe beyaz hap + gölge. Upcoming/Past, gün seçici, Can edit/View only. | 1, 3, 4 |
| **Biniş kartı** | Kapak illüstrasyonu + bayraklı başlık hapı + IATA satırı + yay şeklinde kesikli uçuş yolu + 4 sütunlu meta + yan çentikler ve kesikli perforasyon + ekip/barkod alt bölümü. | 1 |
| **Seyahat destesi** | Ana ekran. Kare bilet kartları dairesel bir yörüngede (R≈560pt, adım ≈7,5°) üst üste dizilir; yandaki kartlar ~5° eğik, küçülmüş ve 2,5–5pt bulanık. Yatay sürüklemeyle bir seferde bir kart ilerler; arkadaki karta dokunmak onu öne getirir. Arka plandaki ışık ve sayfa noktası odaktaki seyahatin rengini alır. Altında vize · bütçe · valiz kısa göstergeleri. | — (yeni) |
| **Kare bilet kartı** | Üst %60 kapak (kullanıcı fotoğrafı ya da pastel yer tutucu, alt kenarda koyu degrade üzerinde ad + şehir · tarih, sağ üstte cam efektli geri sayım hapı). Yan çentiklerle ayrılan koçanda IATA rotası ya da şehir, avatarlar, gece/kişi sayısı, barkod. Koçan ve gölge kapak renginden (fotoğrafın baskın tonu) hafifçe boyanır. | — (yeni) |
| **Seyahat satırı** | Kolaj kapak (üst üste 2 kart + bayrak) + ad + tarih + avatar yığını + durum etiketi. | 1 |
| **Kategori çubuğu** | İkonlu kare rozet + ad + harcanan (kategori rengi) + `/ limit` (`ink-3`) + taralı çubuk. | 2 |
| **Kişi satırı** | Avatar + ad + "pays 🙂 Yuri" ikincil satır + sağda tutar (turuncu) veya ✓. | 2 |
| **Durak satırı** | Numaralı renkli pin + ad + tür · süre + saat etiketi (tint) + küçük illüstrasyon; durakları kesikli dikey çizgi ve ulaşım satırı bağlar. | 3 |
| **Harita** | Özel açık stil: açık gri bloklar, beyaz yollar, pastel yeşil parklar, açık mavi su; aynı renkli numaralı pinler; noktalı rota; üstte bilgi hapı. | 3 |
| **Birincil buton** | Siyah (`ink`) hap, beyaz metin + ikon, yükseklik 56. | Hepsi |
| **İkincil ikon buton** | 56×56 beyaz daire, yumuşak gölge. | 1, 2, 3, 4 |
| **Paylaşım ızgarası** | Beyaz daire ikonlar + altında `caption`. | 4 |
| **Toggle** | Açık: koyu yeşil; kapalı: gri iz. Kapalı satırın metni `ink-2`. | 4 |
| **Onay maddesi** | Yuvarlatılmış kare onay kutusu (koyu yeşil), tamamlanan madde `ink-3` rengine solar. | 4 |
| **Segmentli ilerleme** | Kişi başına renkli parça + taralı kalan; altında avatar + sayı lejantı. | 4 |

## 6. İllüstrasyon & avatar

- **Yerler:** pastel boya / yağlı pastel dokusunda, kısa paralel vuruşlar, beyaz kâğıt boşlukları görünür. Renkler kategori paletiyle uyumlu, doygunluk orta.
- **Avatarlar:** yuvarlak, düz renkli arka plan halkası, sade yüz çizimi; çeşitli ten renkleri. Kullanıcı fotoğrafı yüklerse aynı çerçeveyle gösterilir.
- **Bayraklar:** küçük yuvarlatılmış dikdörtgen, beyaz kenar çizgisi.
- Üretim seçenekleri: (a) illüstratörle 30–50 şehir için set, (b) kullanıcı fotoğrafını bu stile çeviren AI filtresi, (c) her ikisi.

## 7. İkonografi

- Dolgulu (filled), yuvarlatılmış köşeli, 20–24px ikon seti. Modül başlıklarında `ink-2`, butonlarda beyaz/siyah.
- Öneri: Phosphor Icons (Fill) veya SF Symbols (iOS) — tutarlılık için tek set seçilmeli.
- AI eylemleri her zaman ✦ (sparkle) ile.

## 8. Ses & dil (UX yazımı)

- Kısa, sıcak, yargı bildiren cümleler: "Ekibi Lizbon'a çağır." · "18 maddenin 12'si hazır. İki gün kaldı." · "Her şey dengede ✓".
- Rakamlar önde: "€2,900 / €4,800", "4 durak · 3,1 km".
- Göreli zaman: "41 gün sonra", "4 ay sonra" — mutlak tarih ikincil satırda.
- Türkçe ve İngilizce ilk günden; para ve tarih biçimleri yerel ayara göre.

## 9. Hareket

- Yaylı (spring) geçişler, kısa: 200–300 ms. Kartlar açılırken kapaktan detaya paylaşılan öğe geçişi (shared element).
- İlerleme çubukları ekrana girince soldan dolar; onay kutusu küçük bir "pop".
- `prefers-reduced-motion` desteklenir.

## 10. Erişilebilirlik

- Kategori rengi asla tek bilgi taşıyıcısı değil: her zaman ikon + metin eşlik eder.
- Tint zemin üzerindeki renkli metinler için kontrast kontrolü yapılmalı (özellikle sarıya yakın tonlarda). Gerekirse metin için ana rengin bir ton koyusu kullanılır.
- Dokunma hedefleri ≥ 44px; Dynamic Type / ölçeklenebilir font.
