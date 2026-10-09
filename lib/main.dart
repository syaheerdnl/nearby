import 'package:flutter/material.dart';

import 'app.dart';
import 'core/constants.dart';
import 'core/supabase_client.dart';
import 'services/notification_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (!Env.isConfigured) {
    runApp(const MissingConfigApp());
    return;
  }
  await initSupabase();
  await NotificationService.instance.init();
  await NotificationService.instance.checkLaunchedFromNotification();
  runApp(const NearbyApp());
}

/// Shown when the app was started without `--dart-define-from-file`.
class MissingConfigApp extends StatelessWidget {
  const MissingConfigApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      home: Scaffold(
        body: Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'Supabase config missing.\n\n'
              'Copy config.example.json to config.json, fill in your project '
              'URL and anon key, then run:\n\n'
              'flutter run --dart-define-from-file=config.json',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ),
    );
  }
}
