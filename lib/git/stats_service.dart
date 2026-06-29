import 'package:supabase_flutter/supabase_flutter.dart';

/// Reads the shared launch counter from Supabase for display. The counter is
/// only ever incremented server-side by the `fetch-repo` edge function, so the
/// client just reads it here.
class StatsService {
  StatsService({SupabaseClient? client}) : _override = client;

  final SupabaseClient? _override;
  SupabaseClient get _client => _override ?? Supabase.instance.client;

  Future<int?> launches() async {
    try {
      final rows = await _client.from('app_stats').select('launches').limit(1);
      if (rows.isEmpty) {
        return null;
      }
      return rows.first['launches'] as int?;
    } on Exception {
      return null;
    }
  }
}
