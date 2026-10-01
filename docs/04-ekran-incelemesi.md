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
| Vize | Kişi listesi | Yatay kaydırılan bordo T.C. pasaport kartları; üzerinde hedef ülke bayrağıyla vize durumu "damgası" |
| Valiz | Başlık + liste | Seyahat renginde ilerleme halkası, kişiye göre filtre hapları |
| Ekip | Satır listesi | 2 sütunlu kişi kartları (rol, sahip tacı, vize durumu), kesikli "Kişi ekle" kartı |
| Yeni seyahat | Düz form | Yazdıkça güncellenen canlı bilet kartı + fotoğraf ekleme |

## Sonraki adaylar
- Harcama ekleme: hesap makinesi benzeri büyük tutar girişi + kategori hapları (form yerine).
- Durak ekleme: arama sonuçlarını küçük harita önizlemesiyle göstermek.
- Pasaport kartını kaydırınca detay sayfasının da kaydırmaya eşlik etmesi (deste ile aynı geometri).
