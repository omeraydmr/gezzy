# Yer ekle: harita önde, popülerliğe göre — tasarım

Tarih: 2026-11-02 · Durum: onaylandı

## Sorun

- **Önerilen yerler** (`PlaceSuggestionsSheet`) Wikipedia'nın son 30 günlük okunma sayısına göre sıralıyor, ama puan
  görünmüyor ve ekran haritasız bir liste. Kullanıcı sıralamayı rastgele/alfabetik sanıyor ve yerlerin şehirde nerede
  olduğunu göremiyor.
- **Durak ekle** (`AddStopSheet`) Apple Haritalar sonuçlarını yalnızca ad benzerliği + merkeze yakınlıkla sıralıyor;
  popülerlik hiç yok.
- Yer eklemenin iki ayrı yolu var (Fikirler kartında iki buton, gün planında bir buton). "Nereden ekliyordum?" sorusu
  uygulamayı karmaşık gösteriyor.

## Hedef

1. Öneriler ve arama sonuçları popülerliğe göre sıralansın, popülerlik ekranda okunsun.
2. Kullanıcı yer seçerken haritayı hep görsün; eklediği yerin plandaki diğer yerlere göre konumu belli olsun.
3. Yer eklemenin tek bir yolu olsun.

Kapsam dışı: ücretli yer API'leri (Google Places, Foursquare), sunucu tarafı değişiklik, otomatik rota.

## Çözüm özeti

`AddStopSheet` ve `PlaceSuggestionsSheet` kalkar, yerine tek bir **`PlacePickerSheet`** ("Yer ekle") gelir. Ekranın
üstü tam boy harita, altında çekilebilir bir liste çekmecesi var. Sıralama GezzyKit'te yeni, saf ve test edilebilir
**`PlaceRanking`** ile yapılır.

## 1. Ekran yapısı (`PlacePickerSheet`)

```
┌──────────────────────────────┐
│ [Lizbon][Porto]   (çok şehir) │
│   HARİTA   (1)    (2)         │
│       (3)     ● plan          │
│   (4)     🛏 otel             │
├──────────── ━━━ ─────────────┤  ← çekmece
│ Ekleneceği yer: 3. gün ▾      │
│ 🔍 Ara                        │
│ [Tümü][Görülecek][Yeme][Aktivite]
│ 1 Belém Kulesi  Çok popüler + │
│ 2 Jerónimos     Çok popüler + │
│ 3 Alfama        Popüler     + │
└──────────────────────────────┘
```

- **Harita** tam ekran, `pointsOfInterest: .excludingAll` (mevcut stil).
  - Listedeki yerler, listedeki sırasıyla numaralı pin (`NumberedPin`). Filtre ya da arama değişince pinler de değişir.
  - Plandaki duraklar ve hedef günün oteli soluk gri pin. Bunlara dokunulmaz, yalnızca bağlam verir.
  - Bu oturumda eklenen yerler yeşil ✓ pin olur.
  - Kamera ilk açılışta listedeki ilk 10 yeri ve plandaki durakları çerçeveler (`MapFraming`). Liste değişince yeniden
    çerçeveler, ama kullanıcı haritayı elle oynattıysa çerçevelemez.
- **Çekmece**: `presentationDetents` üç kademe: küçük (~%30, harita baskın), yarım (açılış), büyük (liste baskın).
  Arama alanına odaklanınca büyük kademeye çıkar.
- **Pin ↔ satır bağı**: pine dokununca çekmece en az yarım kademeye çıkar ve satır görünür olup vurgulanır. Satıra
  dokununca harita o yere kayar ve pini vurgular.
- **Filtre çipleri**: Tümü · Görülecek (`.sight`) · Yeme-içme (`.food`) · Aktivite (`.activity`). Tek seçim.
- **Çok şehirli seyahat**: şehir çipleri haritanın üstünde, mevcut `legID` mantığıyla.
- **Hedef satırı**: "Ekleneceği yer: <gün> ▾". Menüde seyahatin günleri + "Fikirler". Açılış değeri giriş noktasından
  gelir (bkz. 3).
- **Satır**: numara · ad · popülerlik etiketi · tür ve önerilen süre · sağda **+** butonu. **+** yeri hedefe hemen
  ekler, hafif titreşim verir, butonu ✓'ye çevirir; ekran kapanmaz. ✓'ye tekrar basmak eklemeyi geri alır.
  Çoklu seçim ve üstteki "N yer ekle" butonu kalkar; araç çubuğunda yalnızca "Bitti".
- **Elle ekle**: listenin sonunda "Listede yok mu? Elle ekle". Ad, tür ve süre soran küçük bir form açar. Arama
  metni ad alanına önceden yazılır.
- Topluluk yerlerindeki "Bildir" bağlam menüsü aynen kalır.

## 2. Sıralama (`PlaceRanking`, GezzyKit)

Saf fonksiyonlar; ağ ve UI bilmez.

### Popülerlik puanı

Bir şehirdeki aday havuzu: Wikipedia önerileri (`PlaceSuggestionService` önbelleği, en çok 80) + topluluk yerleri
(`/places/nearby`).

- Wikipedia puanı: okunma sayısının havuz içindeki yüzdelik sırası, 0…1.
- Topluluk puanı: sunucu `score` değerinin topluluk listesi içindeki yüzdelik sırası, 0…1.
- Aynı yer iki kaynakta da varsa (`Suggestion.matches`: ad benzer ya da 80 m içinde) tek kayıt olur, topluluk kaydı
  kalır; popülerlik = iki puanın büyüğü + 0,1 (en çok 1).
- MapKit yedek önerileri (Wikipedia boş dönerse) ve hiçbir kayıtla eşleşmeyen arama sonuçları: 0.

### Etiketler

| Koşul | Etiket |
|---|---|
| Topluluk kaydı | "Gezginler seçti · N kişi" (mevcut metin) |
| popülerlik ≥ 0,8 | "Çok popüler" |
| 0,5 ≤ popülerlik < 0,8 | "Popüler" |
| diğer | etiket yok |

Topluluk etiketi varsa "Çok popüler/Popüler" ayrıca yazılmaz. Yıldız kullanılmaz (puan sanılır).

### Arama yokken sıra

1. "<plandaki yer> sonrası gezginler genelde" bölümleri (mevcut `loadNextPlaces`, filtre yokken).
2. Kalanlar popülerliğe göre azalan; eşitlikte merkeze yakın olan önce.

### Arama varken sıra

Adaylar: yüklü öneri havuzunda ad/tür eşleşenler + `PlaceSearch.places` (Apple Haritalar) sonuçları. Apple sonuçları
havuzla `matches` üzerinden eşleşirse havuzdaki popülerliği alır ve tek satır olur.

- Eşik: `PlaceMatch.similarity(sorgu, ad) < 0,35` ve tür eşleşmesi yoksa aday atılır.
- **Tam eşleşme kuralı**: benzerlik ≥ 0,9 olan adaylar her zaman en üstte (kendi aralarında aşağıdaki puanla).
- Puan = 0,55 × benzerlik + 0,35 × popülerlik + 0,10 × yakınlık, yakınlık = `max(0, 1 − mesafe / 15 km)`.
- En çok 25 sonuç.

Ağırlıklar ve eşikler `PlaceRanking` içinde tek yerde sabit olarak durur; testler bunları kilitler.

## 3. Giriş noktaları

- **Fikirler kartı** (`IdeasCard`): "+" ("Fikir ekle") ve "Yer öner" butonları tek "Yer ekle" butonu olur. Hedef:
  Fikirler. Çok şehirli seyahatte açılış şehri kartın günü.
- **Gün planı** (`PlanSection`): "Durak ekle" → aynı ekran, hedef: o gün.
- Saat, süre ve not artık ekleme anında sorulmaz. Güne eklenen durak günün sonuna (`order` = max + 1), saatsiz
  eklenir. Fikirlere eklenen yer `Suggestion.stop(day:)` ile olur.
- Bugün durağın saatini/notunu sonradan düzenleyen bir ekran yok (yalnızca "Açılış saatleri"). Bu yüzden durağın
  bağlam menüsüne **"Düzenle"** eklenir: ad, tür, saat (isteğe bağlı), süre ve not soran küçük `StopDetailsSheet`.
  `ManualPlaceForm` aynı alan bileşenlerini kullanır.

## 4. Veri akışı

```
PlacePickerSheet
 ├─ PlanCenter.find(trip, leg)            → merkez
 ├─ PlaceSuggestionService.suggestions    → Wikipedia havuzu (önbellekli)
 ├─ CommunityService.nearby / next        → topluluk havuzu + "sonra" bölümleri
 ├─ PlaceSearch.places(query)             → Apple sonuçları (350 ms gecikmeli)
 └─ PlaceRanking.rank(...)                → listedeki sıra + etiketler → harita pinleri
```

Harita pinleri ve liste aynı sıralı diziden üretilir; numaralar her zaman eşleşir.

## 5. Hata durumları

- **İnternet yok / Wikipedia hatası**: harita plandaki duraklarla açılır; çekmecede "Öneriler alınamadı" bandı ve
  "Tekrar dene". Arama ve elle ekleme çalışmaya devam eder.
- **Şehir konumu bulunamadı**: harita seyahatin ülkesini gösterir, liste yalnızca arama modunda çalışır
  ("Aramak için bir yer adı yaz").
- **Topluluk sunucusu kapalı** (`isConfigured == false` ya da hata): yalnızca Wikipedia önerileri, sessizce.
- **Aramada sonuç yok**: "Aramaya uyan yer bulunamadı." + "Elle ekle".

## 6. Kod düzeni

- Yeni: `ios/Packages/GezzyKit/Sources/GezzyKit/PlaceRanking.swift`
- Yeni: `ios/Gezzy/Features/Plan/PlacePicker/` altında `PlacePickerSheet.swift` (iskelet + veri yükleme),
  `PlacePickerMap.swift` (harita ve pinler), `PlacePickerList.swift` (çekmece, satır, filtre, hedef menüsü),
  `ManualPlaceForm.swift`.
- Yeni: `ios/Gezzy/Features/Plan/StopDetailsSheet.swift` (durak düzenleme; ortak form alanları burada).
- Silinir: `AddStopSheet.swift`, `AutoPlanViews.swift` içindeki `PlaceSuggestionsSheet`. `PlanCenter` ve
  `AutoPlanSheet` aynı dosyada kalır.
- Değişir: `IdeasCard.swift`, `PlanSection.swift` (giriş noktaları), `Localizable.xcstrings` (yeni metinler).

## 7. Test

- `PlaceRankingTests` (GezzyKit):
  - Yüzdelik popülerlik ve etiket kademeleri.
  - Wikipedia + topluluk birleştirme: tek kayıt, topluluk kaydı kalır, +0,1 bonus.
  - Tam ad eşleşmesi daha popüler ama benzemeyen yerin önünde.
  - Eşik altı adaylar atılır; tür eşleşmesi ("müze") adayları tutar.
  - Apple sonucu havuzdaki yerle eşleşince popülerliği alır ve tekrarlanmaz.
- Elle doğrulama (simülatör): Lizbon tek şehir ve Lizbon–Porto çok şehir seyahati; açılış, pin↔satır bağı, filtre,
  arama, hedef değiştirme, ekle/geri al, durağı "Düzenle" ile saat/not verme, internet kapalıyken açılış.
