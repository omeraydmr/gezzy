# 02 · Özellik Seti, Bilgi Mimarisi ve MVP

## 1. Temel kavram: Trip

Uygulamadaki her şey bir **Trip** (seyahat) nesnesinin etrafında döner.

```
Trip
├── Bilgiler      : ad, kapak illüstrasyonu, ülke(ler), tarih aralığı, durum (Draft / Upcoming / Live / Past)
├── Ekip          : üyeler + rol (Owner / Can edit / View only) + görünürlük ayarları
├── Ulaşım        : uçuş/tren/otobüs segmentleri (biniş kartı)
├── Konaklama     : otel/ev rezervasyonları
├── Gün planı     : Gün → Durak (yer, saat, süre, kategori, not) → Aradaki ulaşım (yürüme/tram/taksi)
├── Harita        : tüm duraklar, rotalar, kayıtlı yerler, fotoğraf öbekleri
├── Bütçe         : kategori limitleri (Stays / Flights / Food / Activities / …)
├── Masraflar     : kim ödedi, kimler arasında, para birimi → Bakiyeler → Settle up
├── Valiz         : maddeler, atanan kişi, paketlendi mi
├── Belgeler      : pasaport, vize, sigorta, bilet PDF'leri (kişiye özel / paylaşımlı)
├── Vize          : her üye için pasaport × ülke → gereklilik, kontrol listesi, randevu takibi
└── Anılar        : fotoğraflar → öbekler (yer + zaman) → günlük / hikâye
```

## 2. Bilgi mimarisi (alt navigasyon)

| Sekme | İçerik | Referans görsel |
|---|---|---|
| **Trips** | Yaklaşan / geçmiş seyahatler; öne çıkan biniş kartı; "Plan a trip" | Görsel 1 |
| **Plan** (seyahat içi) | Gün seçici + gün planı + harita | Görsel 3 |
| **Money** | Bütçe ilerlemesi + bakiyeler + masraf ekle | Görsel 2 |
| **Memories** | Fotoğraf haritası, öbekler, günlük | — (yeni) |
| **Profil** | Pasaportlar, gezilen ülkeler, belgeler | — |

Seyahat detayında üst kısımda kısa bir özet ("Lisbon Getaway · 4 kişi · 6 gece") ve altında yatay sekmeler: *Plan · Money · Packing · Docs & Visa · Memories · Crew*.

## 3. Özellik modülleri

### 3.1 Trips (ana ekran)
- Bir sonraki seyahat **biniş kartı** olarak öne çıkar: IATA kodları, kalkış/varış saatleri, süre, tarih, kapı, koltuk, konaklama süresi, ekip check-in durumu, barkod.
- Diğer seyahatler kart listesi: kolaj kapak + bayrak + tarih + ekip avatarları + durum etiketi (`In 41 D`, `In 4 Mo`, `Draft`).
- Upcoming / Past segment kontrolü.
- Seyahat günü: Live Activity / widget (kapı, kalkışa kalan süre).

### 3.2 Gün planı & harita
- Gün seçici (Mon 13 · **Tue 14** · Wed 15).
- Her gün bir "rota adı" (ör. *Alfama & Baixa*), durak sayısı ve toplam mesafe.
- Durak kartı: numaralı renkli pin, ad, tür · süre / not ("Book ahead"), saat etiketi, küçük illüstrasyon.
- Duraklar arası geçiş satırı: 🚶 8 min, 🚋 Tram, 🚕 Taxi.
- Harita: aynı renk ve numaralarla pinler, noktalı rota, toplam yürüme süresi etiketi.
- ✦ **Optimize route**: açılış saatleri + mesafe + sabit rezervasyonlar dikkate alınarak sıralama önerisi (önce/sonra karşılaştırması, tek tıkla geri al).
- Sürükle-bırak ile sıralama, başka güne taşıma, "Fikirler" havuzu (henüz güne atanmamış yerler).
- Çevrimdışı harita paketleri (Pro).

### 3.3 Ekip & davet
- Davet: e-posta, link kopyala, QR kod, mesaj, sistem paylaşımı.
- Roller: **Can edit / View only**.
- Görünürlük anahtarları: *Show expenses*, *Show private notes*.
- Hesap açmadan link ile katılım (misafir) → sonradan hesaba dönüştürme.
- Aktivite akışı: "Mara, Pastéis de Belém'i Salı'ya ekledi".

### 3.4 Bütçe & masraflar
- Toplam: `€2,900 of €4,800`, gün bazlı tempo yorumu ("Day 3 of 6 · a little ahead of pace").
- Kategori çubukları: Stays, Flights, Food, Activities (+ Transport, Shopping, Other). Renkler sabit (bkz. tasarım dili).
- Masraf ekleme: tutar, para birimi (otomatik kur), ödeyen, paylaşım şekli (eşit / oran / tutar), kategori, makbuz fotoğrafı (OCR ile tutar okuma).
- **Bakiyeler:** borç sadeleştirme algoritması → minimum transfer sayısı; insancıl başlık: *"İki transfer tüm seyahati kapatıyor."*
- Settle up: IBAN kopyala / ödeme linki / "ödendi" olarak işaretle; özet paylaş.

### 3.5 Valiz (Packing)
- Kişi bazlı segmentli ilerleme çubuğu (kim kaç madde paketledi, kalan).
- Maddeler: onay kutusu, atanan kişi avatarı veya `Unassigned` etiketi.
- ✦ **Suggest items**: hedef hava durumu, aktiviteler, priz tipi (Type F), seyahat süresi → öneriler.
- Ortak maddeler (tek kişi getirsin: adaptör, güneş kremi) vs kişisel maddeler.
- Hikâye anlatan başlık: *"18 maddenin 12'si hazır. İki gün kaldı."*

### 3.6 Vize & giriş şartları
- Profilde her üyenin pasaport(lar)ı: ülke, son geçerlilik tarihi, mevcut vizeler (ör. çok girişli Schengen, ABD B1/B2).
- Seyahat başına her üye için durum: `Vizesiz · 90/180`, `e-Vize`, `Kapıda vize`, `Vize gerekli`, `Geçerli vizen var ✓`.
- Pasaport geçerliliği uyarısı (dönüşten itibaren 3/6 ay kuralı), transit vize kontrolü.
- Vize gerekiyorsa: belge kontrol listesi (davetiye, otel, sigorta, banka dökümü…), randevu tarihi ve hatırlatma, başvuru durumu takibi, ilgili resmî linkler.
- Veri kaynağı adayları: Sherpa API, Travel Buddy API, Passport Index verisi; kritik bilgide **her zaman resmî kaynağa link** ve "son güncelleme" tarihi.

### 3.7 Fotoğraflar & öbekleme (Memories)
- Cihaz galerisinden seyahat tarih aralığına düşen fotoğrafları önerme (izinle, **cihaz üzerinde** filtreleme).
- **Öbekleme (clustering):** EXIF konum + zaman → yer-zaman öbekleri (ör. DBSCAN / HDBSCAN; mesafe eşiği ~150–300 m, zaman eşiği ~2 saat). Her öbek otomatik olarak gün planındaki en yakın durakla eşleşir ("Miradouro da Graça · 23 fotoğraf").
- Harita üzerinde zoom seviyesine göre öbekleşen fotoğraf pinleri (Supercluster).
- Gün gün otomatik günlük: rota çizgisi + öbek kapakları + kısa not.
- Ekip albümü: herkesin fotoğrafları tek havuzda, kişiye göre filtre.
- Seyahat sonu: paylaşılabilir hikâye / video, basılı albüm (gelir fırsatı).
- Fotoğrafların el çizimi/pastel stile dönüştürülmüş kapak versiyonları (tasarım dilindeki illüstrasyonlarla uyum için, opsiyonel AI özelliği).

### 3.8 Rezervasyon içe aktarma
- E-posta yönlendirme (`trips@…`) veya Gmail/Outlook bağlantısı → uçuş, otel, tren, etkinlik parse etme.
- PDF / ekran görüntüsü yükleme → LLM ile alan çıkarma, kullanıcı onayı.
- Uçuş durumu takibi (kapı, gecikme) → biniş kartı ve bildirimler.

## 4. MVP önerisi

**Faz 1 — MVP (çekirdek döngü: planla → ekibi çağır → harca → paylaş)**
1. Trip oluşturma, Trips ekranı (biniş kartı + liste)
2. Gün planı + harita (manuel durak ekleme, yer arama)
3. Davet (link + roller)
4. Masraf ekleme + bütçe kategorileri + bakiyeler/borç sadeleştirme
5. Valiz listesi (atamalı)
6. Vize durumu (salt okunur bilgi kartı + pasaport geçerlilik uyarısı)

**Faz 2**
- Fotoğraf içe aktarma + öbekleme + Memories haritası
- Rezervasyon içe aktarma (e-posta / PDF)
- ✦ Optimize route, ✦ Suggest items
- Vize başvuru takibi, belge kasası

**Faz 3**
- Uçuş takibi, Live Activity, widget
- Çevrimdışı mod, seyahat hikâyesi, basılı albüm
- Gezilen ülkeler profili, ilham akışı

## 5. Teknik notlar (öneri, karar değil)
- **İstemci:** React Native (Expo) veya Flutter — iOS + Android tek kod tabanı. Harita için MapLibre/Mapbox (özel stil şart, bkz. tasarım dili).
- **Backend:** Supabase/Postgres (+ PostGIS) veya Firebase; ortak düzenleme için realtime abonelikler, çevrimdışı için yerel-öncelikli senkron (ör. PowerSync / WatermelonDB).
- **Yer verisi:** Google Places veya Foursquare Places; rota/süre için Mapbox Directions / OSRM.
- **Para:** Tutarlar tam sayı (cent) + para birimi; kurlar günlük snapshot.
- **Gizlilik:** Fotoğraf konum analizi cihazda; belgeler uçtan uca şifreli alan olarak düşünülmeli.

## 6. Açık sorular
1. Hedef platform: önce iOS mu, iOS + Android birlikte mi, web de olacak mı?
2. Hedef kitle: Türkiye'den yurt dışına giden gruplar mı, global mi? (Dil ve vize odağını belirler.)
3. Uygulama adı "Travller" olarak mı kalıyor?
4. İllüstrasyon stili: el çizimi pastel stil için illüstratör mü, AI üretimi mi?
