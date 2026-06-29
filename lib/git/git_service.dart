import 'dart:convert';

import 'package:gitfight/git/git_commit.dart';
import 'package:http/http.dart' as http;

/// Thrown when a repository URL cannot be parsed or fetched.
class GitFetchException implements Exception {
  GitFetchException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Thrown when the host rate limits us. When it happens partway through
/// paging we keep whatever history was already fetched.
class GitRateLimitException extends GitFetchException {
  GitRateLimitException() : super('Rate limited by the host, try again later.');
}

/// Fetches commit history from the big public git hosts using their REST APIs.
///
/// Browsers cannot clone a repository, so we read the history through the
/// hosts' CORS enabled JSON APIs instead. The history is returned oldest
/// commit first so the visualization can replay it forwards in time.
class GitService {
  GitService({this.maxCommits = 20000});

  /// Upper bound on how many commits we pull. Only the committer name and date
  /// are kept per commit, so a large history stays cheap to hold in memory.
  final int maxCommits;

  static const _perPage = 100;

  Future<List<GitCommit>> fetchHistory(String rawUrl) async {
    final repo = _parse(rawUrl);
    final commits = switch (repo.host) {
      _Host.github => await _fetchGitHub(repo),
      _Host.gitlab => await _fetchGitLab(repo),
      _Host.bitbucket => await _fetchBitbucket(repo),
    };
    if (commits.isEmpty) {
      throw GitFetchException('No commits found for this repository.');
    }
    commits.sort((a, b) => a.date.compareTo(b.date));
    return commits;
  }

  /// Returns commits strictly newer than [since], used to poll for new commits
  /// while in live mode. Only the latest page is inspected.
  Future<List<GitCommit>> fetchSince(String rawUrl, DateTime since) async {
    final repo = _parse(rawUrl);
    final iso = since.toUtc().toIso8601String();
    final commits = switch (repo.host) {
      _Host.github => await _getJsonList(
        Uri.https(
          'api.github.com',
          '/repos/${repo.owner}/${repo.name}/commits',
          {'per_page': '$_perPage', 'since': iso},
        ),
      ).then((l) => l.cast<Map<String, dynamic>>().map(_mapGitHub).toList()),
      _Host.gitlab => await _getJsonList(
        Uri.https(
          'gitlab.com',
          '/api/v4/projects/${Uri.encodeComponent(repo.owner)}/repository/commits',
          {'per_page': '$_perPage', 'since': iso},
        ),
      ).then((l) => l.cast<Map<String, dynamic>>().map(_mapGitLab).toList()),
      _Host.bitbucket => await _bitbucketFirstPage(repo),
    };
    final fresh = commits.where((c) => c.date.isAfter(since)).toList()
      ..sort((a, b) => a.date.compareTo(b.date));
    return fresh;
  }

  _Repo _parse(String rawUrl) {
    var url = rawUrl.trim();
    if (url.isEmpty) {
      throw GitFetchException('Please enter a repository URL.');
    }
    if (!url.contains('://')) {
      url = 'https://$url';
    }
    final uri = Uri.tryParse(url);
    if (uri == null || uri.host.isEmpty) {
      throw GitFetchException('That does not look like a valid URL.');
    }

    final segments = uri.pathSegments
        .where((s) => s.isNotEmpty)
        .map((s) => s.endsWith('.git') ? s.substring(0, s.length - 4) : s)
        .toList();
    if (segments.length < 2) {
      throw GitFetchException(
        'The URL must point to a repository, e.g. host.com/owner/repo.',
      );
    }

    final host = uri.host.toLowerCase();
    if (host.contains('github')) {
      return _Repo(_Host.github, segments[0], segments[1]);
    }
    if (host.contains('gitlab')) {
      // GitLab supports nested groups, so the project path is everything.
      return _Repo(_Host.gitlab, segments.join('/'), '');
    }
    if (host.contains('bitbucket')) {
      return _Repo(_Host.bitbucket, segments[0], segments[1]);
    }
    throw GitFetchException(
      'Unsupported host. Try GitHub, GitLab or Bitbucket.',
    );
  }

  Future<List<dynamic>> _getJsonList(Uri uri) async {
    final response = await http.get(
      uri,
      headers: {'Accept': 'application/json'},
    );
    if (response.statusCode == 404) {
      throw GitFetchException('Repository not found (is it public?).');
    }
    if (response.statusCode == 403 || response.statusCode == 429) {
      throw GitRateLimitException();
    }
    if (response.statusCode != 200) {
      throw GitFetchException('Host returned status ${response.statusCode}.');
    }
    return jsonDecode(response.body) as List<dynamic>;
  }

  Future<List<GitCommit>> _fetchGitHub(_Repo repo) async {
    final commits = <GitCommit>[];
    for (var page = 1; commits.length < maxCommits; page++) {
      final uri = Uri.https(
        'api.github.com',
        '/repos/${repo.owner}/${repo.name}/commits',
        {'per_page': '$_perPage', 'page': '$page'},
      );
      final List<dynamic> list;
      try {
        list = await _getJsonList(uri);
      } on GitRateLimitException {
        if (commits.isNotEmpty) {
          break;
        }
        rethrow;
      }
      if (list.isEmpty) {
        break;
      }
      commits.addAll(list.cast<Map<String, dynamic>>().map(_mapGitHub));
      if (list.length < _perPage) {
        break;
      }
    }
    return commits;
  }

  Future<List<GitCommit>> _fetchGitLab(_Repo repo) async {
    final encodedPath = Uri.encodeComponent(repo.owner);
    final commits = <GitCommit>[];
    for (var page = 1; commits.length < maxCommits; page++) {
      final uri = Uri.https(
        'gitlab.com',
        '/api/v4/projects/$encodedPath/repository/commits',
        {'per_page': '$_perPage', 'page': '$page'},
      );
      final List<dynamic> list;
      try {
        list = await _getJsonList(uri);
      } on GitRateLimitException {
        if (commits.isNotEmpty) {
          break;
        }
        rethrow;
      }
      if (list.isEmpty) {
        break;
      }
      commits.addAll(list.cast<Map<String, dynamic>>().map(_mapGitLab));
      if (list.length < _perPage) {
        break;
      }
    }
    return commits;
  }

  Future<List<GitCommit>> _fetchBitbucket(_Repo repo) async {
    final commits = <GitCommit>[];
    Uri? uri = Uri.https(
      'api.bitbucket.org',
      '/2.0/repositories/${repo.owner}/${repo.name}/commits',
      {'pagelen': '$_perPage'},
    );
    while (uri != null && commits.length < maxCommits) {
      final Map<String, dynamic> body;
      try {
        body = await _bitbucketBody(uri);
      } on GitRateLimitException {
        if (commits.isNotEmpty) {
          break;
        }
        rethrow;
      }
      final values = (body['values'] as List<dynamic>)
          .cast<Map<String, dynamic>>();
      commits.addAll(values.map(_mapBitbucket));
      final next = body['next'] as String?;
      uri = next == null ? null : Uri.parse(next);
    }
    return commits;
  }

  Future<List<GitCommit>> _bitbucketFirstPage(_Repo repo) async {
    final body = await _bitbucketBody(
      Uri.https(
        'api.bitbucket.org',
        '/2.0/repositories/${repo.owner}/${repo.name}/commits',
        {'pagelen': '$_perPage'},
      ),
    );
    final values = (body['values'] as List<dynamic>)
        .cast<Map<String, dynamic>>();
    return values.map(_mapBitbucket).toList();
  }

  Future<Map<String, dynamic>> _bitbucketBody(Uri uri) async {
    final response = await http.get(
      uri,
      headers: {'Accept': 'application/json'},
    );
    if (response.statusCode == 404) {
      throw GitFetchException('Repository not found (is it public?).');
    }
    if (response.statusCode == 403 || response.statusCode == 429) {
      throw GitRateLimitException();
    }
    if (response.statusCode != 200) {
      throw GitFetchException('Host returned status ${response.statusCode}.');
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  GitCommit _mapGitHub(Map<String, dynamic> item) {
    final commit = item['commit'] as Map<String, dynamic>;
    final author = commit['author'] as Map<String, dynamic>?;
    final ghUser = item['author'] as Map<String, dynamic>?;
    final name = (author?['name'] as String?) ?? 'unknown';
    final email = (author?['email'] as String?) ?? name;
    return GitCommit(
      displayName: (ghUser?['login'] as String?) ?? name,
      identityKey: email.toLowerCase(),
      date: DateTime.parse(author?['date'] as String),
      avatarUrl: ghUser?['avatar_url'] as String?,
      profileUrl: ghUser?['html_url'] as String?,
    );
  }

  GitCommit _mapGitLab(Map<String, dynamic> item) {
    final name = (item['author_name'] as String?) ?? 'unknown';
    final email = (item['author_email'] as String?) ?? name;
    return GitCommit(
      displayName: name,
      identityKey: email.toLowerCase(),
      date: DateTime.parse(item['committed_date'] as String),
    );
  }

  GitCommit _mapBitbucket(Map<String, dynamic> item) {
    final author = item['author'] as Map<String, dynamic>?;
    final user = author?['user'] as Map<String, dynamic>?;
    final raw = (author?['raw'] as String?) ?? 'unknown';
    final name =
        (user?['nickname'] as String?) ??
        (user?['display_name'] as String?) ??
        _nameFromRaw(raw);
    final links = user?['links'] as Map<String, dynamic>?;
    final avatar = links?['avatar'] as Map<String, dynamic>?;
    final html = links?['html'] as Map<String, dynamic>?;
    return GitCommit(
      displayName: name,
      identityKey: _emailFromRaw(raw).toLowerCase(),
      date: DateTime.parse(item['date'] as String),
      avatarUrl: avatar?['href'] as String?,
      profileUrl: html?['href'] as String?,
    );
  }

  String _nameFromRaw(String raw) {
    final idx = raw.indexOf('<');
    return idx > 0 ? raw.substring(0, idx).trim() : raw.trim();
  }

  String _emailFromRaw(String raw) {
    final start = raw.indexOf('<');
    final end = raw.indexOf('>');
    if (start >= 0 && end > start) {
      return raw.substring(start + 1, end);
    }
    return raw;
  }
}

enum _Host { github, gitlab, bitbucket }

class _Repo {
  _Repo(this.host, this.owner, this.name);

  final _Host host;
  final String owner;
  final String name;
}
