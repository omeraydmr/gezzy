# 01 · Pazar ve Rakip Analizi

> Kapsam: seyahat planlama, birlikte seyahat, harcama paylaşımı, seyahat günlüğü ve vize bilgisi alanındaki öne çıkan uygulamalar.
> Not: Bilgiler Ekim 2026 itibarıyla kamuya açık ürün bilgilerine dayanır. Fiyatlar ve bazı özellikler değişmiş olabilir; geliştirmeye başlamadan önce kritik rakipler tek tek denenmeli.

---

## 1. Pazarın özeti

Seyahat uygulamaları bugün **parçalı** bir deneyim sunuyor. Tipik bir grup tatilinde kullanıcı aynı anda şunları kullanıyor:

| İhtiyaç | Bugün kullanılan araç |
|---|---|
| Rezervasyonları toplamak | TripIt, e-posta, ekran görüntüleri |
| Gün gün plan / harita | Wanderlog, Google Maps listeleri, Notion |
| Kiminle gidiyorum, kim ne yapıyor | WhatsApp grubu |
| Bütçe ve borç paylaşımı | Splitwise, Tricount, Excel |
| Fotoğraf & anı | Polarsteps, Google Fotoğraflar, Instagram |
| Vize / giriş şartları | Konsolosluk siteleri, VFS/iDATA, Sherpa, forumlar |
| Valiz listesi | Notlar uygulaması, PackPoint |

**Fırsat:** Bu yedi ihtiyacı *tek bir seyahat nesnesi* etrafında birleştiren, sıcak ve kişisel görünen bir uygulama. Rakiplerin çoğu bu alanların en fazla 2–3 tanesinde iyi.

---

## 2. Rakipler — tek tek

### 2.1 Wanderlog — *planlama odaklı "her şey bir arada"*
- **Güçlü:** Harita + gün gün itinerary yan yana; Google Docs gibi gerçek zamanlı ortak düzenleme; e-postadan rezervasyon içe aktarma; rota optimizasyonu (Pro); bütçe ve masraf bölme; çevrimdışı mod (Pro).
- **Zayıf:** Arayüz kalabalık ve "araç" gibi hissettiriyor; mobilde uzun kaydırmalı liste; görsel kimlik zayıf; fotoğraf/anı tarafı yok denecek kadar az; vize bilgisi yok.
- **Ders:** Harita ↔ liste senkronu ve ortak düzenleme artık *temel beklenti*. Ama yoğunluğu yönetmek gerekiyor.

### 2.2 TripIt — *rezervasyon organizatörü*
- **Güçlü:** `plans@tripit.com`'a e-posta yönlendirerek otomatik itinerary; uçuş durumu, kapı değişikliği bildirimleri (Pro); takvim entegrasyonu.
- **Zayıf:** Eski görünümlü arayüz; keşif/planlama yok; sosyal ve bütçe tarafı zayıf.
- **Ders:** **Rezervasyon e-postası parse etme** en büyük "sihir anı". Bizim biniş kartı kartımız (görsel 1) bu verinin güzel sunumu olabilir.

### 2.3 Tripsy (iOS) — *en iyi tasarlanmış planlayıcılardan*
- **Güçlü:** Native iOS hissi, temiz tipografi, rezervasyon içe aktarma, Apple Watch/widget desteği, uçuş takibi.
- **Zayıf:** Sadece Apple ekosistemi; grup ve bütçe sınırlı.
- **Ders:** Az ama kaliteli bilgi, iyi widget'lar ve Live Activity'ler (uçuş, kapı) güçlü bağlılık yaratıyor.

### 2.4 Polarsteps — *otomatik seyahat günlüğü*
- **Güçlü:** Arka planda düşük pil tüketimiyle konum kaydı; haritada çizilen rota; fotoğrafları otomatik konuma bağlama; seyahat sonunda **basılı fotoğraf kitabı** (ana gelir kalemi); takipçilerle paylaşım.
- **Zayıf:** Planlama tarafı zayıf; bütçe yok; vize yok.
- **Ders:** "Sonrası" deneyimi (anı, rota, kitap) duygusal bağ kuruyor ve para kazandırıyor. **Fotoğraf öbekleme** özelliğimiz için ana referans.

### 2.5 Splitwise / Tricount — *masraf paylaşımı*
- **Güçlü:** Borç sadeleştirme ("debt simplification": N kişi arasında minimum transfer), çoklu para birimi, makbuz fotoğrafı, çevrimdışı ekleme. Tricount hesap açmadan link ile katılma imkânı veriyor.
- **Zayıf:** Splitwise ücretsiz sürümde günlük masraf limiti getirdi → kullanıcı şikâyetleri; seyahat bağlamı yok (sadece bir "grup").
- **Ders:** Görsel 2'deki *"Two transfers settle the whole trip."* tam olarak borç sadeleştirme algoritmasının insancıl anlatımı. **Hesapsız katılım** grup büyümesi için kritik.

### 2.6 Google Maps (Listeler) & Google Travel
- **Güçlü:** Herkesin elinde; yer verisi, yorumlar, çevrimdışı haritalar; Gmail'den rezervasyon tespiti.
- **Zayıf:** Planlama ve ortaklık yüzeysel; "Trips" ürünü birkaç kez kapatılıp başka yüzeylere dağıtıldı.
- **Ders:** Yer verisi için Google Places / Foursquare gibi bir sağlayıcıya bağımlı olacağız; Google Maps ile *rekabet değil, entegrasyon* (ör. "Google Maps listesini içe aktar").

### 2.7 Stippl / Lambus / Roadtrippers
- **Stippl:** Görsel, sosyal planlama; harita üstünde sürükle-bırak; seyahat ilhamı akışı.
- **Lambus:** Grup seyahati + masraf + belge kasası (pasaport, bilet PDF'leri) Avrupa odaklı.
- **Roadtrippers:** Kara yolu rotası, yol üstü duraklar, mesafe/yakıt.
- **Ders:** **Belge kasası** (pasaport, vize, sigorta PDF'i) grup seyahatinde çok değerli ve az uygulamada var.

### 2.8 AI planlayıcılar — Mindtrip, Layla, Wonderplan, ChatGPT
- **Güçlü:** Doğal dille "4 günlük Lizbon, yürüyüş ağırlıklı, bütçe orta" → saniyeler içinde plan; harita üstünde öneriler.
- **Zayıf:** Planlar genelleşmiş, açılış saatleri/mesafe hataları; kullanıcı planı "sahiplenmiyor"; düzenlemesi zahmetli.
- **Ders:** AI'ı **ana ekran değil, yardımcı buton** olarak konumlamak: *Optimize route*, *Suggest items*, *Boş günü doldur* (görsel 3 ve 4'teki ✦ butonları tam bu yaklaşım).

### 2.9 Vize / giriş şartları — Sherpa, iVisa, Passport Index, Travel Buddy
- **Sherpa (joinsherpa):** Pasaport + varış + transit → vize gerekliliği, sağlık kuralları; B2B API olarak havayollarına satılıyor.
- **Passport Index / Travel Buddy:** Pasaport bazlı vizesiz/e-vize/kapıda vize matrisi.
- **IATA Timatic:** Havayollarının kullandığı resmî kaynak; pahalı, B2B.
- **Ders:** Vize *verisi* lisanslanabilir; asıl boşluk **süreç yönetimi**: randevu takibi, belge kontrol listesi, başvuru durumu, pasaport geçerlilik uyarısı (6 ay kuralı).
- **Türkiye pazarı için önemli:** Schengen randevu sıkıntısı (VFS Global / iDATA), çok girişli vize geçmişi, e-vize/ETA (ör. İngiltere ETA, ABD ESTA uygunluğu yok) gibi konular Türk pasaportu sahipleri için gerçek bir acı noktası. Bu, uygulamayı rakiplerden ayıracak en güçlü yerel farklılaştırıcı olabilir.

### 2.10 Diğer ilham kaynakları (seyahat dışı veya niş)
- **Flighty:** Uçuş takibi için sınıfının en iyisi tasarım; Live Activity, gecikme tahmini. → biniş kartı kartı ve uçuş günü deneyimi için referans.
- **Been / Visited:** Gezilen ülkeler haritası, yüzdeler → oyunlaştırma ve profil ekranı için.
- **PackPoint:** Hava durumu + aktiviteye göre otomatik valiz listesi → *Suggest items*.
- **Airbnb (2025+ yeniden tasarım):** Sıcak, el yapımı hissi veren 3B ikonlar ve illüstrasyonlar → "kişisel, sıcak" görsel ton için referans.

---

## 3. Karşılaştırma matrisi

`●` güçlü · `◐` kısmen / ücretli · `○` yok

| Özellik | Wanderlog | TripIt | Tripsy | Polarsteps | Splitwise | Lambus | AI planlayıcılar | **Travller (hedef)** |
|---|---|---|---|---|---|---|---|---|
| Gün gün plan + harita | ● | ◐ | ● | ○ | ○ | ● | ● | ● |
| Rota optimizasyonu | ◐ | ○ | ○ | ○ | ○ | ○ | ◐ | ● (✦ AI) |
| Rezervasyon içe aktarma | ● | ● | ● | ○ | ○ | ◐ | ○ | ● |
| Ortak düzenleme / roller | ● | ◐ | ◐ | ◐ | ● | ● | ○ | ● |
| Bütçe (kategori bazlı) | ◐ | ○ | ◐ | ○ | ◐ | ◐ | ○ | ● |
| Borç sadeleştirme | ◐ | ○ | ○ | ○ | ● | ● | ○ | ● |
| Fotoğraf & otomatik öbekleme | ○ | ○ | ○ | ● | ○ | ○ | ○ | ● |
| Rota/anı günlüğü | ○ | ○ | ○ | ● | ○ | ○ | ○ | ● |
| Vize & giriş şartları | ○ | ○ | ○ | ○ | ○ | ○ | ◐ | ● |
| Belge kasası | ○ | ◐ | ◐ | ○ | ○ | ● | ○ | ● |
| Valiz listesi (atamalı) | ◐ | ○ | ◐ | ○ | ○ | ◐ | ○ | ● |
| Çevrimdışı | ◐ | ◐ | ● | ● | ● | ◐ | ○ | ● |
| Görsel kimlik / sıcaklık | ◐ | ○ | ● | ● | ○ | ◐ | ◐ | ● |

---

## 4. Çıkarımlar

1. **Konumlandırma:** "Seyahatin *öncesi, sırası ve sonrası* — ekibinle, tek yerde." Rakipler genelde yalnızca bir evreye odaklanıyor (Wanderlog: öncesi, TripIt/Flighty: sırası, Polarsteps: sonrası).
2. **Tek nesne:** Her şey bir **Trip** nesnesine bağlı. Bütçe, plan, valiz, fotoğraf, vize — hepsi aynı seyahatin sekmeleri. (Splitwise'ın "grup" kavramından daha zengin.)
3. **Sıcaklık bir özellik:** Paylaştığın görsellerdeki el çizimi pastel illüstrasyonlar ve hikâye anlatan başlıklar ("Bring the crew into Lisbon.") rakiplerin soğuk, tablo gibi arayüzünden net ayrışıyor.
4. **AI = yardımcı fiil:** ✦ ikonlu tek bir buton; tüm ekranı ele geçirmeyen, geri alınabilir öneriler.
5. **Yerel farklılaştırıcı:** Türk pasaportu odaklı vize asistanı (randevu, belge listesi, süre uyarıları).
6. **Büyüme motoru:** Davet linki ile hesapsız katılım (Tricount modeli) + seyahat sonunda paylaşılabilir "seyahat hikâyesi" (Polarsteps modeli).
7. **Gelir modeli adayları:** Freemium (Pro: çevrimdışı, AI, sınırsız fotoğraf), basılı fotoğraf kitabı, vize/sigorta/eSIM ortaklıkları (affiliate). Splitwise'ın limit tepkisinden ders: **temel masraf paylaşımı ücretsiz kalmalı**.
