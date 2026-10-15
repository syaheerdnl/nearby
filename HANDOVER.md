# Nearby, handover (updated 2026-10-15)

TL;DR: Phases 1, 2 and 3 are built, tested on two devices and released (latest v1.2.0). The repo is public with README screenshots, a 57 s demo video and a portfolio card on syaheerdaniel.dev. One thing is still unproven: a real-world arrival alert on the iQOO with the app fully closed (the pass mark in CLAUDE.md section 9).

Read this first, then `CLAUDE.md` (original brief). `_SESSION_SUMMARY.md` is a local, gitignored step-by-step log on the user's Mac.

## 1. Where things stand

| Area | State |
|---|---|
| Places + reminders, offline-first sync | Done, tested |
| Background geofence alerts (native_geofence) | Done. Emulator: fires about 3 to 15 s after entry. Real-world walk on the iQOO with the app closed: **not done yet** (see section 2) |
| Notification tap opens place, "Done" action | Done, tested |
| Search / map tiles / routing on Geoapify | Done, tested. Search asks within 50 km first, then widens if fewer than 3 results |
| Trip planner (shortest order via Route Matrix + Held-Karp) | Done, unit-tested |
| Bottom tabs Home / Map / Trips / Profile | Done, tested |
| "How often" (once) + active hours per place | Done, tested |
| Friends (search, request, accept, WhatsApp invite text) | Done, tested |
| Shared lists (claim / bought, live updates, View / Can buy, friend alerts cache) | Done, 2-phone tested |
| Shared places as pins on a friend's Map | Done. Tap opens list, long-press opens a details sheet. Hidden while a category filter is on |
| Phase 3: receipts and settle up | Done, 2-phone tested (v1.1.0). Buyer adds receipt (photo + amount), owner pays outside the app and marks paid (settles the item, final). Payment details in Profile, friends only |
| You owe totals + Pay all | Done, 2-phone tested (v1.2.0). Card per friend on each list; Pay all marks every receipt in one insert (all or nothing) |

## 2. Do this first

1. **Real-world arrival test on the iQOO.** Install the latest release (v1.2.0), make sure it's signed in as the user's own account (it may still be on the demo account `hafiz`), close Nearby fully, walk at least 300 m away from a saved place and back in. Note the time of entry and of the alert. This also settles the open GMS "registration not permitted" log line (section 6).

## 3. Run it

```
cd ~/NearbyApp
flutter test                                        # 49 tests, all passing as of v1.2.0
flutter run --dart-define-from-file=config.json     # emulator
flutter run -d <iQOO id> --release --dart-define-from-file=config.json
flutter emulators --launch Medium_Phone_API_36.0
```
- `config.json` (gitignored) holds `SUPABASE_URL`, `SUPABASE_ANON_KEY` (publishable key), `GEOAPIFY_KEY`. Template: `config.example.json`. Never commit or paste keys; the user edits it himself.
- Release signing: `android/key.properties` + `nearby-release.jks` (both gitignored, user holds them; back them up). Without them the release build falls back to the debug key.
- Builds for the iQOO: release-signed universal APK from `~/NearbyApp`. Avoid `--split-per-abi` builds there (version code jumps to 200x and blocks later installs). The emulator currently has a split build installed, so it needs split builds too (or uninstall first).
- Emulator GPS test: `bash tools/geofence_test.sh [place name]`. Places come from `tools/geofence_places.txt` (gitignored, real locations); see `geofence_places.example.txt`. The emulator only takes `adb emu geo fix` while an app (Google Maps) is actively asking for location.
- Logcat markers: `NEARBY_GEOFENCE ... notified= inWindow= once=` and `NEARBY_DONE zone= turnedOff=`.

## 4. Architecture (as built; deviations from CLAUDE.md noted)

- **State:** provider. `AuthProvider`, `ZoneProvider`, `FriendProvider` above `MaterialApp` (`lib/app.dart`). `ShellNav` (tab + Home to Map filter requests) inside `AppShell`. No separate list provider: list state lives in the list screens.
- **Local store:** sqflite, DB version 4 (`local_db_service.dart`): `zones` (+ category, once_only, active_from/to), `zone_reminders`, `trigger_log`, `app_meta`, `shared_places` (cache of places shared with me, read by the geofence isolate).
- **Sync:** `sync_service.dart` push pending, then pull; pulls never overwrite rows with local pending changes.
- **Geofencing:** one OS fence per own zone (id = zone id) + one per claim-shared place (id = `s:<zoneId>`). Background callback reads local DB only (no network).
- **Notifications:** payload = zone id, or `list:<listId>` for shared. "Done" runs in a background isolate and pings the open app via `IsolateNameServer` port `nearby_done`.
- **Shared lists:** server-only, `list_repository.dart`; live updates via Supabase Realtime on `list_items`.
- **Receipts / payments:** server-only, `settlement_repository.dart`. Photos in private Storage buckets, shown via 10-minute signed URLs. Money kept as whole sen (`int`). Saving a receipt re-writes the item's status so the realtime listener fires. Who owes whom: `models/owed.dart` (`owedByPerson`). Error text: `settlementErrorMessage` (network vs refused vs generic).
- **External APIs:** Geoapify tiles, Autocomplete, Routing, Route Matrix. Every request sends `Referer: https://nearby.syaheerdaniel.dev/` (`AppConstants.httpHeaders`, `widgets/app_tile_layer.dart`). Attribution "Powered by Geoapify · © OpenStreetMap contributors" required on every map.
- **Release build:** `android/app/proguard-rules.pro` keeps WorkManager's Room DB + native_geofence classes. `res/raw/keep.xml` keeps the notification icon.

## 5. Supabase (project `nearby`, Singapore region)

Migrations in `supabase/`, applied in order via the dashboard SQL editor. **Add-only rule**: never drop or rewrite user data. Run new ones wrapped in `begin; ... commit;`.

| File | Status |
|---|---|
| 001_phase1.sql (profiles, zones, zone_reminders, RLS) | Applied |
| 002_zone_category.sql | Applied |
| 003_zone_schedule.sql (once_only, active_from/to) | Applied, verified |
| 004_friends_lists.sql (friends, shared_lists, list_access, list_items, RLS helpers, realtime) | Applied, verified |
| 005_lists_hardening.sql (status-only accept, unfriend revokes access, item column grants + claim guard, `is_my_friend`, one list per zone) | Applied 2026-10-14, verified |
| 006_receipts_payments.sql (receipts, payment_records, friends-only payment_details, settle trigger + settled guard, private buckets receipts / payment-qr) | Applied 2026-10-14, verified |
| 007_fix_receipt_upload_policy.sql (qualify `objects.name` in the receipt photo upload policy) | Applied 2026-10-14, verified |

- RLS helpers are `SECURITY DEFINER` (owns_zone, owns_list, list_permission, zone_shared_with_me, is_my_friend, item_list, can_see_list) to avoid policy recursion.
- Lesson from 006/007: inside a subquery in a policy, qualify every column (`objects.name`, `receipts.id`). An unqualified name binds to the innermost table that has it.
- Geoapify key (ends `b3dd`) has an HTTP Referer filter for `https://nearby.syaheerdaniel.dev/`. It blocks other referrers on the API but allows requests with no referrer, and the tile server doesn't enforce it. Real protection would need a server proxy.

**Demo data (keep, used for README screenshots and the demo video):** accounts `aina` (owner, places around KLCC) and `hafiz` (friend). They are friends; aina's "Groceries this week" (Jaya Grocer) is shared with hafiz as Can buy. hafiz has demo payment details (Maybank, HAFIZ DEMO, 1234 5678 9012) and two unpaid demo receipts (Susu RM 8.90, Telur RM 13.50). The user's own test list "Barang Home" is empty.

## 6. Test checklist still open

- [ ] Real-world iQOO walk into a saved place, app fully closed (section 2)
- [ ] Friend arrival alert lists open items (needs the friend's phone to physically arrive at a shared place)
- [ ] GMS "registration not permitted" log line on the iQOO (likely re-register noise; a real arrival settles it)

Done: shared pins, live claim/bought both ways, unfriend revokes access (005), receipts + mark paid, You owe + Pay all.

## 7. Known limits / decisions

- Build warning "plugins that apply Kotlin Gradle Plugin (KGP): native_geofence": not fixable on our side yet (checked 2026-10-15). native_geofence 1.3.1 already supports built-in Kotlin, but `android.builtInKotlin=true` breaks the build because `app_links` 7.2.2 (via supabase_flutter) still applies KGP. Retry when app_links updates.
- Friend's alert shows open items as of their last refresh (cached locally for offline alerts). Cache refreshes on app resume, Home pull-to-refresh, and on leaving a shared list.
- "View" shares don't get map pins or alerts; only "Can buy".
- Paid items are final (database guard). Pay all always pays all of a friend's receipts on a list.
- Distances on Home are straight-line (no API cost). Trip planner uses road times.
- WhatsApp invite is plain text with the username (no deep link).
- Geoapify free plan: 3,000 credits/day, attribution required. Supabase free plan pauses after 1 week idle.
- Android only; iOS not set up.

## 8. Releases and portfolio

- GitHub: https://github.com/syaheerdnl/nearby (public). History was cleaned of private data and author emails are the GitHub noreply address. Releases v1.0.0 to v1.2.0 (latest), APK + `nearby-demo.mp4` (57 s) on v1.2.0.
- Version rule: bump `pubspec.yaml` before each release (minor for features, patch for fixes), and the `+N` build number every time.
- Demo video source: `~/nearby-demo` (HyperFrames project, pinned `hyperframes@0.8.155`; raw clips in `assets/raw`, music from `assets/audio/make_bgm.sh <seconds>`).
- Portfolio card: `~/Projects/portfolio/portfolio-site` (card 03, video `nb-demo.mp4`). Push to main deploys.

## 9. Ideas not started

- WhatsApp share of a receipt (optional in CLAUDE.md Phase 3).
- Invite deep link (`nearby://invite/{username}`).
- iOS build.
- Scrapped: "any branch" reminders.

## 10. Working rules (from the user)

- Terse replies. Plan + checklist before multi-step work; show mockups/drafts and wait for "go" before applying.
- No AI-isms or em dashes in drafted copy. Don't overclaim.
- Keys/secrets: never ask for or paste them; user edits `config.json` himself.
- Supabase changes are add-only and shown to the user first; the user clicks Run.
- Run `flutter analyze` and `flutter test` after every change.
- Update `_SESSION_SUMMARY.md` after each task.
