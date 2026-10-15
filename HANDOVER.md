# Nearby — Handover (2026-10-13)

TL;DR: Phase 1 + Phase 2 (friends, shared lists, shared pins) are built and tested on the emulator (owner) and the iQOO (friend), live updates both ways. Open: confirm migration 005, unfriend test, friend arrival alert in the real world.

Read this first, then `CLAUDE.md` (original brief) and `_SESSION_SUMMARY.md` (step-by-step log).

## 1. Where things stand

| Area | State |
|---|---|
| Places + reminders, offline-first sync | Done, tested |
| Background geofence alerts (native_geofence) | Done. Emulator: fires ~10 s after entry. iQOO release build: tested OK by user |
| Notification tap opens place, "Done" action | Done, tested |
| Search / map tiles / routing on Geoapify | Done, tested (key in config.json) |
| Trip planner (shortest order via Route Matrix + Held-Karp) | Done, unit-tested |
| Redesign: bottom tabs Home / Map / Trips / Profile | Done, tested |
| "How often" (once) + active hours per place | Done, tested |
| Friends (search, request, accept, WhatsApp invite text) | Done, tested on 2 accounts |
| Shared lists (claim / bought, live updates, share View/Can buy, friend alerts) | Done. 2-phone test 2026-10-13: add, claim, bought all live in ~3 s both ways. Friend arrival alert not yet tested |
| Shared places as pins on friend's Map | Done, tested on iQOO. Tap opens list, long-press opens a details sheet (`widgets/shared_place_sheet.dart`). Hidden while a category filter is on |
| Phase 3 (receipts, payments) | Done, tested on 2 devices, released v1.1.0. Receipt photo + amount by the buyer, owner pays outside the app and marks paid (settles the item, final). Payment details in Profile, friends only. Unused placeholder files from the CLAUDE.md layout were removed (list state lives in the screens, claim/permission UI in the list and share screens) |

## 2. Do these first

1. Real-world arrival test on the iQOO (release build v1.0.2, battery exempt).

## 3. Run it

```
cd ~/NearbyApp
flutter test                                        # 5 test files, all passing as of e260e2d
flutter run --dart-define-from-file=config.json     # emulator
flutter run -d <iQOO id> --release --dart-define-from-file=config.json
flutter emulators --launch Medium_Phone_API_36.0
```
- `config.json` (gitignored) holds `SUPABASE_URL`, `SUPABASE_ANON_KEY` (publishable key), `GEOAPIFY_KEY`. Template: `config.example.json`. Never commit or paste keys; the user adds keys himself.
- Without `GEOAPIFY_KEY` the app falls back to public OSM / Photon / OSRM demo servers (dev only).
- Emulator GPS test: `bash tools/geofence_test.sh [home|asrama]` (drives `adb emu geo fix`, keeps Google Maps in front, greps logcat for `NEARBY_GEOFENCE`, saves logs to `tools/geofence_logs/`, gitignored). Use `adb -e` / `adb -d` when both devices are plugged in.
- Logcat markers: `NEARBY_GEOFENCE ... notified= inWindow= once=` and `NEARBY_DONE zone= turnedOff=`.

## 4. Architecture (as built; deviations from CLAUDE.md noted)

- **State:** provider. `AuthProvider`, `ZoneProvider`, `FriendProvider` above `MaterialApp` (`lib/app.dart`). `ShellNav` (tab + Home→Map filter requests) inside `AppShell`.
- **Local store:** sqflite, DB version 4 (`local_db_service.dart`): `zones` (+ category, once_only, active_from/to), `zone_reminders`, `trigger_log`, `app_meta`, `shared_places` (cache of places shared with me, read by the geofence isolate).
- **Sync:** `sync_service.dart` push pending → pull; pulls never overwrite rows with local pending changes (`saveRemoteReminder` / `deleteSyncedReminder`).
- **Geofencing:** one OS fence per own zone (id = zone id) + one per claim-shared place (id = `s:<zoneId>`). Background callback `onGeofenceEvent` reads local DB only (no network). Quiet outside active hours; "once" turns reminders off after alerting.
- **Notifications:** payload = zone id, or `list:<listId>` for shared. "Done" action runs in a background isolate and pings the open app via `IsolateNameServer` port `nearby_done`.
- **Shared lists:** server-only (no offline copy), `list_repository.dart`; live updates via Supabase Realtime on `list_items` (unique channel topic per screen; deletes via unfiltered delete listener).
- **External APIs:** Geoapify tiles (`osm-carto @2x`), Autocomplete, Routing, Route Matrix. Attribution "Powered by Geoapify · © OpenStreetMap contributors" required on every map (`widgets/map_credit.dart`).
- **Release build:** `android/app/proguard-rules.pro` keeps WorkManager's Room DB + native_geofence classes (release crashed on launch without it). `res/raw/keep.xml` keeps the notification icon.

## 5. Supabase (project `nearby`, Singapore region)

Migrations in `supabase/`, applied in order via the dashboard SQL editor. **Add-only rule**: never drop or rewrite user data.

| File | Status |
|---|---|
| 001_phase1.sql (profiles, zones, zone_reminders, RLS) | Applied |
| 002_zone_category.sql | Applied |
| 003_zone_schedule.sql (once_only, active_from/to) | Applied, verified |
| 004_friends_lists.sql (friends, shared_lists, list_access, list_items, RLS helpers, realtime) | Applied, 4 tables verified with RLS |
| 005_lists_hardening.sql (status-only accept, unfriend revokes access, item column grants + claim guard, `is_my_friend`, one list per zone) | Applied 2026-10-14 (re-run in a transaction), verified |
| 006_receipts_payments.sql (receipts, payment_records, friends-only payment_details, settle trigger + settled guard, private buckets receipts / payment-qr) | Applied 2026-10-14 in a transaction, verified |
| 007_fix_receipt_upload_policy.sql (qualify objects.name in the receipt photo upload policy; 006 always refused uploads) | Applied 2026-10-14, verified |

RLS helpers are `SECURITY DEFINER` (owns_zone, owns_list, list_permission, zone_shared_with_me, is_my_friend) to avoid policy recursion between zones and shared_lists.

## 6. Test checklist still open

- [x] Shared pins visible on friend's Map; tap opens list; category filter hides them
- [x] Emulator (owner) list "Barang Home" with Beras, Telur x30, Gula, shared with syaheerdaniel23 as Can buy
- [x] iQOO (friend): Home shows "Shared with you"; claim / bought / owner adds all update live (~3 s)
- [ ] Friend arrival alert lists open items. Needs the iQOO to physically arrive (geofence_test.sh only mocks emulator GPS, and the emulator is the owner account)
- [ ] Check GMS "registration not permitted" warning on iQOO (logged on each reinstall/refresh for the 150 m Home fence; perms are granted, likely re-register noise). A real arrival settles it
- [x] Unfriend → friend loses the list (2026-10-14: aina removed hafiz, list_access 1 → 0 via friends_revoke_access trigger)
- [ ] Real-world iQOO walk to a shared place

## 7. Known limits / decisions

- Build warning "plugins that apply Kotlin Gradle Plugin (KGP): native_geofence": not fixable on our side yet (checked 2026-10-15). native_geofence 1.3.1 (latest) already supports built-in Kotlin, but setting `android.builtInKotlin=true` breaks the build because `app_links` 7.2.2 (latest, pulled in by supabase_flutter) still applies KGP unconditionally. Retry when app_links updates.

- Friend's alert shows open items as of their last refresh (cached locally for offline alerts). Cache refreshes on app resume, Home pull-to-refresh, and on leaving a shared list.
- Friends see only the owner + themselves in a list's member line (RLS hides other friends' access rows).
- "View" shares don't get map pins or alerts; only "Can buy".
- Distances on Home are straight-line (no API cost). Trip planner uses road times.
- WhatsApp invite is plain text with the username (no deep link; needs a domain/app-links setup).
- Geoapify free plan: 3,000 credits/day, attribution required. Supabase free plan pauses after 1 week idle.
- Android only; iOS not set up.

## 8. Next ideas (agreed order)

1. Finish section 2 + 6.
2. Portfolio packaging: demo video, README screenshots, APK, card on syaheerdaniel.dev.
3. "Any branch" reminders (any Mydin / 99 Speedmart nearby) — Geoapify Places, mind Android's 100-fence limit.
4. Phase 3 (receipts, settle up) from CLAUDE.md.

## 9. Working rules (from the user)

- Terse replies. Plan + checklist before multi-step work; show mockups/drafts and wait for "go" before applying.
- No AI-isms or em dashes in drafted copy. Don't overclaim.
- Keys/secrets: never ask for or paste them; user edits `config.json` himself.
- Supabase changes are add-only; run SQL only after the user approves the plan.
- Update `_SESSION_SUMMARY.md` after each task.
- User runs flutter/adb on his Mac and pastes output; review code carefully since compile happens on his side.
