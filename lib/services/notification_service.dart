import 'dart:ui' show Color, IsolateNameServer;

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../core/constants.dart';
import 'local_db_service.dart';

/// Action id for the "Done" button on reminder notifications.
const String kDoneActionId = 'done';

/// Notification payload for a shared list: "list:<list id>". Plain zone ids
/// otherwise.
const String kListPayloadPrefix = 'list:';

/// Port the map screen listens on, so a "Done" from the background isolate
/// refreshes the open app right away.
const String kDonePortName = 'nearby_done';

/// Runs in a background isolate when the user presses "Done" on a reminder
/// notification without opening the app. Turns that place's reminders off
/// locally; they sync to Supabase the next time the app opens.
@pragma('vm:entry-point')
Future<void> onNotificationActionInBackground(NotificationResponse response) async {
  if (response.actionId != kDoneActionId) return;
  final zoneId = response.payload;
  if (zoneId == null || zoneId.isEmpty) return;
  try {
    final count = await LocalDbService.instance.turnOffReminders(zoneId);
    debugPrint('NEARBY_DONE zone=$zoneId turnedOff=$count');
    IsolateNameServer.lookupPortByName(kDonePortName)?.send(zoneId);
  } catch (e) {
    debugPrint('Done action failed for $zoneId: $e');
  }
}

/// Local notifications. Used from the UI isolate and from the geofence
/// background isolate, so each isolate initialises its own instance.
class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  bool _ready = false;

  /// Zone id from a tapped notification, waiting for the map screen to open
  /// it. Set on tap while the app runs, or from launch details on cold start.
  final ValueNotifier<String?> pendingZoneId = ValueNotifier<String?>(null);

  Future<void> init() async {
    if (_ready) return;
    try {
      final ok = await _plugin.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings('ic_stat_nearby'),
          iOS: DarwinInitializationSettings(
            requestAlertPermission: false,
            requestBadgePermission: false,
            requestSoundPermission: false,
          ),
        ),
        onDidReceiveNotificationResponse: _onTap,
        onDidReceiveBackgroundNotificationResponse:
            onNotificationActionInBackground,
      );
      _ready = ok ?? false;
    } catch (e) {
      debugPrint('Notifications init failed: $e');
    }
  }

  void _onTap(NotificationResponse response) {
    // Only plain taps reach here: "Done" has showsUserInterface: false.
    final zoneId = response.payload;
    if (response.actionId == null && zoneId != null && zoneId.isNotEmpty) {
      pendingZoneId.value = zoneId;
    }
  }

  /// Call once at startup (UI isolate only). If a reminder notification
  /// launched the app, queues its place to open.
  Future<void> checkLaunchedFromNotification() async {
    try {
      final details = await _plugin.getNotificationAppLaunchDetails();
      final response = details?.notificationResponse;
      if ((details?.didNotificationLaunchApp ?? false) && response != null) {
        _onTap(response);
      }
    } catch (e) {
      debugPrint('Reading launch details failed: $e');
    }
  }

  /// Android 13+ runtime prompt. Returns true when allowed (or not needed).
  Future<bool> requestPermission() async {
    await init();
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (android != null) {
      return await android.requestNotificationsPermission() ?? false;
    }
    final ios = _plugin.resolvePlatformSpecificImplementation<
        IOSFlutterLocalNotificationsPlugin>();
    if (ios != null) {
      return await ios.requestPermissions(alert: true, sound: true) ?? false;
    }
    return true;
  }

  Future<void> showZoneReminder({
    required int id,
    required String title,
    required String body,
    String? zoneId,
    String? payload,
    bool withDone = true,
  }) async {
    await init();
    if (!_ready) return;
    try {
      await _plugin.show(
        id: id,
        title: title,
        body: body,
        payload: payload ?? zoneId,
        notificationDetails: NotificationDetails(
          android: AndroidNotificationDetails(
            AppConstants.notificationChannelId,
            AppConstants.notificationChannelName,
            channelDescription: 'Reminders that fire when you reach or leave a place',
            importance: Importance.high,
            priority: Priority.high,
            styleInformation: BigTextStyleInformation(body),
            icon: 'ic_stat_nearby',
            color: const Color(0xFF3D3AA8),
            actions: withDone
                ? const <AndroidNotificationAction>[
                    AndroidNotificationAction(
                      kDoneActionId,
                      'Done',
                      // Handled in the background; the app stays closed.
                      showsUserInterface: false,
                      cancelNotification: true,
                    ),
                  ]
                : null,
          ),
          iOS: const DarwinNotificationDetails(
            interruptionLevel: InterruptionLevel.timeSensitive,
          ),
        ),
      );
    } catch (e) {
      debugPrint('Showing notification failed: $e');
    }
  }
}
