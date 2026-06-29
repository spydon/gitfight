import 'dart:async';

import 'package:gitfight/git/git_commit.dart';
import 'package:gitfight/git/git_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Reads commit history through the `fetch-repo` Supabase edge function, which
/// caches each repository so the next visitor asking for the same repository
/// gets the cached data instead of hitting the host again.
///
/// The function fetches from the canonical host server-side and is the only
/// writer to the cache, so clients cannot poison it. To make the first load
/// fast, a cache hit is served whole, while a cache miss streams straight from
/// the host (oldest first) and kicks off a background cache fill for next time.
class SupabaseGitService extends GitService {
  SupabaseGitService({SupabaseClient? client}) : _override = client;

  final SupabaseClient? _override;
  SupabaseClient get _client => _override ?? Supabase.instance.client;

  @override
  Stream<List<GitCommit>> streamHistory(String rawUrl) async* {
    Map<String, dynamic>? cache;
    try {
      cache = await _invoke({'url': rawUrl, 'cacheOnly': true});
    } on GitFetchException {
      rethrow;
    } on Object {
      cache = null; // Function unreachable; fall back to streaming from host.
    }

    if (cache != null && cache['cached'] == true) {
      yield _parseCommits(cache);
      return;
    }

    // Cache miss: fill it server-side for next time (without double-counting
    // the launch), and stream from the host right now.
    unawaited(_populate(rawUrl));
    yield* streamFromHost(rawUrl);
  }

  @override
  Future<List<GitCommit>> fetchHistory(String rawUrl) async {
    try {
      return _parseCommits(await _invoke({'url': rawUrl}));
    } on GitFetchException {
      rethrow;
    } on Object {
      return super.fetchHistory(rawUrl);
    }
  }

  Future<void> _populate(String rawUrl) async {
    try {
      await _invoke({'url': rawUrl, 'count': false});
    } on Object {
      // Best effort; the cache simply stays empty for next time.
    }
  }

  Future<Map<String, dynamic>> _invoke(Map<String, dynamic> body) async {
    try {
      final response = await _client.functions.invoke('fetch-repo', body: body);
      final data = response.data;
      if (data is Map<String, dynamic>) {
        return data;
      }
      throw Exception('Unexpected response from the cache.');
    } on FunctionException catch (e) {
      final details = e.details;
      final message = details is Map ? details['error'] : null;
      if (message != null) {
        throw GitFetchException(message.toString());
      }
      throw Exception('Cache request failed (${e.status}).');
    }
  }

  List<GitCommit> _parseCommits(Map<String, dynamic> data) {
    final list = data['commits'] as List?;
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
