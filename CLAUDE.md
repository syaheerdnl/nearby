# CLAUDE.md — Build Instructions for Nearby

This file is the working brief for Claude Code. Read this in full before writing any code. Follow the build order strictly — do not jump ahead to Phase 2 or 3 features until Phase 1 is confirmed working.

---

## 1. Architecture Overview

Nearby is a Flutter mobile app backed by Supabase. Three layers, kept deliberately separate:

```
┌─────────────────────────────────────────────┐
│              Flutter App (iOS/Android)        │
│  ┌───────────────┐   ┌──────────────────────┐ │
│  │  UI Layer      │   │  State Management     │ │
│  │  (screens,     │   │  (Provider)            │ │
│  │  widgets)      │   │                        │ │
│  └───────────────┘   └──────────────────────┘ │
│  ┌───────────────────────────────────────────┐ │
│  │  Geofencing Layer                          │ │
│  │  native_geofence (OS geofencing APIs)      │ │
│  │  — runs independently of app lifecycle     │ │
│  │  — fires local events on enter/exit/dwell  │ │
│  └───────────────────────────────────────────┘ │
│  ┌───────────────────────────────────────────┐ │
│  │  Local Storage (offline-first)             │ │
│  │  sqflite or Hive — zones + reminders cached│ │
│  │  locally, synced to Supabase when online   │ │
│  └───────────────────────────────────────────┘ │
│  ┌───────────────────────────────────────────┐ │
│  │  Supabase Client (supabase_flutter)        │ │
│  │  — auth, realtime, storage, Postgres calls │ │
│  └───────────────────────────────────────────┘ │
└─────────────────────────────────────────────┘
                      │
                      ▼
┌─────────────────────────────────────────────┐
│                  Supabase Backend             │
│  ┌───────────────┐  ┌──────────────────────┐  │
│  │  Postgres +    │  │  Realtime             │  │
│  │  PostGIS       │  │  (list_items changes) │  │
│  └───────────────┘  └──────────────────────┘  │
│  ┌───────────────┐  ┌──────────────────────┐  │
│  │  Auth          │  │  Storage              │  │
│  │  (email/magic  │  │  (receipt photos,     │  │
│  │  link)         │  │  row-level security)  │  │
│  └───────────────┘  └──────────────────────┘  │
└─────────────────────────────────────────────┘
```

**Key architectural rule:** the geofencing layer must never depend on the app being open or on a live network connection to *detect* a trigger. Detection happens on-device via native OS geofencing APIs (wrapped by `native_geofence`). Network/Supabase calls only happen after detection, to sync state or fetch/display the relevant zone's data. If offline, queue the sync and retry when connectivity returns.

Do not build a custom polling loop that checks location every N seconds in Dart code. Use the plugin's native geofence registration so the OS handles wake-ups.

---

## 2. Tech Stack (fixed, do not substitute without asking)

| Layer | Package/Tool |
|---|---|
| Framework | Flutter (stable channel) |
| State management | `provider` |
| Local storage | `sqflite` (relational, matches Supabase schema shape) |
| Geofencing | `native_geofence` (OS geofencing: GeofencingClient on Android, CLLocationManager on iOS). Replaced `flutter_background_geolocation`, which needs a paid licence for Android release builds. |
| Maps | `flutter_map` + OpenStreetMap tiles. Replaced `google_maps_flutter`, which needs a billing-enabled API key. |
| Backend | Supabase (`supabase_flutter` package) |
| Auth | Supabase Auth — email/password to start, magic link optional later |

If a package above turns out to be unworkable for a specific reason, stop and flag it rather than silently swapping to an alternative.

---

## 3. Project Structure

```
lib/
  main.dart
  app.dart                     # MaterialApp, routes, providers wiring

  core/
    supabase_client.dart       # single Supabase client instance
    constants.dart             # radius defaults, trigger type enums
    theme.dart

  models/
    zone.dart
    zone_reminder.dart
    friend.dart
    shared_list.dart
    list_access.dart
    list_item.dart
    receipt.dart
    payment_record.dart

  services/
    geofence_service.dart      # wraps native_geofence
    local_db_service.dart      # sqflite CRUD
    sync_service.dart          # reconciles local db <-> Supabase
    zone_repository.dart       # exposes zone CRUD to UI, hides local/remote split
    list_repository.dart
    friend_repository.dart

  providers/
    zone_provider.dart
    list_provider.dart
    friend_provider.dart
    auth_provider.dart

  screens/
    onboarding/
      permission_intro_screen.dart
      battery_optimization_screen.dart
    zones/
      zone_map_screen.dart
      zone_detail_screen.dart
      zone_create_screen.dart
    lists/
      shared_list_screen.dart
      list_item_detail_screen.dart
    friends/
      friends_screen.dart
      add_friend_screen.dart
    settlement/
      receipt_upload_screen.dart
      payment_confirm_screen.dart

  widgets/
    zone_pin_marker.dart
    reminder_tile.dart
    claim_button.dart
    permission_tier_selector.dart
```

Keep repositories as the only layer that talks to both `local_db_service` and Supabase directly. Screens and providers should never call Supabase or sqflite directly — always go through a repository. This makes Phase 1's offline-first behavior swappable later without rewriting UI code.

---

## 4. Database Schema (Supabase / Postgres + PostGIS)

Create these tables in this order, since later ones reference earlier ones via foreign key.

```sql
-- enable PostGIS
create extension if not exists postgis;

create table zones (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid references auth.users not null,
  name text not null,
  location geography(point, 4326) not null,
  radius_meters int not null default 150,
  trigger_type text not null check (trigger_type in ('enter', 'exit', 'dwell')),
  created_at timestamptz default now()
);

create table zone_reminders (
  id uuid primary key default gen_random_uuid(),
  zone_id uuid references zones on delete cascade not null,
  title text not null,
  body text,
  active boolean default true,
  created_at timestamptz default now()
);

-- profiles table needed for usernames (auth.users has no username field by default)
create table profiles (
  id uuid primary key references auth.users on delete cascade,
  username text unique not null,
  created_at timestamptz default now()
);

create table friends (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references auth.users not null,
  friend_id uuid references auth.users not null,
  requested_by uuid references auth.users not null,
  status text not null check (status in ('pending', 'accepted')) default 'pending',
  created_at timestamptz default now(),
  constraint no_self_friend check (user_id <> friend_id),
  constraint unique_pair unique (least(user_id, friend_id), greatest(user_id, friend_id))
);

create table shared_lists (
  id uuid primary key default gen_random_uuid(),
  zone_id uuid references zones on delete cascade not null,
  title text not null,
  is_shared boolean default false,
  created_at timestamptz default now()
);

create table list_access (
  id uuid primary key default gen_random_uuid(),
  list_id uuid references shared_lists on delete cascade not null,
  friend_id uuid references auth.users not null,
  permission text not null check (permission in ('view', 'claim')) default 'view',
  created_at timestamptz default now()
);

create table list_items (
  id uuid primary key default gen_random_uuid(),
  list_id uuid references shared_lists on delete cascade not null,
  name text not null,
  quantity int default 1,
  notes text,
  status text not null check (status in ('open', 'claimed', 'bought', 'settled')) default 'open',
  claimed_by uuid references auth.users,
  created_at timestamptz default now()
);

create table receipts (
  id uuid primary key default gen_random_uuid(),
  list_item_id uuid references list_items on delete cascade not null,
  uploaded_by uuid references auth.users not null,
  image_url text not null,
  amount numeric(10,2),
  created_at timestamptz default now()
);

create table payment_records (
  id uuid primary key default gen_random_uuid(),
  receipt_id uuid references receipts on delete cascade not null,
  payer_id uuid references auth.users not null,
  payee_id uuid references auth.users not null,
  method text check (method in ('qr', 'bank')),
  settled boolean default false,
  settled_at timestamptz
);
```

Enable row-level security on every table before writing any client code against them. At minimum:
- `profiles`: readable by anyone (usernames need to be searchable to add friends), writable only by the owning user
- `zones`, `zone_reminders`: owner can read/write their own rows only
- `shared_lists`, `list_items`: readable by owner + anyone with a matching `list_access` row; writable if the requester is the zone owner (via `shared_lists.zone_id -> zones.owner_id`), **or** has a matching `list_access` row with `permission = 'claim'`. The owner check is not optional — without it, the person who created the list can be locked out of editing their own items.
- `receipts`: readable by anyone with access to the parent list; insertable by the claimer
- Do not skip RLS "to move faster" — this app handles other people's location and payment-adjacent data.

Example policy for `list_items` showing the owner-or-claim-access pattern (write similar owner-aware policies for `shared_lists`):

```sql
create policy "list_items write access"
on list_items for update using (
  exists (
    select 1 from shared_lists sl
    join zones z on z.id = sl.zone_id
    where sl.id = list_items.list_id
    and z.owner_id = auth.uid()
  )
  or
  exists (
    select 1 from list_access la
    where la.list_id = list_items.list_id
    and la.friend_id = auth.uid()
    and la.permission = 'claim'
  )
);
```

---

## 5a. Secrets Handling

Use `--dart-define-from-file` with a gitignored `config.json` (or `config.dev.json` / `config.prod.json` if you need separate environments) holding `SUPABASE_URL` and `SUPABASE_ANON_KEY` (no maps key needed with OpenStreetMap). No `flutter_dotenv` dependency needed. Add the config file(s) to `.gitignore` immediately when the repo is created — before the first commit, not after.

---

## 5. Build Order — Follow This Exactly

### Phase 1 — Personal Zone Engine (build and fully test before touching Phase 2)

1. Set up Flutter project, add dependencies, wire up Supabase client and auth (email/password).
2. Build local sqflite schema mirroring `zones` and `zone_reminders`.
3. Build the map screen: drop a pin, name it, set radius, choose trigger type. Save locally first, sync to Supabase in background.
4. Integrate `native_geofence`, register a geofence per saved zone.
5. On trigger fire, show a local notification with that zone's active reminders.
6. Build the permission onboarding flow (see section 6 below) — do this before asking for location permission anywhere else in the app.
7. Test on the iQOO (Vivo, OriginOS/FuntouchOS — aggressive background killing). Confirm enter/exit fires within a few minutes on both. Log actual trigger latency, don't just eyeball it.

Do not proceed to Phase 2 until step 7 passes on the iQOO.

### Phase 2 — Friends and Shared Lists

1. Build `friends` add flow. Decision: **username-based, with a shareable invite link** — not email, not QR code.
   - On signup, user picks a unique username (stored in `profiles`).
   - "Add friend" screen: search by username, sends a request row to `friends` (status = 'pending', `requested_by` = sender's id). `user_id`/`friend_id` are stored as an unordered pair (enforced by the `unique_pair` constraint), so `requested_by` is the only column that tells you who initiated it — use it to split the pending list into "sent" vs "received" in the UI.
   - Also generate a shareable invite link (deep link, e.g. `nearby://invite/{username}` or a web fallback URL) that can be sent via WhatsApp. Tapping it opens the app to a pre-filled "send friend request to {username}" screen, or to the app store if not installed.
   - Recipient accepts/declines from a pending requests list; on accept, flip status to 'accepted'. This connection is permanent and independent of any zone.
   - Skip QR-code adding — that pattern fits in-person "add nearby" flows, not this app's use case of adding friends ahead of time.
2. Add `shared_lists` and `list_access` — UI to toggle a list to shared, pick friends, assign permission tier (view/claim) per friend.
3. Wire Supabase Realtime on `list_items` so claim/status changes update live for everyone with access.
4. Build claim flow: tap item → claim → mark bought. No receipts yet.
5. Make permission tier editable after the fact from list settings, not just at share time.

### Phase 3 — Proof and Settlement

1. Add receipt upload (image picker → Supabase Storage → `receipts` row).
2. Display buyer's static QR/bank details for repayment (stored on user profile, entered manually by each user in settings — do not attempt to integrate a live payment API).
3. Build manual "mark as settled" action, writes to `payment_records`.
4. Optional: WhatsApp share intent to export a receipt image + amount as an external record.

---

## 6. Permission Onboarding Flow (Phase 1, build before general location prompts)

1. First launch: plain-language explainer screen — why background location matters, no permission prompt yet.
2. Location permission requested only when the user creates their first zone, not on app launch.
3. Immediately after first zone is saved: battery optimization exemption screen, short explanation + deep link to the OEM-specific settings page. Detect OEM via `device_info_plus` and adjust the deep link/instructions (MIUI, ColorOS, FuntouchOS, stock differ in settings paths).
4. Do not prompt for autostart or foreground service permissions until Phase 2 is reached — no reason to front-load permission asks before there's a real reason for the user to grant them.

---

## 7. Coding Conventions

- Null-safety on, no `late` fields unless truly unavoidable — prefer explicit nullable types and guard clauses.
- Repositories return domain models (`Zone`, `ListItem`, etc.), never raw Supabase JSON maps, to the provider/UI layers.
- All Supabase table names and column names in Dart code should match the schema in section 4 exactly — no aliasing.
- Every screen that touches location or payment data needs a loading and an error state, not just a happy path. This app deals with background triggers that can legitimately fail or arrive late — the UI needs to communicate that, not silently do nothing.
- Write a short comment above any geofencing-related code explaining the OEM-specific consideration if there is one — this codebase will need revisiting when a new OEM behavior surfaces.

---

## 8. What Not To Build

- No custom manual location-polling loop — use native geofencing via the plugin.
- No in-app payment processing of any kind — QR/bank detail display and manual settlement only.
- No global permission-tier setting — permissions are always per-friend, per-list.
- No skipping RLS setup "for now" — set it up correctly from the first table.

---

## 9. Definition of Done for Phase 1

Phase 1 is complete when: a user can create at least 3 zones, attach reminders to each, and reliably receive a notification within a few minutes of physically entering or leaving each zone, tested on the iQOO (Vivo, OEM-heavy), with the app fully closed (not just backgrounded) during the test. If this isn't reliable, stop and fix it before adding any Phase 2 feature — the whole app is built on this working.

---

## 10. Monetization — Deferred, Not In Scope Yet

**Do not build anything in this section during Phase 1, 2, or 3.** This is a product note for later, after the core app works and has real users (friends actually using it daily, not just solo testing). Recorded here so the idea isn't lost, not as a task list.

Rough direction, for whenever that time comes:
- Free tier: limited zones/friends (e.g. 3 each), core reminders unchanged in reliability — never paywall basic trigger reliability itself, that's a trust issue not a feature.
- Paid tier ideas: unlimited zones/friends, receipt OCR (auto-extract amount from photo instead of manual entry), simple spending/settlement insights per friend, opt-in "high priority" foreground-service zones, smart zone suggestions from repeated location visits.
- Pricing shape to consider later: one-time unlock or annual price over monthly, and possibly a group/household plan rather than strictly per-user.
- When actually implementing: use RevenueCat rather than hand-building App Store/Play Store billing and receipt validation.
