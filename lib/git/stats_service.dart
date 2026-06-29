import 'dart:convert';

import 'package:gitfight/supabase_config.dart';
import 'package:http/http.dart' as http;

/// Reads the shared launch counter from Supabase for display. The counter is
/// only ever incremented server-side by the `fetch-repo` edge function, so the
/// client just reads it here.
class StatsService {
  StatsService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  Future<int?> launches() async {
    try {
      final response = await _client.get(
        Uri.parse('${SupabaseConfig.url}/rest/v1/app_stats?select=launches'),
        headers: {
          'apikey': SupabaseConfig.publishableKey,
          'Authorization': 'Bearer ${SupabaseConfig.publishableKey}',
        },
      );
      if (response.statusCode != 200) {
        return null;
      }
      final list = jsonDecode(response.body) as List<dynamic>;
      if (list.isEmpty) {
        return null;
      }
      return (list.first as Map<String, dynamic>)['launches'] as int?;
    } on Exception {
      return null;
    }
  }
}
