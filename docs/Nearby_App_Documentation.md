# Nearby — Location-Aware Shared Reminder & Errand App

**Status:** Side project concept, not tied to thesis work
**Last updated:** July 2026

---

## 1. One-Line Pitch

A location-aware reminder app where zones don't just notify you, they unlock shared errand lists that friends can claim and settle inside the app.

## 2. Problem It Solves

Two annoyances that nobody's tied together yet.

First, generic reminders show up whether or not you're actually in a position to act on them. A reminder to "buy milk" at 3pm is useless if you're not near a store at 3pm.

Second, shared errands (parents asking you to grab something, roommates splitting a grocery run) rely on WhatsApp chaos and manual repayment tracking. Someone buys something, someone else has to remember to pay them back, and there's rarely a clean record of who bought what.

Nearby ties both problems to the same trigger: physical presence at a place. A zone shows only what's relevant while you're there, and if that zone has a shared list attached, whoever's actually standing in the store can claim and settle it on the spot.

## 3. Competitive Landscape

The zone-based reminder idea on its own is not new. Apps already doing this well include:

- **Trigger** — custom geofence zones with enter/exit/dwell actions
- **GeoNote** — on-device geofencing, privacy-first, battery-efficient
- **RemindMeWhere / GeoAlert** — similar geofence-triggered reminders
- Apple's own Reminders app has native location triggers built in

Shared shopping/expense-splitting also exists separately:

- **SplitCart** — shared grocery list with built-in bill splitting, tracks who owes whom
- **AnyList / Listonic** — collaborative shopping lists, real-time sync across devices

**The gap:** nobody combines the two. Nothing ties a live geofence zone to a claimable, splittable shared list that only becomes actionable when you're physically present. That's the actual differentiator for Nearby, not the geofencing itself.

## 4. Core Concept

- Users define **zones** by dropping pins on a map (Home, Uni, Gym, Mamak, etc.)
- Each zone holds personal reminders, notes, or goals
- Zones trigger on **enter**, **exit**, or **dwell**
- Zones can be shared with friends. A shared zone can have a **shared list** attached
- Anyone with access to a shared list can claim items, mark them bought, upload a receipt, and settle payment manually through their own banking app (QR/bank details shown in-app, marked settled manually, no processing handled by Nearby itself)

## 5. Build Phases

### Phase 1 — Personal Zone Engine
- Drop pins, name zones, set radius
- Attach reminders per zone
- Enter / exit / dwell triggers
- Single-user only, no sharing yet
- Offline-first: works with local storage, syncs to backend when online
- Reliability testing specifically on stock Android **and** OEM-heavy devices (Xiaomi/Oppo), since background throttling is the real technical risk here, not the map or UI

### Phase 2 — Friends and Shared Lists
- Add friends (persistent connection, one-time add, not per-zone)
- Attach a shared list to a zone
- Share a list with specific friends, choosing a permission tier per friend:
  - **view** — sees live updates, can't claim
  - **claim** — can claim items and mark bought
- No payment flow yet, just claim/bought states

### Phase 3 — Proof and Settlement
- Receipt photo upload on claim
- Buyer's QR/bank details surface for repayment
- Payer settles through their own banking app, marks it paid manually inside Nearby (no in-app payment processing, avoids compliance overhead)
- Optional WhatsApp export of the receipt as an external record

## 6. Tech Stack

| Layer | Choice | Why |
|---|---|---|
| Frontend | Flutter | Single codebase for iOS and Android |
| Maps | `google_maps_flutter` or `flutter_map` | Cross-platform pin-dropping UI |
| Geofencing | `flutter_background_geolocation` | Wraps native OS-managed geofencing (Android `GeofencingClient`, iOS `CLLocationManager` region monitoring), handles OEM battery throttling better than manual polling. Free tier limited, check pricing before committing |
| Backend | Supabase | Postgres + PostGIS for geospatial zone data, Realtime for live list updates, built-in auth, Storage for receipt photos, row-level security for controlling who sees whose receipts |

**Why Supabase over Laravel for this project:**
- PostGIS is the right tool for zone/location queries, not just convenient
- Realtime subscriptions fit the "friend claims an item, list updates live for everyone" flow without hand-rolling WebSockets
- Less backend boilerplate to maintain, which matters more than fine-grained control for a side project
- Free tier is generous enough for personal use with a handful of testers
- Caveat: free tier pauses projects after a week of inactivity — just needs a manual restart, not a blocker

## 7. Database Schema (Supabase / Postgres + PostGIS)

**zones**
- id, owner_id (fk → auth.users), name, location (geography point), radius_meters, trigger_type (enter/exit/dwell), created_at

**zone_reminders**
- id, zone_id (fk), title, body, active, created_at

**friends**
- id, user_id, friend_id, requested_by, status (pending/accepted), created_at
- persistent one-time connection, not tied to a specific zone
- `user_id`/`friend_id` form an unordered pair (DB-enforced, one row per relationship regardless of who sent it); `requested_by` records who initiated the request, needed to show "sent" vs "received" in the pending list
- self-friending and duplicate/reciprocal rows blocked at the DB level (`no_self_friend` and `unique_pair` constraints)

**shared_lists**
- id, zone_id (fk), title, is_shared (bool), created_at

**list_access**
- id, list_id (fk), friend_id (fk), permission (view/claim), created_at
- editable after creation — permission tier can be bumped up or down anytime from list share settings
- note: the zone/list owner always has full read/write access to their own list regardless of `list_access` rows — `list_access` grants access to others, it isn't the only path to write access for the owner

**list_items**
- id, list_id (fk), name, quantity, notes, status (open/claimed/bought/settled), claimed_by (fk, nullable), created_at

**receipts**
- id, list_item_id (fk), uploaded_by (fk), image_url (Supabase storage path), amount, created_at

**payment_records**
- id, receipt_id (fk), payer_id, payee_id, method (qr/bank), settled (bool), settled_at

Note: the actual enter/exit/dwell detection happens on-device via the geofencing plugin, not through a PostGIS query. PostGIS matters for things like "show zones near my current location" or validating zone overlap, not the real-time trigger itself.

## 8. The Location Reliability Problem

This is the single biggest technical risk in the whole project, bigger than anything backend-related.

**Why it happens:** Android OEM skins (MIUI on Xiaomi, ColorOS on Oppo, FuntouchOS on Vivo, Samsung to a lesser degree) run aggressive battery managers that kill background processes the stock OS would otherwise allow to keep running. A geofence callback can fail to fire, or fire several minutes late, because the OEM decided the app was "not in use."

This isn't a bug fixable purely with better Flutter code — it's an OS-level permissions and battery-settings problem.

**Mitigation approach:**

1. **Use native OS-managed geofencing, not manual polling.** Android's `GeofencingClient` and iOS's `CLLocationManager` region monitoring are designed for exactly this use case — the OS decides when to wake the app using cell tower and wifi triangulation before falling back to GPS, which is more battery-efficient and harder for OEMs to kill than an app-driven polling loop. `flutter_background_geolocation` wraps both properly.

2. **Explicit onboarding for battery optimization / autostart permissions.** On first launch, walk the user through disabling battery optimization and enabling autostart for the app — settings buried inside MIUI/ColorOS/FuntouchOS that most users won't find on their own. Deep-link directly to the relevant settings page rather than describing where to find it.

3. **Design the UX for delayed triggers, not just missed ones.** Even with everything configured correctly, OEM throttling can delay a trigger by a few minutes. Reminders should be designed assuming they might fire a few minutes after entry, not instantly. Avoid building any feature that depends on split-second accuracy.

4. **Optional foreground service for high-priority zones.** For zones a user marks as important, allow an opt-in foreground service with a small persistent notification. Android is much less likely to kill a foreground service, at the cost of higher battery use and visible "running" status. Opt-in only, never default.

5. **Device-specific testing.** Budget testing time specifically on Xiaomi and Oppo devices, not just a personal daily driver, since OEM behavior varies significantly by brand and even by software version.

**Honest caveat:** even with all of the above, 100% reliability isn't realistic — none of the existing geofencing apps researched (GeoNote, Trigger) promise instant triggers on every device either. The realistic goal is "reliable enough that users don't stop trusting the app," not perfection.

## 9. Onboarding Flow for Permissions (to avoid feeling naggy)

Suggested flow, to be refined further once UI work starts:

1. First launch — explain in plain language why background location is needed ("so reminders show up when you arrive, without you opening the app")
2. Request location permission at the point the user creates their first zone, not on app launch
3. After first zone is created, prompt for battery optimization exemption with a short explanation and a direct deep link to the relevant settings screen
4. Skip autostart / foreground service prompts entirely until Phase 2 sharing is in use — no reason to front-load every permission ask before the user has any real reason to care yet

## 10. Open Decisions

- Whether to add an "edit" permission tier above claim, letting some friends add new items to a shared list themselves (currently claim is the ceiling)
- Exact wording/flow for the battery optimization onboarding screen, to be designed once UI work starts
- Whether foreground service opt-in should be per-zone or a global app setting

## 11. Detailed Competitor Research (Round 2)

A deeper pass to confirm whether the exact combination — geofence-triggered visibility plus a claimable, splittable shared list — already exists anywhere. Short answer: no, but a few apps get close on one half of it.

**Closest match on the zone-switching mechanic:** "Grocery - Smart Shopping List" (iOS). It lets a user assign a store per geofence and auto-switches which list is active based on location, plus supports shared lists through iCloud Reminders. This is single-user list-switching though — the list itself isn't claimable or split between people, it's just visibility switching for one person's own shopping.

**Retail/marketing geofencing category:** a large, separate space entirely — brands like Meijer and Home Depot use in-store geofencing to reorder a shopping list by store layout or switch the app into an in-store mode with a product locator. Useful precedent for "in-store detection changes what's shown," but it's business-to-consumer, not peer-to-peer, and has no claim or settlement concept at all.

**Bill-splitting category:** Splitwise, Settle Up, Revolut Split. All handle group expense math and repayment reminders well, but none are location-aware — an expense has to be entered manually, it's never triggered by presence at a location.

**Conclusion:** the zone-reminder category and the split-expense category are both mature and crowded on their own. Nothing found combines them — a shared list that only becomes actionable (claimable, settleable) because someone is physically standing in the right zone. This remains the actual gap the project is aimed at, and it's a workflow gap rather than a technical one, which is realistic to claim as a side project.

## 12. Known Risks Summary

- Background location throttling on Android OEMs — primary risk, addressed above
- Payment handling stays manual by design (QR/bank display, user marks settled) to avoid compliance overhead of processing real transactions
- Supabase free tier pauses after a week of inactivity — minor inconvenience, not a blocker
