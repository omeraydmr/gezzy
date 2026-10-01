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
| Durak ekle | Yalnızca metin sonuç listesi | Numaralı sonuçlar ve aynı numaralarla harita önizlemesi; seçilen yer yeşil işaretle |
| Yeni seyahat | Düz form | Yazdıkça güncellenen canlı bilet kartı + fotoğraf ekleme |

## Dış servisler
- **Frankfurter** (api.frankfurter.app): Avrupa Merkez Bankası referans kurları, anahtarsız. ECB'nin yayınlamadığı para birimleri (AMD, GEL, AZN, RSD, MAD…) için kur elle girilir.
- **Open-Meteo**: hava tahmini ve arşiv, anahtarsız; ticari kullanımda lisans koşulları kontrol edilmeli.
- **Apple CLGeocoder**: koordinatı olmayan seyahatlerin şehri bir kez konuma çevrilip kaydedilir.
- **OpenStreetMap Overpass API**: durak çevresindeki (80 m) aynı adlı yerin `opening_hours` etiketi; her durak bir kez sorgulanır, istekler arasında 1 sn beklenir. Yoğun kullanımda kendi Overpass sunucusu ya da önbellek gerekir. Veri ODbL lisanslı; uygulamada atıf gösterilmeli.
- **Apple Vision**: makbuz metni tamamen cihazda okunur, görüntü hiçbir yere gönderilmez.

## Sonraki adaylar
- Açılış saati uyarısında "uygun güne taşı" önerisi (durağın açık olduğu en yakın gün).
- OpenStreetMap atfının ayarlar/hakkında ekranında gösterilmesi.
- Makbuzdan kalem kalem okuma ve kişilere bölüştürme.
