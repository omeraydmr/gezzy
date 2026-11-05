# Animated survey + in-app hints — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Turn the onboarding survey ("Nasıl seyahat ediyorsun?") from one long page of text chips into a short, animated, one-question-per-card flow in the "Kartpostal" style, and add a small hint system that teaches hidden gestures (deck swipe, QR invite, long-press menus, drag to reorder, map long-press) with short demo animations.

**Architecture:**
- Survey logic (which sub-steps, auto-advance, order of interests) moves into `GezzyKit/Onboarding.swift` so it can be unit-tested. Views live in a new `Features/Onboarding/Survey/` folder; `OnboardingView` only hosts them.
- Hints use **TipKit** (iOS 17, already our target) for *when* to show (rules, events, "show once", invalidate after the action). A custom `TipViewStyle` + small demo animations give them the Gezzy look. Which hint comes first is decided by a pure `HintPlanner` in GezzyKit, ordered by the user's survey interests.
- One motion helper (`Animation.gezzy`) that respects Reduce Motion — this also closes audit item #7 in `docs/06-ui-ux-audit.md`.

**Tech Stack:** SwiftUI iOS 17, Swift 6, TipKit, SF Symbols effects (`symbolEffect`), `phaseAnimator` / `keyframeAnimator`, `sensoryFeedback`.

**Why not Remotion:** Remotion renders videos, not app UI. Everything here is native SwiftUI. (Optional later: a Remotion promo clip of the new onboarding for the App Store / socials — out of scope.)

## Current state (what we found)

- `OnboardingView.swift` → `survey`: 3 questions + `RouteSharingPrompt` stacked on one scrolling page, plain text capsules, only a 0.25 s spring on selection.
- Interest **order matters** (first pick = first tab when a trip opens, see `TravelPreferences.preferredSection`) but the UI never shows the order. Users can't see why it matters.
- The progress dots treat the whole survey as one step.
- "Done" step shows 3 static text tips — the only "hints" in the app. `EmptyHint` is a static row.
- Hidden gestures with no hint today: deck swipe (`TripDeck`), QR corner tap → invite (`TripDeck.swift:55`), context menus on stops/expenses/packing/documents, drag to reorder stops (`PlanSection.swift:1243`), long-press on map to drop a pin (`PlacePickerMap.swift`), receipt scan (`ExpenseSheets.swift:294`).
- Reduce Motion is read in only 3 files.

## Global Constraints

- Build: `cd ios && xcodebuild -project Gezzy.xcodeproj -scheme Gezzy -destination 'platform=iOS Simulator,name=iPhone Air' build`; after adding files run `cd ios && xcodegen generate` first. Tests: `cd ios/Packages/GezzyKit && swift test`.
- Keep `TravelPreferences` Codable shape unchanged (stored under `gezzy.preferences`). Keep `RouteSharingPrompt` behaviour: "Hayır" opens the paywall; non-premium users must answer before continuing; "Şimdilik geç" still skips everything.
- Motion: springs 200–400 ms (design doc §9). Every new animation goes through `Animation.gezzy(...)`; with Reduce Motion on → short cross-fade or nothing, and gesture demos become a static icon.
- Never more than **one** hint on screen. No hint during the first 2 seconds of a screen, never on top of a sheet, never during the stamp ceremony.
- Tap targets ≥ 44 pt, VoiceOver labels on every tile, selection order read aloud ("1. seçim").
- New strings in Turkish, `en` added by hand to `Localizable.xcstrings` (don't let the build rewrite the file).
- Comments in Turkish, short. Stage only files you changed.

---

### Task 0: Motion foundation

**Files:** Create `ios/Gezzy/DesignSystem/Motion.swift`

- [ ] `extension Animation { static func gezzy(_ base: Animation = .spring(duration: 0.35), reduceMotion: Bool) -> Animation? }` → `nil`/`.easeOut(0.15)` when reduced.
- [ ] `ViewModifier` `.gezzyAppear(delay:)` — fade + 12 pt rise, used for staggered entrances; static when reduced.
- [ ] Replace the springs in `OnboardingView.go(_:)` and `chips` with the helper.
- [ ] Build; commit `"Add Reduce Motion aware animation helper"`.

### Task 1: Survey model in GezzyKit (testable)

**Files:** Modify `GezzyKit/Onboarding.swift`; add `Tests/GezzyKitTests/SurveyFlowTests.swift`

- [ ] `public enum SurveyQuestion: CaseIterable { case companion, frequency, interests, routeSharing }`.
- [ ] `public struct SurveyFlow` — `questions(isPremium:)` (drops `.routeSharing` for premium), `next/previous`, `autoAdvances(_:)` (true for single-choice `companion`, `frequency`), `canContinue(...)`.
- [ ] `TravelPreferences.rank(of: Interest) -> Int?` (1-based) for the order badges.
- [ ] Tests: premium skips route step; toggling keeps order; `rank` updates after removing the first pick; `preferredSection` unchanged.
- [ ] Commit `"Model the onboarding survey as a step flow"`.

### Task 2: One question per card + segmented progress

**Files:** Create `Features/Onboarding/Survey/SurveyPager.swift`; modify `OnboardingView.swift`

- [ ] `survey` step hosts `SurveyPager` (own `@State question`). Each question is a "postcard" card (`tray`, large radius, slight tilt −1°…1° that straightens on appear).
- [ ] Card transition: next card slides in from trailing with a small rotation + scale 0.96 → 1; previous card lifts off to leading. Reduced: cross-fade.
- [ ] Header progress: the survey capsule splits into 3–4 mini segments that fill left → right (`matchedGeometryEffect` for the active segment).
- [ ] Single-choice questions auto-advance 0.45 s after a tap (with `.sensoryFeedback(.selection)`); back button returns to the previous *question* before leaving the survey step.
- [ ] Footer: "Devam" only on interests + route steps; "Şimdilik geç" stays visible on every survey card.
- [ ] Build; commit.

### Task 3: Animated answer designs

**Files:** Create `Survey/CompanionCard.swift`, `Survey/FrequencyCard.swift`, `Survey/InterestsCard.swift`

- [ ] **Companion — "who's in the photo":** 2×2 large tiles (`person.fill`, `person.2.fill`, `person.3.fill`, `figure.2.and.child.holdinghands`). Tile pops (`symbolEffect(.bounce)`), tile border draws in. Above the grid, the user's own `AvatarView` (colour from profile step) sits alone; on selection, companion avatars slide in next to it (1 / 2 / 4) with a stagger.
- [ ] **Frequency — passport page:** a passport page with empty slots. Picking "1 kez" drops 1 `StampImprint`, "2–3 kez" drops 3, "4 ve üzeri" drops 5, each with a light impact haptic and a 70 ms stagger. Switching answers lifts extra stamps off. Reuses our stamp identity from `Stamp.swift`.
- [ ] **Interests — ordered tiles:** 5 icon tiles in a grid (map, chart.pie, person.text.rectangle, suitcase, photo.on.rectangle). Selecting shows a numbered badge (1, 2, 3…) that pops in; removing one renumbers the rest with `contentTransition(.numericText())`. Below, a live preview pill: "Seyahat açılınca önce: **Bütçe**" that morphs to the first pick (`contentTransition(.interpolate)`) — makes the order rule visible.
- [ ] **Route sharing:** existing `RouteSharingPrompt` inside a card; the "Evet" choice plays a short dotted-route draw (`trim` animation) across a mini map illustration.
- [ ] VoiceOver: tiles are buttons with `.isSelected` and value "1. seçim".
- [ ] Build; commit `"Animated survey answer cards"`.

### Task 4: Welcome and Done polish

**Files:** Modify `OnboardingView.swift`

- [ ] Welcome: hero icon does a one-time take-off (`airplane.departure` with `symbolEffect(.bounce)` + small offset), feature rows enter with `.gezzyAppear(delay: 0.06 * index)`.
- [ ] Done: a "postcard summary" built from the answers (avatars + stamps + first-interest icon) that flips in; replace the 3 static tips with "Uygulamayı kullanırken sana küçük ipuçları göstereceğiz" (the real tips now come from Task 6).
- [ ] Build; commit.

### Task 5: Hint engine (TipKit + planner)

**Files:** Create `GezzyKit/HintPlanner.swift` + tests; create `ios/Gezzy/Features/Hints/GezzyTips.swift`, `HintStyle.swift`; modify `GezzyApp.swift`

- [ ] `GezzyApp`: `try? Tips.configure([.displayFrequency(.daily), .datastoreLocation(.applicationDefault)])`. Debug launch args `-resetTips` → `Tips.resetDatastore()`, `-showAllTips` → `Tips.showAllTipsForTesting()`.
- [ ] `HintPlanner` (pure): `enum HintID` + `priority(for: TravelPreferences)` — e.g. `money` interest puts receipt-scan first, `planning` puts drag-reorder/map long-press first, `friends/family` puts QR invite first. Tested.
- [ ] One `Tip` per hint with `@Parameter`/`Event` rules. Each tip calls `invalidate(reason: .actionPerformed)` when the user does the gesture themselves — so people who already know it never see it.
- [ ] `GezzyTipStyle: TipViewStyle` — tray background, accent icon, title + 1 line, small demo slot (Task 6), close button 44 pt. Entrance: scale 0.9 → 1 + fade from the anchor.
- [ ] Profile: "İpuçlarını yeniden göster" row → reset datastore.
- [ ] Build; commit `"Add hint engine on TipKit"`.

### Task 6: Hint catalogue with demo animations

**Files:** Create `Features/Hints/HintDemos.swift`; add `.popoverTip` / `TipView` at the anchors below

| Hint | Where | Shows when | Demo animation |
|---|---|---|---|
| Swipe the deck | `TripsView` / `TripDeck` | ≥ 2 trips, deck never swiped | Front card nudges 24 pt left and back, a ghost finger slides (`keyframeAnimator`, 2 loops then stops) |
| QR invite | `TripDeck` QR corner | trip has 1 member, opened trip twice | Pulsing ring on the QR corner |
| First tab came from your answer | `TripDetailView` tab bar | first trip opened after onboarding | Selected tab pill glows once; text "Bütçe'yi seçtiğin için önce bu açıldı" |
| Ticket row → reservations | `TripTicketRow` | has a flight, never tapped | Row shimmer sweep |
| Long-press for more | first stop / expense / packing row | 3+ items, never opened a context menu | Row presses down (scale 0.97) and a menu ghost fades in |
| Drag to reorder | `PlanSection` day list | day has ≥ 3 stops | Drag handle wiggles, a row lifts 8 pt |
| Long-press map for a pin | `PlacePickerMap` | opened picker twice, no pin dropped | Pin drops with bounce + ripple |
| Scan a receipt | expense sheet camera button | 3rd manual expense | Camera icon `symbolEffect(.pulse)` |

- [ ] Each demo has a static fallback for Reduce Motion and runs at most 2 cycles.
- [ ] Anchors respect "one hint at a time": tips declare `Tips.MaxDisplayCount(1)` and the planner order decides which is eligible first.
- [ ] Build; commit per 2–3 hints.

### Task 7: Verify

- [ ] `swift test` green (SurveyFlow, HintPlanner).
- [ ] Simulator pass: fresh install with `-resetTips`; full onboarding as non-premium (route "Hayır" → paywall → back to survey still works) and premium; Reduce Motion on; VoiceOver on survey; Dynamic Type XXL on survey cards; dark mode.
- [ ] Record a short screen capture of the survey and each hint for the PR.
- [ ] Update `docs/03-tasarim-dili.md` §9 Hareket with the survey/hint motion rules.

## Open questions

1. Auto-advance on single-choice questions — OK, or always require "Devam"?
2. Should hints also appear for existing users (who finished onboarding before this ships)? Default proposal: yes, but only "invalidate on action" ones, so power users won't see them.
3. Any analytics wanted for survey drop-off per question? (Currently none; would need a decision on privacy text.)
