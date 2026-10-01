# 04 · Ekran İncelemesi — Kartpostal 2

Ana ekrandaki deste anlayışı (kare bilet, fotoğraflı kapak, seyahat rengi, kompaktlık) seyahat detayına ve sekmelere taşındı.
Görsel maket: [`design/screens.html`](../design/screens.html)

## Ortak ilkeler
- **Seyahat rengi (tint) her yerde:** kapak fotoğrafının baskın tonu ya da palet rengi; arka plan ışığı, seçili sekme ikonu, gün çipi noktaları, ilerleme halkası, bilet koçanı çizgisi.
- **Bilet sürekliliği:** ana ekrandaki kart, detayda tam genişlik kapak + üstüne binen koçana dönüşür; transferler ve yeni seyahat önizlemesi de bilet biçiminde.
- **Önce özet, sonra liste:** her sekme bir grafik/sayı ile açılır (donut, halka, pasaport damgası), liste altta.
- **Siyah = seçim/eylem:** seçili gün ve filtre hapları siyah; tint yalnızca vurgu (beyaz metin altında kontrast sorunu yaratmasın diye).

## Ekran ekran

| Ekran | Önce | Şimdi |
|---|---|---|
| Seyahat detayı | Küçük kapak kutusu, metin sekmeleri, düz gri zemin | Aşağı çekince esneyen tam genişlik kapak, üstüne binen bilet koçanı (rota · tarih · gece · koltuk · ekip), ikonlu sekmeler, seyahat renginde ışık; yukarı kayınca başlık gezinme çubuğuna geçer |
| Plan | Metin gün seçici, harita listenin altında | Gün çipleri (gün adı + numara + durak noktaları), önce harita, durak / mesafe / yürüme hapları |
| Bütçe | Tek sütun çubuklar, düz bakiye satırları | Kategori renkli donut + kalan tutar + tempo hapı, 2×2 kategori kutuları, transferler yanları çentikli mini bilet, harcamalar güne göre gruplu |
| Vize | Kişi listesi + ayrı detay sayfası | Yatay kaydırılan bordo T.C. pasaport kartları; üzerinde hedef ülke bayrağıyla vize durumu "damgası". Kaydırdıkça altında o kişinin uyarıları ve işaretlenebilir belge listesi açılır |
| Valiz | Başlık + liste | Seyahat renginde ilerleme halkası, kişiye göre filtre hapları |
| Ekip | Satır listesi | 2 sütunlu kişi kartları (rol, sahip tacı, vize durumu), kesikli "Kişi ekle" kartı |
| Masraf ekle | Form, klavyeyle tutar | Büyük tutar göstergesi + hesap makinesi tuşları (Türkçe "1.250,5" yazımı, haptik), renkli kategori hapları (zemin ışığı kategori renginde), ödeyen/bölünecek avatar seçimi, canlı kişi başı tutar |
| Plan · sıralama | Bağlam menüsünden yukarı/aşağı | Durağı basılı tutup sürükle-bırak; gün çipine bırakınca o güne taşınır |
| Döviz ve makbuz | Yalnızca seyahat para birimi | Para birimi menüsü; ECB kuruyla (Frankfurter) anında çevrim, kur yoksa elle; orijinal tutar listede; kamera/galeriden makbuz, dokununca tam ekran |
| Valiz · hava | Aya göre tahmin | Open-Meteo: 16 gün içindeyse tahmin, değilse geçen yılın aynı tarihleri; öneriler sıcaklık ve yağışa göre |
| Makbuz okuma | Tutar elle | Makbuzdaki toplam cihaz üzerinde (Vision) okunur; tutar ve para birimi dolar, "Geri al" ile vazgeçilir; emin olunamazsa "kontrol et" uyarısı |
| Para birimleri | — | Birden fazla parayla harcama varsa bütçede dağılım kartı: orijinal toplamlar, seyahat parasındaki karşılığı, yüzdeler |
| Açılış saatleri | — | OpenStreetMap'ten otomatik; durak saatine göre "O gün kapalı", "Henüz kapalı · açılış 10:00", "Kapanış 17:30 · süre yetmeyebilir"; elle düzenlenebilir |
| Saat düzeltme | Yalnızca uyarı | Uyarının altında tek dokunuşla çözüm: "Saati 10:00 yap" ya da "Taşı: Sal 13" (aynı saatte açık en yakın gün; eşitlikte sonraki gün) |
| Kalem kalem bölme | Herkese eşit | Makbuz kalemleri okunur, her kalem kişilere atanır; vergi/servis/kur farkı oransal dağıtılır; bakiyeler kişi başı paylarla hesaplanır |
| Hakkında | — | Veri kaynakları ve lisans atıfları, gizlilik notları, vize verisi uyarısı, örnek verileri sıfırlama |
| Harcama düzenleme | Yalnızca silme | Harcamaya dokununca aynı ekran düzenleme modunda açılır; tutar/para birimi aynıysa kayıtlı karşılık korunur, özel paylar yeni tutara oranlanır, makbuz değiştirilebilir |
| Ekip paylaşımı | Elle kişi ekleme | iCloud daveti Mesajlar/Mail ile; seyahat herkesin telefonunda eşitlenir, çakışmalar öğe bazında birleşir, silinenler geri gelmez; katılan kişi kendini ekibe ekler |
| Çevrimdışı harita | — | Günlerin rotası numaralı pinleriyle görüntü olarak kaydedilir; internet yokken canlı haritanın yerine gösterilir |
| Bildirimler | — | Önceki akşam valiz, uçuştan 3 saat önce kapı/koltuk, her sabah günün planı, notlu duraklardan 45 dk önce |
| Anlık güncelleme | Açılışta eşitleme | CloudKit abonelikleri sessiz push gönderir; değişiklik hemen birleşir ve "Elif bir harcama ekledi: Kahvaltı · €27,75" gibi bildirim düşer; kendi değişikliklerin bildirilmez |
| Fotoğraf eşitleme | Yalnızca bu cihazda | Kapak ve makbuz fotoğrafları CKAsset olarak yüklenir; her fotoğraf bir kez gönderilir, ekipteki diğer telefonlara iner |
| Schengen 90/180 | — | Schengen seyahatlerinde vize sekmesinde: dönüş günü itibarıyla son 180 günde kullanılan gün (seyahat dahil), 180 günlük şerit (bu seyahat, diğer ziyaretler, aşan günler), sayılan ziyaretler, elle geçmiş ziyaret ekleme; aşımda ilk aşım günü, en geç çıkış ve aynı uzunluk için en erken giriş önerisi. Aşım, vize uyarıları ve ana sayfadaki vize kutusuna da yansır |
| Konaklama | — | Plan sekmesinde otel kartı (ad, adres araması, giriş/çıkış saati, rezervasyon no); gün planı ve harita sabah kalınan otelden başlar, otelden ilk durağa süre gösterilir; giriş ve çıkış sabahı bildirim; konaklaması olmayan geceler uyarılır |
| Fikirler | — | Güne atanmamış yerler havuzu; "Sal 14 ekle" ile seçili günün sonuna taşınır; duraktan "Fikirlere taşı" |
| Rezervasyon içe aktarma | — | PDF ya da ekran görüntüsünden (cihazda okunur) uçuş numarası, rota, tarih, saat, koltuk ve otel adı, giriş/çıkış, rezervasyon no bulunur; seçilenler seyahate eklenir |
| Duraklar arası süre | Kuş uçuşu tahmin | Apple Haritalar'dan yürüme ve (uzun mesafede) toplu taşıma süresi; ağ yoksa tahmin |
| Uçuş durumu | Elle girilen kapı | AeroDataBox'tan rötar, kapı, terminal ve aşama; bilet koçanında "Rötarlı +40 dk" ve üstü çizili eski saat; kapı değişince, rötar olunca, biniş başlayınca bildirim; uygulama açılınca ve arka planda yenilenir |
| Ana ekran widget'ı | — | Küçük: sıradaki seyahate kalan gün; seyahatteyken "3. gün / 7" ve günün sıradaki durağı. Orta: ek olarak uçuş ve tarihler. Dokununca ilgili seyahat açılır |
| Bildirimden geçiş | Ana ekran açılır | Bildirime dokununca ilgili seyahatin ilgili sekmesi: harcama → Bütçe, valiz → Valiz, durak/uçuş → Plan, katılım → Ekip; widget ve canlı kart da aynı bağlantıyı kullanır |
| Seyahat onayı | Düz damga inişi | Bilet perspektifle masaya yatar, 3B ahşap mühür gölgesiyle süzülüp bastırır, iz kalır, mühür kalkar; bilet doğrulup desteye uçar |
| Canlı uçuş kartı | — | Uçuştan 6 saat önce kilit ekranı ve Dynamic Island'da bilet: rota, kapı, koltuk, kalkışa geri sayım, durum (Zamanında/Biniş/Havada); 24 saat içinde elle de açılır, inişte kapanır |
| Durak ekle | Yalnızca metin sonuç listesi | Numaralı sonuçlar ve aynı numaralarla harita önizlemesi; seçilen yer yeşil işaretle |
| Yeni seyahat | Düz form | Yazdıkça güncellenen canlı bilet kartı + fotoğraf ekleme |

## Dış servisler
- **Frankfurter** (api.frankfurter.app): Avrupa Merkez Bankası referans kurları, anahtarsız. ECB'nin yayınlamadığı para birimleri (AMD, GEL, AZN, RSD, MAD…) için kur elle girilir.
- **Open-Meteo**: hava tahmini ve arşiv, anahtarsız; ticari kullanımda lisans koşulları kontrol edilmeli.
- **Apple CLGeocoder**: koordinatı olmayan seyahatlerin şehri bir kez konuma çevrilip kaydedilir.
- **OpenStreetMap Overpass API**: durak çevresindeki (80 m) aynı adlı yerin `opening_hours` etiketi; her durak bir kez sorgulanır, istekler arasında 1 sn beklenir. Yoğun kullanımda kendi Overpass sunucusu ya da önbellek gerekir. Veri ODbL lisanslı; uygulamada atıf gösterilmeli.
- **AeroDataBox** (RapidAPI): uçuş durumu, kapı, terminal, tahmini saatler; anahtarlı, ücretsiz katmanı aylık kotalı.
- **Apple Vision**: makbuz metni tamamen cihazda okunur, görüntü hiçbir yere gönderilmez.

## Atıflar
Lisans gereği görünür atıf gereken yerler: plan listesinin altında (açılış saatleri varsa) "© OpenStreetMap katkıcıları" bağlantısı, açılış saati düzenleyicisinde, valizdeki hava kartında "Open-Meteo", döviz satırında "ECB", ve hepsi "Hakkında" ekranında bağlantılarıyla.

## Bilinen sınırlar
- Anlık güncelleme sessiz push'a dayanır; iOS bunları geciktirebilir ya da düşük güç modunda atlayabilir, uygulama öne gelince yine eşitlenir.
- Uçuş durumu için AeroDataBox (RapidAPI) anahtarı gerekir; anahtar yoksa kapı/saat elle girilen bilgidir. Ücretsiz kota düşük olduğundan aynı uçuş en fazla 5 dakikada bir, yalnızca kalkışa 36 saat kala sorulur.
- Kilit ekranı kartı uygulama açıkken ya da arka plan yenilemesinde güncellenir; iOS arka plan yenilemesini seyrekleştirebilir. Anında güncelleme için sunucudan Live Activity push'u gerekir.
- Çevrimdışı harita yakınlaştırılamayan bir görüntüdür; adım adım yol tarifi için Apple Haritalar'ın çevrimdışı haritaları önerilir.

## Sonraki adaylar
- Canlı kartı sunucudan push ile güncellemek (uygulama kapalıyken bile anında rötar/kapı).
- Etkileşimli widget: valiz maddesini widget'tan işaretlemek.
- Kilit ekranı widget'ı (saatin altındaki küçük alan): kalan gün.
