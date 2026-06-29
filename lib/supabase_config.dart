/// Supabase project the repository cache lives in.
class SupabaseConfig {
  const SupabaseConfig._();

  static const url = 'https://obxavvuwjepnjoykpfce.supabase.co';
  static const publishableKey =
      'sb_publishable_HyFejB2UJvxKBp4wq5GKog_D78xSlyg';

  static Uri functionUrl(String name) => Uri.parse('$url/functions/v1/$name');
}
