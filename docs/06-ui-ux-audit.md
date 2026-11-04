# Gezzy UI/UX audit — light & dark

Date: 2026-11-04 · Build: Debug 0.1.0 (2), branch `feature/community-places` · Device: iPhone Air simulator (iOS 27)

Screens checked in both themes: Trips home, New trip sheet, Trip detail (Plan, Rezervasyon, Para, Daha fazla grid, Valiz, Vize, Ekip, Anılar), Profile, Hakkında/Ayarlar.
Not checked live: Onboarding, Paywall, Share Studio, place picker, expense editor, emergency views. Those were only skimmed in code.

Severity: **P0** broken / blocks the user · **P1** accessibility or clear usability problem · **P2** UX friction · **P3** polish.

---

## P0 — Bugs

### 1. ✅ Fixed — Tab switch from a long scrolled tab can show an empty screen
- Steps: Trip detail → Para → scroll to the expense list → tap "Daha fazla".
- Seen once: whole screen went blank, the pinned tab bar disappeared too, until a manual scroll up brought content back.
- Other times: content swaps only after ~1 s, and taps made during that time are dropped (had to tap "Daha fazla", Ekip, Anılar and the home CTA twice).
- Code: [TripDetailView.swift:128](../ios/Gezzy/Features/TripDetail/TripDetailView.swift:128) — `onChange(of: contentID)` → animated `scrollTo` inside a `LazyVStack` with pinned header, plus `.transition(.opacity)` and `.id(contentID)` on the content. The old content is removed before the new one is laid out, so the scroll offset can point past the end.
- Fix idea: reset the offset without animation before swapping content (`scrollPosition` binding or `proxy.scrollTo` with no animation), drop the opacity transition on a full content swap, and test on device to see if the ~1 s lag is simulator-only.

### 2. ✅ Fixed — "On" switches are nearly invisible in dark mode (confirmed)
- The whole app gets `.tint(Color.ink)` in [GezzyApp.swift:19](../ios/Gezzy/App/GezzyApp.swift:19). In dark mode `ink` is `#F2F2F3`, so an "on" `Toggle` becomes a near-white track with a white knob (contrast **1.12:1**). On/off can't be told apart.
- Affects every toggle: Seyahat bildirimleri, Rotamı paylaş, Taslak, Planı da kaydır, Yalnızca bu cihazda, onboarding toggles, etc.
- Not confirmed with a screenshot (didn't want to flip real settings). Easy to confirm: turn on "Taslak olarak kaydet" in New trip, dark mode.
- Fix: give `Toggle` its own tint (e.g. `Color.success` or the trip accent), or a small `ToggleStyle` in the design system.

### 3. ✅ Fixed — "Fotoğraf ekle" overlaps the day-count badge in the New trip preview
- [NewTripSheet.swift:128](../ios/Gezzy/Features/Trips/NewTripSheet.swift:128): the camera button and the "30 gün" badge collide at the top of the tilted ticket.
- Fix: put the button bottom-left of the cover, or hide the badge in the preview.

---

## P1 — Accessibility & contrast

### 4. `ink3` is used for real text and fails contrast in both themes
| Pair | Ratio | Needs |
|---|---|---|
| `ink3` on `tray` (light) | 2.27 | 4.5 |
| `ink3` on `surface` (light) | 2.08 | 4.5 |
| `ink3` on `tray` (dark) | 3.14 | 4.5 |

81 `.foregroundStyle(.ink3)` uses. Visible as: glance-tile captions (Vize/Bütçe/Valiz), flight codes ("TK1783 · koltuk 23A"), booking refs, "öder/alır" under settlement avatars, "Madde ekle" / "Yapılacak ekle" placeholders, profile footnotes, data-source licence lines.
- Fix: darken light `ink3` to about `#80848C` (≈3.9:1, ok for large/secondary) and use `ink2` (5.0:1) for anything that must be read. Keep `ink3` for icons, dividers and disabled text only. Token: [Theme.swift:29](../ios/Gezzy/DesignSystem/Theme.swift:29).

### 5. Category colors used as text fail in light mode
| Text | Ratio on white |
|---|---|
| Konaklama green `#3EC58F` ("DKK 7.600") | 2.19 |
| Yemek orange `#F2814A` ("DKK 620", settlement amounts) | 2.62 |
| Yemek orange on its tint (`Atanmadı` pills, settlement pill) | 2.30 |
| Aktivite purple `#D158D6` | 3.46 |
| Ulaşım blue `#5B78EE` ("Ülke ekle ya da çıkar") | 3.91 |
| Green on mint ("Geçerli ✓", "85 gün kalır") | ≈2 |

In dark mode the same colors read fine. Fix: add a `text` variant per `Accent` (darker in light, as-is in dark) — same idea you already use for trips with `tripText` / `accentText`. Keep the bright color for bars, icons and rings.

### 6. Dynamic Type is partly blocked
- 72 places use `.font(.system(size:))` with fixed sizes (10–26 pt), so they don't grow with the user's text size. Many important labels sit in fixed-size or `minimumScaleFactor` containers (glance tiles, ticket card).
- Fix: switch fixed sizes to text styles (`.caption`, `.footnote`…) or `@ScaledMetric`; test at AX3.

### 7. Reduce Motion only partly respected
- 116 animations, but `accessibilityReduceMotion` is read only in `Stamp.swift` and `TripDetailView.swift`. The deck springs, ticket fly-in after create, tint glow and tab transitions still animate.
- Fix: one `Animation.gezzy(_:)` helper that returns `nil` (or a short fade) when Reduce Motion is on.

### 8. Small tap targets
- `.circleIcon(size: 32)` in [SharedAlbumViews.swift:34](../ios/Gezzy/Features/Memories/SharedAlbumViews.swift:34) and 32×32 icon buttons in [CommunityShareCard.swift:225](../ios/Gezzy/Features/Memories/CommunityShareCard.swift:225) are below 44 pt. Keep the visual size, add `.contentShape` + `.frame(minWidth: 44, minHeight: 44)`.

---

## P2 — UX friction

### Trips home
9. **Header title is gray** (`ink2`) and the same size as the picker — the screen has no clear title. Use `ink` or drop the label and keep only the icon.
10. **Ticket repeats the city**: "Kopenhag" title + "Kopenhag · 19–23 Kas" subtitle. For single-city trips show country or dates only ("Danimarka · 19–23 Kas").
11. **One-trip page indicator**: the deck dot shows with a single trip. Hide it when `trips.count == 1`.
12. **Large dead gap** between glance tiles and "Seyahat planla" (~35% of screen). Use it for the next action ("Sonraki: uçuş 15 gün sonra, 08:25") or today's plan when the trip is live.

### Trip detail — shared
13. **Tab labels don't line up**: "Rezervasyon" sits lower than Plan/Para/Daha fazla because the suitcase icon is taller. Give icons a fixed frame (e.g. 24×24) so labels share a baseline.
14. **Changing tab name**: when you open Valiz from "Daha fazla", the 4th tab is renamed "Valiz"/"Vize"/"Ekip"/"Anılar", and a second back link "‹ Daha fazla" appears under the nav back button. Two back controls on one screen is confusing. Options: keep the 4th tab named "Daha fazla" with a small sub-label, or show these 4 sections as a segmented row under the tab bar.
15. **Back / ••• buttons over the light cover** are pale glass on pale green — hard to see in both themes. Add a dark scrim at the top of the hero or a stronger material.
16. **"15 gün" pill in dark mode**: olive text on dark olive, low contrast.
17. **Section headers are gray** (Bütçe, Harcamalar, Valiz, Vize, Ekip…) while the sentence under them is black and bigger. Fine as a style, but the header icon + gray title + green "+" in one row reads as three weights; consider `ink` for the title.

### Plan
18. **Stacked pins**: stops 1–4 near Hotel SP34 overlap; pin 4 is mostly hidden. Cluster or offset overlapping pins, or fit the map tighter to the selected day.
19. **Route-optimize button is icon-only** (curvy path). It has an a11y label but no visible one; most users won't know it reorders the day. Add a short label ("Rotayı diz") or a first-use tooltip.
20. **Two "add" buttons in Fikirler** (header "+" and a "+" per row) with different meanings (new idea vs add to day). Use a different icon for "add to day" (e.g. `calendar.badge.plus`).
21. **Dark map**: route dots (olive) almost vanish on the dark map.

### Rezervasyon
22. Hotel dates wrap and leave "13:00" on its own line. Use a two-line layout ("Giriş 19 Per 17:00" / "Çıkış 23 Pzt 13:00").
23. Flight duration "4 sa 20 dk" next to 08:25→10:45 looks wrong at a glance (time-zone change). Add "(yerel saat)" or show "+1 sa saat farkı".

### Para
24. **Expense titles are cut** ("Torvehallerne akşa…", "Hotel SP34 (4 gec…") because the subtitle line also repeats the date already shown in the group header ("· 19…"). Drop the date from rows; allow 2 lines for the title.
25. **"kalan DKK 7.795" is gray and wraps** under the total. Remaining budget is the number people look for — make it its own line in `ink`.
26. **No warning near a limit**: Konaklama 7.600 / 8.000 (95%) looks the same as Yemek at 14%. Turn the bar orange above ~90% and red when over.
27. **Mixed decimals**: "DKK 3.685" vs "DKK 2.054,99". Round settlement amounts the same way as the rest, or always show 2 decimals there.
28. **Tax-free has two add buttons** (header "+" and the dashed "Tax-free alışverişi ekle" card). Keep one while the list is empty.

### Valiz
29. **"Atanmadı" pill on every row** (6 of 7) in loud orange. Unassigned is the normal state; show nothing (or a faint person icon) and only show the avatar when assigned.
30. Group header shows a **"?" avatar with a green "3"** — meaning is unclear. Label it ("3 hazır · 4 kaldı").
31. Ring (%43) + progress bar + "3/7 madde hazır" say the same thing three times. Keep one.
32. Headline wraps mid-phrase ("…hazır. 15 / gün kaldı."). Put the countdown on its own line.

### Vize / Ekip / Anılar
33. "Başvuru" pill (New trip) and the "+" next to Schengen 90/180 look like buttons but it's unclear what they do. Make status pills non-pill text, and give the "+" a label ("Giriş ekle").
34. **Identity mismatch**: Profile name is "Ben", the crew owner is "Ömer". Anılar then says "Ortak albüm için önce Ekip sekmesinden kendini seyahate ekle" even though you own the trip. Link "me" to the owner member, or ask "Bu sen misin?" once.
35. **Dead-end hints**: Anılar "…Ekip sekmesinden kendini ekle" and Ekip "iCloud'a giriş yapılmamış. Ayarlar'dan…" are plain text. Add a button (go to Ekip / open Settings).
36. Empty photo state ("fotoğraf bulunamadı") has no next step (pick photos, check permission).

### Profile & settings
37. **Settings are hard to find**: notifications and iCloud live under "Hakkında, bildirimler ve veri kaynakları", inside a second sheet on top of the Profile sheet. Add a plain "Ayarlar" row at the top level of Profile, or move these into Profile.
38. **Missing common settings**: appearance (system/light/dark), default currency, notification detail (which reminders), data export/delete, privacy policy & terms, support/contact, rate the app.
39. Close buttons differ: Profile "Bitti", Hakkında "Tamam". Pick one.
40. IBAN hint has no action — the user must find "Düzenle". Make the row tappable.
41. Privacy copy ends with "Profil'den istediğin zaman değiştirebilirsin" while the user is already in Profile ([RouteSharingPrompt.swift:25](../ios/Gezzy/Features/Premium/RouteSharingPrompt.swift:25)). Use a context-free line here, or split the text.
42. Premium rows: icon widths differ, so "Premium'a geç" and "Satın alımları geri yükle" labels don't line up. Fixed-width icon frame.
43. "Ülke ekle ya da çıkar" is the only blue link in the app (uses transport blue). Use `ink` or the app tint.
44. Bell icon is `bell.badge` (with a dot) even when notifications are off — reads as "you have a notification".

### New trip
45. Country is pre-filled with **Portekiz** — looks random. Leave empty or pick from the last trip / locale.
46. "Oluştur" is disabled with no hint why. Show what's missing (e.g. "Şehir seç") or enable it and validate inline.
47. Trip name field has only a placeholder label; it disappears when typing.
48. Currency menu: 13 bare codes in no clear order. Show the country's currency first, then name + code ("DKK · Danimarka kronu").

---

## P3 — Polish (dark mode)
49. Cover art stays bright pastel in dark mode and glares on the black home screen. Lower its brightness ~10–15% in dark.
50. Blue icon on navy tint (Bütçe glance tile) is dim; same for purple on dark purple.
51. White primary CTA in dark mode is the brightest thing on screen; fine, but consider `tray` + border or the trip accent to match light mode's weight.

---

## What already works well
- Strong, consistent visual language (ticket/stamp/passport metaphors), good card rhythm, rounded corners consistent.
- Dark mode palette is well-made: category colors, tints and trays read better than in light.
- Helpful sentence headlines ("Herkes girişe hazır.", "İki transfer tüm seyahati kapatıyor.").
- Many icon buttons already carry `accessibilityLabel` (70 uses); glance tiles combine caption + value for VoiceOver.
- Pinned tab bar + collapsing hero is a good pattern once the switching bug is fixed.

## Suggested order
1. P0 #1 tab-switch blank screen, #2 toggle tint, #3 overlap.
2. Token pass: darker light `ink3`, `Accent.text` variants (#4, #5). Fixes most contrast issues in one change.
3. Valiz noise (#29–31), Para rows (#24–26), settings entry point (#37).
4. Dynamic Type and Reduce Motion sweep (#6, #7).
