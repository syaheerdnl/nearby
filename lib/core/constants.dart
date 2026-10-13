/// Build-time config, passed with `--dart-define-from-file=config.json`.
class Env {
  const Env._();

  static const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

  static bool get isConfigured =>
      supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty;

  /// Optional. With a key, map tiles, search and routing use Geoapify
  /// (free plan allows commercial use). Without one, the app falls back to
  /// the public OSM / Photon / OSRM demo servers, fine for development only.
  static const geoapifyKey = String.fromEnvironment('GEOAPIFY_KEY');
  static bool get useGeoapify => geoapifyKey.isNotEmpty;
}

class AppConstants {
  const AppConstants._();

  /// Android geofencing is unreliable below ~100 m, so the UI never goes lower.
  static const int minRadiusMeters = 100;
  static const int maxRadiusMeters = 1000;
  static const int defaultRadiusMeters = 150;

  /// How long the user must stay inside before a "dwell" zone fires.
  static const Duration dwellDelay = Duration(minutes: 5);

  static const String notificationChannelId = 'zone_reminders';
  static const String notificationChannelName = 'Zone reminders';

  /// Used before we know where the user is (Melaka).
  static const double fallbackLatitude = 2.1896;
  static const double fallbackLongitude = 102.2501;

  /// Raster tiles. Geoapify's osm-carto looks like the standard OSM map and
  /// only needs the Geoapify + OSM credits (no OpenMapTiles credit).
  static String get tileUrl => Env.useGeoapify
      ? 'https://maps.geoapify.com/v1/tile/osm-carto/{z}/{x}/{y}@2x.png'
          '?apiKey=${Env.geoapifyKey}'
      : 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';

  /// Credit line shown next to every map. Geoapify's free plan requires it.
  static String get mapAttribution => Env.useGeoapify
      ? 'Powered by Geoapify · © OpenStreetMap contributors'
      : '© OpenStreetMap contributors';
  static const String userAgentPackageName = 'com.syaheer.nearby';

  /// Sent to the search/routing servers, which ask apps to identify themselves.
  static const String httpUserAgent = 'Nearby/0.1 (com.syaheer.nearby)';

  /// Geoapify can't restrict a key to an Android app, only to HTTP referrers,
  /// origins or IPs. The key is restricted to this referrer in MyProjects, so
  /// it stops casual reuse (other websites, quick scripts). Not real security:
  /// the header ships in the APK.
  static const String geoapifyReferer = 'https://nearby.syaheerdaniel.dev/';

  /// Headers for every search, routing and tile request.
  static Map<String, String> get httpHeaders => {
        'User-Agent': httpUserAgent,
        if (Env.useGeoapify) 'Referer': geoapifyReferer,
      };
}

/// Matches `zones.trigger_type` in the database.
enum TriggerType {
  enter,
  exit,
  dwell;

  String get label => switch (this) {
        TriggerType.enter => 'When I arrive',
        TriggerType.exit => 'When I leave',
        TriggerType.dwell => 'After I stay a while',
      };

  /// Short form for list rows: "On arrival", "On leaving", "After 5 min".
  String get short => switch (this) {
        TriggerType.enter => 'On arrival',
        TriggerType.exit => 'On leaving',
        TriggerType.dwell => 'After ${AppConstants.dwellDelay.inMinutes} min',
      };

  String get segment => switch (this) {
        TriggerType.enter => 'Arrive',
        TriggerType.exit => 'Leave',
        TriggerType.dwell => 'Stay ${AppConstants.dwellDelay.inMinutes} min',
      };

  static TriggerType fromName(String value) => TriggerType.values.firstWhere(
        (t) => t.name == value,
        orElse: () => TriggerType.enter,
      );
}

/// Local-only column that tracks what still needs pushing to Supabase.
enum SyncStatus {
  synced('synced'),
  pendingUpsert('pending_upsert'),
  pendingDelete('pending_delete');

  const SyncStatus(this.value);
  final String value;

  static SyncStatus fromValue(String? value) => SyncStatus.values.firstWhere(
        (s) => s.value == value,
        orElse: () => SyncStatus.pendingUpsert,
      );
}
