#!/usr/bin/env bash
# Nearby geofence simulation for the Android emulator.
# Drives the emulator's GPS into saved places and checks that Android fires
# the geofence and Nearby shows a notification. Prints PASS/FAIL + latency.
#
# Usage:  bash tools/geofence_test.sh            (both tests)
#         bash tools/geofence_test.sh <name>     (one test, matches place name)
# Needs: emulator running, Nearby installed and signed in.

set -u
PKG=com.syaheer.nearby
ADB="${ADB:-$(command -v adb || echo "$HOME/Library/Android/sdk/platform-tools/adb")}"
[ -x "$ADB" ] || { echo "adb not found. Set ADB=/path/to/adb"; exit 1; }

# Places to test come from tools/geofence_places.txt (gitignored, it holds
# real locations). Format: name|lat|lng|radius, see geofence_places.example.txt.
PLACES_FILE="$(dirname "$0")/geofence_places.txt"
[ -f "$PLACES_FILE" ] || PLACES_FILE="$(dirname "$0")/geofence_places.example.txt"
TESTS=()
while IFS= read -r line; do
  case "$line" in ''|'#'*) continue ;; esac
  TESTS+=("$line")
done < "$PLACES_FILE"
ONLY="${1:-}"

say() { printf '\033[1m%s\033[0m\n' "$*"; }
fix() { "$ADB" emu geo fix "$2" "$1" >/dev/null; }   # lat lng -> adb wants lng lat

dist_m() { # lat1 lng1 lat2 lng2
  awk -v a="$1" -v b="$2" -v c="$3" -v d="$4" 'BEGIN{
    r=6371000; p=atan2(0,-1)/180;
    dl=(c-a)*p; dn=(d-b)*p;
    h=sin(dl/2)^2+cos(a*p)*cos(c*p)*sin(dn/2)^2;
    printf "%d", 2*r*atan2(sqrt(h),sqrt(1-h)) }'
}

notif_count() {
  "$ADB" shell dumpsys notification --noredact 2>/dev/null | grep -c "pkg=$PKG" || true
}

say "== Setup"
"$ADB" wait-for-device
"$ADB" shell pm list packages | grep -q "$PKG" || { echo "Nearby is not installed on the emulator."; exit 1; }
for perm in ACCESS_FINE_LOCATION ACCESS_COARSE_LOCATION ACCESS_BACKGROUND_LOCATION POST_NOTIFICATIONS; do
  "$ADB" shell pm grant "$PKG" "android.permission.$perm" 2>/dev/null || true
done
"$ADB" shell cmd location set-location-enabled true 2>/dev/null || true
echo "Permissions granted, location on."

# Google Maps keeps the emulator's location provider active, which the
# emulator needs before it will evaluate geofences.
"$ADB" shell monkey -p com.google.android.apps.maps -c android.intent.category.LAUNCHER 1 >/dev/null 2>&1 \
  && echo "Opened Google Maps (keeps location active)." \
  || echo "Google Maps not found; geofences may be slow on this image."
sleep 4

# Open Nearby so it syncs places from Supabase and registers the geofences,
# then send it to the background like a normal user would.
"$ADB" shell monkey -p "$PKG" -c android.intent.category.LAUNCHER 1 >/dev/null 2>&1
echo "Opened Nearby to register geofences..."
sleep 10
"$ADB" shell input keyevent KEYCODE_HOME
echo "Nearby is in the background now."

# Bring Maps back to the front. Android only updates the fused location (and
# so only checks geofences) quickly while some app is actively asking for
# location. Nearby stays in the background, which is the case we care about.
"$ADB" shell monkey -p com.google.android.apps.maps -c android.intent.category.LAUNCHER 1 >/dev/null 2>&1
echo "Maps in front to keep GPS updates flowing."

LOGDIR="$(dirname "$0")/geofence_logs"
mkdir -p "$LOGDIR"
say ""
say "== Diagnostics"
echo "Registered fences saved by native_geofence (debug build only):"
FENCES=$("$ADB" shell "run-as $PKG sh -c 'cat shared_prefs/*.xml'" 2>/dev/null \
  | grep -oE '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}' | sort -u)
if [ -n "$FENCES" ]; then printf '%s\n' "$FENCES" | sed 's/^/  /'; else echo "  none found"; fi
"$ADB" shell dumpsys activity service com.google.android.gms/com.google.android.location.internal.GoogleLocationManagerService \
  > "$LOGDIR/gms_location.txt" 2>&1
echo "GMS geofence lines: $(grep -ci geofence "$LOGDIR/gms_location.txt")  (full dump in tools/geofence_logs/gms_location.txt)"

run_test() {
  local name="$1" lat="$2" lng="$3" radius="$4"
  say ""
  say "== Test: arrive at \"$name\" (radius ${radius} m)"

  # Start ~2 km south-east, outside every saved place.
  local slat slng
  slat=$(awk -v x="$lat" 'BEGIN{printf "%.6f", x-0.014}')
  slng=$(awk -v x="$lng" 'BEGIN{printf "%.6f", x+0.012}')
  echo "Parking outside at $slat,$slng ($(dist_m "$slat" "$slng" "$lat" "$lng") m away)..."
  for _ in 1 2 3 4 5 6; do fix "$slat" "$slng"; sleep 5; done

  "$ADB" logcat -c
  local before; before=$(notif_count)

  # Drive in: 24 steps, one GPS fix every 5 s (~2 minutes, like a slow car).
  local steps=24 entered_at="" i plat plng d
  echo "Driving in..."
  for i in $(seq 1 $steps); do
    plat=$(awk -v s="$slat" -v e="$lat" -v i="$i" -v n="$steps" 'BEGIN{printf "%.6f", s+(e-s)*i/n}')
    plng=$(awk -v s="$slng" -v e="$lng" -v i="$i" -v n="$steps" 'BEGIN{printf "%.6f", s+(e-s)*i/n}')
    fix "$plat" "$plng"
    d=$(dist_m "$plat" "$plng" "$lat" "$lng")
    if [ -z "$entered_at" ] && [ "$d" -le "$radius" ]; then
      entered_at=$(date +%s)
      echo "  step $i: ${d} m from centre  <- crossed into the place"
    fi
    sleep 5
  done
  [ -n "$entered_at" ] || entered_at=$(date +%s)

  # Stay inside and wait for the geofence (up to 3 minutes).
  echo "Inside. Waiting up to 3 min for Android..."
  local fired="" notified="" now waited
  for _ in $(seq 1 36); do
    fix "$lat" "$lng"
    if [ -z "$fired" ] && "$ADB" logcat -d -s flutter 2>/dev/null | grep -q "NEARBY_GEOFENCE.*zone=\"$name\""; then
      fired=$(( $(date +%s) - entered_at ))
    fi
    if [ -z "$notified" ] && [ "$(notif_count)" -gt "$before" ]; then
      notified=$(( $(date +%s) - entered_at ))
    fi
    [ -n "$fired" ] && [ -n "$notified" ] && break
    sleep 5
  done

  local slug; slug=$(printf '%s' "$name" | tr -c 'A-Za-z0-9' '_')
  "$ADB" logcat -d > "$LOGDIR/logcat_$slug.txt" 2>&1
  echo "  logcat saved: tools/geofence_logs/logcat_$slug.txt"
  grep -iE "geofenc|NEARBY_|flutter.*(error|exception)|FATAL" "$LOGDIR/logcat_$slug.txt" | tail -15 | sed 's/^/    /'

  local line
  line=$("$ADB" logcat -d -s flutter 2>/dev/null | grep "NEARBY_GEOFENCE.*zone=\"$name\"" | tail -1)
  if [ -n "$fired" ]; then
    echo "  geofence fired ${fired}s after entering   $line"
  else
    echo "  geofence did NOT fire within 3 min"
  fi
  if [ -n "$notified" ]; then
    echo "  notification shown ${notified}s after entering"
  else
    echo "  no notification seen"
  fi
  if [ -n "$fired" ] && [ -n "$notified" ]; then
    say "  PASS"
  else
    say "  FAIL"
  fi
}

for t in "${TESTS[@]}"; do
  IFS='|' read -r n la lo r <<<"$t"
  if [ -n "$ONLY" ] && ! printf '%s' "$n" | grep -qi "$ONLY"; then continue; fi
  run_test "$n" "$la" "$lo" "$r"
done

say ""
say "== Done. Open each place in Nearby: History should list the arrivals."
