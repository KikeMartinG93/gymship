# Gymship

SwiftUI iOS app that finds shared free time for a workout group by reading
everyone's calendars and syncing busy blocks through Supabase.

## Stack

- SwiftUI (iOS 27+), Liquid Glass on chrome and controls, concentric content surfaces
- EventKit for reading device calendars and writing confirmed workouts
- On-device Apple Intelligence (`FoundationModels`) for slot picking and the Agent tab
- Supabase Swift SDK (auth, Postgres) — free tier

## Project layout

```
Gymship/
  App/            GymshipApp.swift, AppState.swift
  Models/         CalendarModels.swift, SupabaseModels.swift
  Managers/       ThemeManager, EventKit, ETA, WorkoutSlotFinder, PowerState
  Services/       SupabaseService.swift, SupabaseConfig.swift
  Views/          RootView, Onboarding/, Calendar/, Group/, Components/
  Extensions/     GlassStyle.swift (glass surfaces, concentric cards, GymshipBackground)
  Resources/      Info.plist, Assets.xcassets, PrivacyInfo.xcprivacy
Docs/
  supabase_schema.sql   Full schema + RLS policies + Realtime setup
project.yml              XcodeGen project spec
```

The `.xcodeproj` is generated, not hand-maintained — see below.

## First-time setup

1. **Generate the Xcode project.** This repo uses [XcodeGen](https://github.com/yonaskolb/XcodeGen)
   instead of committing a `.xcodeproj`, so file adds/removes never cause merge conflicts.

   ```bash
   brew install xcodegen   # or: mint install yonaskolb/XcodeGen
   xcodegen generate
   open Gymship.xcodeproj
   ```

   Xcode resolves the `supabase-swift` Swift Package automatically on first open/build.

2. **Create the Supabase project** (free tier is enough) at supabase.com, then in the
   SQL Editor run [`Docs/supabase_schema.sql`](Docs/supabase_schema.sql). It creates
   `profiles`, `groups`, `group_members`, `busy_slots`, RLS policies for every table,
   a trigger capping groups at 5 members, and enables Realtime on `busy_slots`.

3. **Fill in credentials** in [`Gymship/Services/SupabaseConfig.swift`](Gymship/Services/SupabaseConfig.swift):

   ```swift
   static let url = URL(string: "https://YOUR-PROJECT-REF.supabase.co")!
   static let anonKey = "YOUR-SUPABASE-ANON-KEY"
   ```

4. Build and run on a simulator or device (iOS 27+). On first calendar-access
   request, the system prompt uses the string from
   `NSCalendarsFullAccessUsageDescription` in `project.yml`. Prefer the
   **iPhone Air** simulator when checking layout and the settling mesh background.

## What's implemented

**EventKit (`Managers/EventKitManager.swift`)**
- `requestAccess()` — requests full calendar access (`requestFullAccessToEvents`)
- `refreshCalendars()` — lists all active event calendars as `GymCalendar`
- `setAvailability(_:for:)` — per-calendar Available/Unavailable toggle, persisted to `UserDefaults`
- `refreshBusySlotsForCurrentWeek()` — pulls events from Unavailable calendars for the
  current Mon–Sun week and merges overlapping ranges into `[BusySlot]` (`[DateInterval]`)
- `writeWorkoutSlot(_:)` — creates (once) a dedicated "Gymship Workouts" calendar and
  writes a confirmed `EKEvent` to it; `removeWorkoutSlot(eventIdentifier:)` to undo

**Supabase (`Services/SupabaseService.swift`)**
- Email one-time code (sideload-friendly; Sign in with Apple needs a paid Apple team)
- `createProfile(handle:name:)` / `fetchProfile()` / `findProfile(byHandle:)`
- `createGroup(name:)` / `joinGroup(withInviteCode:)` — 5-member cap enforced both
  client-side (pre-check) and server-side (DB trigger)
- `syncBusySlots(_:)` — replaces the signed-in user's `busy_slots` rows for the group
- `refreshHomeData()` — coalesced groups + proposals + commitments fetch

**UI** — Plan (week dial), Crews, Agent, You, onboarding, calendar setup, ride planner.
Content sits on a shared mesh background that settles after a few seconds. Scroll
views use `.scrollEdgeEffectStyle(.soft)`. Liquid Glass is reserved for the tab bar,
buttons, and chips.

## Sideloading (no TestFlight)

There is no paid Apple Developer Program on this project, so builds go out as an **unsigned IPA** that testers re-sign in [FlareStore](https://flarestore.app/guide/ios/).

1. Install FlareStore on the iPhone.
2. Add this source URL (raw `apps.json` on GitHub):

   `https://raw.githubusercontent.com/KikeMartinG93/gymship/main/flarestore/apps.json`

3. Download Gymship, **Sign** it with your Apple ID, then **Install**.
4. Free Apple IDs expire after 7 days and cap at 3 sideloaded apps. Sign in is an **email 6-digit code** (Sign in with Apple is a paid Apple capability and does not work after a free-ID re-sign).

In the Supabase dashboard, Authentication → Providers → Email must be enabled, and the Magic Link template should include `{{ .Token }}` so the 6-digit code arrives in the email.

To build the IPA locally:

```bash
Scripts/build-ipa.sh
# writes build/Gymship.ipa
```

Pushing a `v*` tag (for example `v1.2.0`) runs [`.github/workflows/release-ipa.yml`](.github/workflows/release-ipa.yml), which attaches `Gymship.ipa` to a GitHub Release. Then update `downloadURL` and `size` in [`flarestore/apps.json`](flarestore/apps.json).

## Verified

`xcodebuild -scheme Gymship -destination 'platform=iOS Simulator,name=iPhone Air' build`
against the real `supabase-swift` package.
