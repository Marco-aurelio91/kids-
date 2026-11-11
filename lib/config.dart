// A chave anon é pública (protegida por RLS), mas é passada em build:
//   flutter run --dart-define=SUPABASE_ANON_KEY=<chave anon>
class Config {
  static const supabaseUrl = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://wzdzezoatbzvhuvlrkcy.supabase.co',
  );
  static const supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');
}
