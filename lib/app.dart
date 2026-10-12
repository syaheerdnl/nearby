import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'core/theme.dart';
import 'providers/auth_provider.dart';
import 'providers/zone_provider.dart';
import 'screens/onboarding/permission_intro_screen.dart';
import 'screens/onboarding/sign_in_screen.dart';
import 'screens/shell/app_shell.dart';
import 'services/local_db_service.dart';

class NearbyApp extends StatelessWidget {
  const NearbyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthProvider()),
        ChangeNotifierProvider(create: (_) => ZoneProvider()),
      ],
      child: MaterialApp(
        title: 'Nearby',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light(),
        darkTheme: AppTheme.dark(),
        home: const _AuthGate(),
      ),
    );
  }
}

/// Signed out -> sign in. Signed in -> intro once, then the map.
class _AuthGate extends StatefulWidget {
  const _AuthGate();

  @override
  State<_AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<_AuthGate> {
  static const _introKey = 'intro_seen';
  bool? _introSeen;
  String? _loadedFor;

  @override
  void initState() {
    super.initState();
    _readIntroFlag();
  }

  Future<void> _readIntroFlag() async {
    final value = await LocalDbService.instance.getMeta(_introKey);
    if (mounted) setState(() => _introSeen = value == '1');
  }

  Future<void> _finishIntro() async {
    await LocalDbService.instance.setMeta(_introKey, '1');
    if (mounted) setState(() => _introSeen = true);
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    if (!auth.isSignedIn) {
      _loadedFor = null;
      return const SignInScreen();
    }
    if (_introSeen == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_introSeen == false) {
      return PermissionIntroScreen(onContinue: _finishIntro);
    }
    // Load zones once per signed-in user.
    if (_loadedFor != auth.userId) {
      _loadedFor = auth.userId;
      WidgetsBinding.instance.addPostFrameCallback(
          (_) => context.read<ZoneProvider>().load());
    }
    return const AppShell();
  }
}
