import 'package:supabase_flutter/supabase_flutter.dart';

import 'constants.dart';

/// The one Supabase client. Only repositories and AuthProvider should use it.
SupabaseClient get supabase => Supabase.instance.client;

Future<void> initSupabase() async {
  await Supabase.initialize(
    url: Env.supabaseUrl,
    publishableKey: Env.supabaseAnonKey,
  );
}
