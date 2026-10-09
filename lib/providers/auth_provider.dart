import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/supabase_client.dart';

/// Email/password auth. The username goes in sign-up metadata; a database
/// trigger turns it into the `profiles` row.
class AuthProvider extends ChangeNotifier {
  AuthProvider() {
    _session = supabase.auth.currentSession;
    _sub = supabase.auth.onAuthStateChange.listen((state) {
      _session = state.session;
      notifyListeners();
    });
  }

  late final StreamSubscription<AuthState> _sub;
  Session? _session;
  bool _busy = false;
  String? _error;

  bool get isSignedIn => _session != null;
  bool get busy => _busy;
  String? get error => _error;
  String? get userId => _session?.user.id;
  String? get email => _session?.user.email;

  static final usernamePattern = RegExp(r'^[a-z0-9_]{3,20}$');

  Future<bool> signIn(String email, String password) => _run(() async {
        await supabase.auth
            .signInWithPassword(email: email.trim(), password: password);
      });

  /// Returns a message to show when email confirmation is still needed.
  Future<String?> signUp({
    required String email,
    required String password,
    required String username,
  }) async {
    String? info;
    await _run(() async {
      final res = await supabase.auth.signUp(
        email: email.trim(),
        password: password,
        data: {'username': username.trim().toLowerCase()},
      );
      if (res.session == null) {
        info = 'Check your email to confirm the account, then sign in.';
      }
    });
    return info;
  }

  Future<void> signOut() async {
    await supabase.auth.signOut();
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }

  Future<bool> _run(Future<void> Function() action) async {
    _busy = true;
    _error = null;
    notifyListeners();
    try {
      await action();
      return true;
    } on AuthException catch (e) {
      _error = _friendly(e.message);
      return false;
    } catch (e) {
      _error = 'Something went wrong. Check your connection and try again.';
      debugPrint('Auth error: $e');
      return false;
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  String _friendly(String message) {
    final m = message.toLowerCase();
    if (m.contains('database error saving new user')) {
      return 'That username is taken or invalid. Use 3 to 20 lowercase letters, numbers or _.';
    }
    if (m.contains('invalid login credentials')) {
      return 'Wrong email or password.';
    }
    return message;
  }

  @override
  void dispose() {
    _sub.cancel();
    super.dispose();
  }
}
