import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'config.dart';
import 'screens/auth_screen.dart';
import 'screens/parent_home.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (Config.supabaseAnonKey.isNotEmpty) {
    await Supabase.initialize(
      url: Config.supabaseUrl,
      publishableKey: Config.supabaseAnonKey,
    );
  }
  runApp(const KidsApp());
}

class KidsApp extends StatelessWidget {
  const KidsApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'App Kids',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: const Color(0xFF6C5CE7),
        useMaterial3: true,
      ),
      home: Config.supabaseAnonKey.isEmpty
          ? const _MissingKey()
          : const _AuthGate(),
    );
  }
}

class _AuthGate extends StatelessWidget {
  const _AuthGate();

  @override
  Widget build(BuildContext context) {
    final auth = Supabase.instance.client.auth;
    return StreamBuilder<AuthState>(
      stream: auth.onAuthStateChange,
      builder: (context, _) =>
          auth.currentSession == null ? const AuthScreen() : const ParentHome(),
    );
  }
}

class _MissingKey extends StatelessWidget {
  const _MissingKey();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'Falta a chave do Supabase.\n\nExecute com:\n'
            'flutter run --dart-define=SUPABASE_ANON_KEY=<sua chave anon>',
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }
}
