/// Build-time config, passed with `--dart-define-from-file=config.json`.
class Env {
  const Env._();

  static const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

  static bool get isConfigured =>
      supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty;
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

  static const String osmTileUrl =
      'https://tile.openstreetmap.org/{z}/{x}/{y}.png';
  static const String userAgentPackageName = 'com.syaheer.nearby';

  /// Sent to Photon and OSRM, which ask apps to identify themselves.
  static const String httpUserAgent = 'Nearby/0.1 (com.syaheer.nearby)';
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
