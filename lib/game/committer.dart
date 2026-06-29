import 'dart:ui';

import 'package:gitfight/components/spaceship.dart';

/// Runtime state for one committer taking part in the fight.
///
/// The committer keeps its slot, colour and score for the whole replay even
/// while its ship is off-screen, so it can rejoin where it left off.
class Committer {
  Committer({
    required this.identityKey,
    required this.displayName,
    required this.color,
    required this.slotIndex,
    this.profileUrl,
  });

  final String identityKey;
  final String displayName;
  final Color color;

  /// Stable index used to place this committer in the fleet's formations.
  final int slotIndex;

  /// Link to the committer's profile on the host, when available.
  final String? profileUrl;

  /// Null while the committer has driven out of the scene.
  Spaceship? ship;
  int score = 0;
  DateTime? lastCommitDate;

  bool get present => ship != null;
}
