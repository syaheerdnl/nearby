# Nearby — Handover (2026-10-13)

TL;DR: Phase 1 + Phase 2 (friends, shared lists) are built and mostly tested on the emulator and the iQOO. The last change (shared pins on the map) is written but not built yet, and one Supabase hardening migration (005) needs its result confirmed.

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
| Shared lists (claim / bought, live updates, share View/Can buy, friend alerts) | Built + committed (e260e2d). Full 2-phone test not reported yet |
| Shared places as pins on friend's Map | Written, NOT built yet (uncommitted: `lib/widgets/shared_pin_marker.dart`, `lib/screens/zones/zone_map_screen.dart`) |
| Phase 3 (receipts, payments) | Not started. Empty placeholder files exist (`settlement/*`, `receipt.dart`, `payment_record.dart`, `list_provider.dart`, `add_friend_screen.dart`, `list_item_detail_screen.dart`, `claim_button.dart`, `permission_tier_selector.dart`) |

## 2. Do these first

1. **Confirm migration 005.** `supabase/005_lists_hardening.sql` was started in the Supabase SQL editor but the tab hung, so the result is unknown. Check with:
   ```sql
   select indexname from pg_indexes where indexname = 'shared_lists_zone_uidx';
   select proname from pg_proc where proname in ('is_my_friend','are_friends');
   ```
   Expect the index and `is_my_friend` only (no `are_friends`). If not, re-run 005 (it's written to be re-runnable).
2. Build, test the shared pins (friend account → Map tab), then commit.
3. Full 2-phone shared-list test (see section 6).

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
| 005_lists_hardening.sql (status-only accept, unfriend revokes access, item column grants + claim guard, `is_my_friend`, one list per zone) | **Unconfirmed** — see section 2 |

RLS helpers are `SECURITY DEFINER` (owns_zone, owns_list, list_permission, zone_shared_with_me, is_my_friend) to avoid policy recursion between zones and shared_lists.

## 6. Test checklist still open

- [ ] Shared pins visible on friend's Map; tap opens list
- [ ] Emulator (owner) creates list on a place, adds "Beras", "Telur x30", shares with test account as Can buy
- [ ] iQOO (test account): Home shows "Shared with you"; claim item → owner sees "<name> buying" live
- [ ] Friend arrival alert lists open items (iQOO alone on adb: `bash tools/geofence_test.sh home`)
- [ ] Unfriend → friend loses the list (needs 005)
- [ ] Real-world iQOO walk to a shared place

## 7. Known limits / decisions

- Friend's alert shows open items as of their last app refresh (cached locally for offline alerts).
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
