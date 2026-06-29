/// A single commit pulled from a remote git host.
class GitCommit {
  GitCommit({
    required this.displayName,
    required this.identityKey,
    required this.date,
    this.avatarUrl,
    this.profileUrl,
  });

  /// The nickname shown next to the ship (login/nickname when available,
  /// otherwise the author name).
  final String displayName;

  /// Stable key used to group commits to the same committer. Prefers the
  /// email, falls back to the display name.
  final String identityKey;

  final DateTime date;

  final String? avatarUrl;

  /// Link to the committer's profile on the host, when available.
  final String? profileUrl;
}
