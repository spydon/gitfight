import 'dart:convert';

import 'package:gitfight/git/git_commit.dart';
import 'package:gitfight/git/git_service.dart';
import 'package:gitfight/supabase_config.dart';
import 'package:http/http.dart' as http;

/// Reads commit history through the `fetch-repo` Supabase edge function, which
/// caches each repository so the next visitor asking for the same repository
/// gets the cached data instead of hitting the host again.
///
/// The function fetches from the canonical host server-side and is the only
/// writer to the cache, so clients cannot poison it. We call it over plain
/// HTTP (no Supabase SDK) to keep the WebAssembly build clean. Live polling
/// ([fetchSince]) still goes straight to the host, since per-session "what is
/// new right now" is not worth caching.
class SupabaseGitService extends GitService {
  SupabaseGitService({super.maxCommits, http.Client? client})
    : _client = client ?? http.Client();

  final http.Client _client;

  @override
  Future<List<GitCommit>> fetchHistory(String rawUrl) async {
    try {
      final response = await _client.post(
        SupabaseConfig.functionUrl('fetch-repo'),
        headers: {
          'Content-Type': 'application/json',
          'apikey': SupabaseConfig.publishableKey,
          'Authorization': 'Bearer ${SupabaseConfig.publishableKey}',
        },
        body: jsonEncode({'url': rawUrl}),
      );
      final data = jsonDecode(response.body);
      if (response.statusCode == 200) {
        return _parseCommits(data);
      }
      // A clear error from the function (e.g. repo not found) is shown as-is;
      // anything else means the cache is unavailable, so fall back to the host.
      final message = data is Map ? data['error'] : null;
      if (message != null) {
        throw GitFetchException(message.toString());
      }
      return super.fetchHistory(rawUrl);
    } on GitFetchException {
      rethrow;
    } on Object catch (_) {
      return super.fetchHistory(rawUrl);
    }
  }

  List<GitCommit> _parseCommits(dynamic data) {
    final list = data is Map ? data['commits'] as List? : null;
    if (list == null) {
      throw GitFetchException('Unexpected response from the cache.');
    }
    final commits = list.map((item) {
      final map = item as Map;
      return GitCommit(
        displayName: map['name'] as String,
        identityKey: map['key'] as String,
        date: DateTime.parse(map['date'] as String),
        profileUrl: map['profileUrl'] as String?,
      );
    }).toList()..sort((a, b) => a.date.compareTo(b.date));
    if (commits.isEmpty) {
      throw GitFetchException('No commits found for this repository.');
    }
    return commits;
  }
}
