import 'dart:async' as async;
import 'dart:math' as math;

import 'package:flame/components.dart';
import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:gitfight/components/bullet.dart';
import 'package:gitfight/components/explosion.dart';
import 'package:gitfight/components/planet.dart';
import 'package:gitfight/components/spaceship.dart';
import 'package:gitfight/components/starfield.dart';
import 'package:gitfight/game/committer.dart';
import 'package:gitfight/git/git_commit.dart';
import 'package:gitfight/git/git_service.dart';
import 'package:gitfight/git/stats_service.dart';
import 'package:gitfight/git/supabase_git_service.dart';

/// Replays a repository's commit history as a space fight, and also drives the
/// overlay flow: fetching the history, switching to live mode and polling for
/// new commits. The widget layer only supplies overlay builders.
class GitFightGame extends FlameGame {
  GitFightGame({GitService? service, StatsService? stats})
    : _service = service ?? SupabaseGitService(),
      _stats = stats ?? StatsService();

  static const entryOverlay = 'entry';
  static const loadingOverlay = 'loading';
  static const hudOverlay = 'hud';

  static const _planetRadius = 60.0;
  static const _goldenAngle = 2.399963229728653;
  static const _maxCommitsPerFrame = 6;
  static const _pollInterval = Duration(seconds: 60);

  /// How long a single commit takes to play back, before [speed] is applied.
  static const _baseInterval = 0.275;

  /// Keeps the fleet clear of the planet in radial formations.
  static const _innerRadius = 100.0;

  /// Spacing that keeps ships from sitting on top of each other: [_ringGap]
  /// between concentric rings, [_arcGap] between neighbours along a ring/grid.
  static const _ringGap = 52.0;
  static const _arcGap = 46.0;
  static const _formationCount = 7;

  final GitService _service;
  final StatsService _stats;

  /// Two commits within this window of each other count as "close" enough to
  /// fire at one another.
  Duration closeWindow = const Duration(days: 2);

  /// A committer that has not committed within this window drives out of the
  /// scene until they commit again.
  Duration inactivityLimit = const Duration(days: 365);

  final committers = <String, Committer>{};

  late final Planet _planet;
  List<GitCommit> _timeline = const [];
  int _index = 0;
  double _sinceLast = 0;
  int _spawnCount = 0;

  final _rng = math.Random();
  double _formationTime = 0;
  double _formationSwitch = 0;
  int _formationType = 0;
  double _viewExtent = 320;

  double speed = 1.0;
  bool _playing = false;
  bool _live = false;
  bool _streamComplete = false;

  String? _url;
  DateTime? _liveSince;
  async.Timer? _liveTimer;
  bool _liveStarted = false;

  final currentDate = ValueNotifier<DateTime?>(null);
  final progress = ValueNotifier<double>(0);
  final leaderboard = ValueNotifier<List<Committer>>(const []);
  final finished = ValueNotifier<bool>(false);
  final live = ValueNotifier<bool>(false);
  final error = ValueNotifier<String?>(null);
  final launches = ValueNotifier<int?>(null);

  @override
  Color backgroundColor() => const Color(0xFF05060D);

  @override
  Future<void> onLoad() async {
    camera.backdrop.add(Starfield());
    _planet = Planet(radius: _planetRadius, position: Vector2.zero());
    world.add(_planet);
    camera.viewfinder.anchor = Anchor.center;
    _fitCamera();
    _refreshLaunches();
  }

  @override
  void onRemove() {
    _liveTimer?.cancel();
    super.onRemove();
  }

  /// Fetch the repository's history and start replaying it. Swaps the entry
  /// overlay for the loading overlay, then the HUD, reopening the entry on
  /// failure with the error shown.
  Future<void> submit(String url) async {
    error.value = null;
    overlays.remove(entryOverlay);
    overlays.add(loadingOverlay);
    var started = false;
    try {
      await for (final batch in _service.streamHistory(url)) {
        if (batch.isEmpty) {
          continue;
        }
        if (!started) {
          started = true;
          _url = url;
          _liveStarted = false;
          _liveTimer?.cancel();
          start(batch);
          overlays.remove(loadingOverlay);
          overlays.add(hudOverlay);
          _refreshLaunches();
        } else {
          _appendHistory(batch);
        }
      }
      if (!started) {
        throw GitFetchException('No commits found for this repository.');
      }
      _completeStream();
    } on GitFetchException catch (e) {
      started ? _completeStream() : _reopenEntry(e.message);
    } on Object catch (_) {
      started
          ? _completeStream()
          : _reopenEntry('Could not reach the host. Check the URL.');
    }
  }

  void _appendHistory(List<GitCommit> batch) {
    _timeline = [..._timeline, ...batch];
  }

  void _completeStream() {
    _streamComplete = true;
    if (_timeline.isNotEmpty) {
      _liveSince = _timeline.last.date;
    }
  }

  /// Return to the entry screen to pick a new repository.
  void restart() {
    _liveTimer?.cancel();
    _liveTimer = null;
    _liveStarted = false;
    overlays.remove(hudOverlay);
    _reopenEntry(null);
    _refreshLaunches();
  }

  void _reopenEntry(String? message) {
    overlays.remove(loadingOverlay);
    overlays.remove(hudOverlay);
    overlays.add(entryOverlay);
    error.value = message;
  }

  void _refreshLaunches() {
    async.unawaited(
      _stats.launches().then((value) {
        if (value != null) {
          launches.value = value;
        }
      }),
    );
  }

  /// Start live mode and poll for new commits. Triggered from the HUD, or
  /// automatically once the history finishes replaying.
  void goLive() {
    if (_liveStarted || _url == null) {
      return;
    }
    _liveStarted = true;
    enterLiveMode();
    _liveTimer = async.Timer.periodic(_pollInterval, (_) => _poll());
  }

  Future<void> _poll() async {
    final url = _url;
    final since = _liveSince;
    if (url == null || since == null) {
      return;
    }
    try {
      final fresh = await _service.fetchSince(url, since);
      if (fresh.isNotEmpty) {
        _liveSince = fresh.last.date;
        playLiveCommits(fresh);
      }
    } on Object catch (_) {
      // Transient failure (rate limit, network); retry on the next cycle.
    }
  }

  void start(List<GitCommit> timeline) {
    for (final committer in committers.values) {
      committer.ship?.removeFromParent();
    }
    committers.clear();
    _timeline = timeline;
    _index = 0;
    _sinceLast = 0;
    _spawnCount = 0;
    _playing = true;
    _live = false;
    _streamComplete = false;
    finished.value = false;
    live.value = false;
    progress.value = 0;
    currentDate.value = timeline.first.date;
    leaderboard.value = const [];
    _fitCamera();
  }

  /// Switch from replaying history to watching for new commits as they land.
  /// Replay stops where it is; [playLiveCommits] feeds in anything new.
  void enterLiveMode() {
    if (_live) {
      return;
    }
    _live = true;
    _playing = false;
    live.value = true;
    finished.value = true;
    progress.value = 1;
    if (_timeline.isNotEmpty) {
      currentDate.value = _timeline.last.date;
    }
    _checkInactivity(DateTime.now());
  }

  /// Play freshly polled commits immediately, as if they just happened.
  void playLiveCommits(List<GitCommit> commits) {
    if (commits.isEmpty) {
      return;
    }
    final start = _timeline.length;
    _timeline = List<GitCommit>.from(_timeline)..addAll(commits);
    for (var k = 0; k < commits.length; k++) {
      _processCommit(start + k);
    }
    _checkInactivity(DateTime.now());
    currentDate.value = _timeline.last.date;
  }

  @override
  void update(double dt) {
    super.update(dt);
    _updateFormation(dt);
    if (!_playing || _timeline.isEmpty) {
      return;
    }

    _sinceLast += dt * speed;
    var processed = 0;
    while (_sinceLast >= _baseInterval &&
        _index < _timeline.length &&
        processed < _maxCommitsPerFrame) {
      _processCommit(_index);
      _checkInactivity(_timeline[_index].date);
      _index++;
      _sinceLast -= _baseInterval;
      processed++;
    }

    progress.value = _index / _timeline.length;
    if (_index < _timeline.length) {
      currentDate.value = _timeline[_index].date;
    } else if (_playing && _streamComplete) {
      // Caught up and nothing more will stream in: history is done.
      _playing = false;
      finished.value = true;
      goLive();
    }
  }

  /// Advances the shared formation clock, occasionally switches to a different
  /// pattern, and hands every present ship its current slot in the formation.
  void _updateFormation(double dt) {
    _formationTime += dt;
    _formationSwitch -= dt;
    if (_formationSwitch <= 0) {
      final next = _rng.nextInt(_formationCount - 1);
      _formationType = next >= _formationType ? next + 1 : next;
      _formationSwitch = 9 + _rng.nextDouble() * 5;
    }
    final n = math.max(1, _spawnCount);
    for (final committer in committers.values) {
      final ship = committer.ship;
      if (ship == null || ship.isLeaving) {
        continue;
      }
      ship.setFormationTarget(
        _formationPosition(committer.slotIndex, n, _formationTime),
      );
    }
  }

  /// Position of slot [i] of [n] ships in the current formation at time [t].
  ///
  /// Formations are kept symmetric and evenly spaced (no overlaps), with a
  /// small deterministic per-ship jitter so they never look perfectly
  /// mechanical.
  Vector2 _formationPosition(int i, int n, double t) {
    final jr = _jitter(i, 6);
    final ja = _jitter(i * 31 + 7, 0.05);

    switch (_formationType) {
      case 1: // Breathing concentric rings.
        final slot = _ringSlot(i);
        final radius =
            (slot.radius + jr) * (1 + 0.05 * math.sin(t * 1.4 + slot.ring));
        final angle = slot.angle + ja + t * 0.22;
        return _polar(radius, angle);
      case 2: // Swirl: each ring twisted and rotating for a galaxy sweep.
        final slot = _ringSlot(i);
        final angle = slot.angle + ja + t * 0.3 + slot.ring * 0.18;
        return _polar(slot.radius + jr, angle);
      case 3: // Sunflower spiral (organic, evenly spread).
        final radius = _innerRadius + 24 * math.sqrt(i.toDouble()) + jr;
        final angle = i * _goldenAngle + ja + t * 0.25;
        return _polar(radius, angle);
      case 4: // Slowly rotating square grid.
        final cols = math.max(1, math.sqrt(n).ceil());
        final rows = (n / cols).ceil();
        final gx = ((i % cols) - (cols - 1) / 2) * _arcGap + jr;
        final gy = ((i ~/ cols) - (rows - 1) / 2) * _arcGap + jr;
        final ca = math.cos(t * 0.18);
        final sa = math.sin(t * 0.18);
        return Vector2(gx * ca - gy * sa, gx * sa + gy * ca);
      case 5: // Flower: ring radius bends into rotating petals.
        final slot = _ringSlot(i);
        final radius =
            slot.radius + jr + 18 * math.sin(6 * slot.angle + t * 0.6);
        final angle = slot.angle + ja + t * 0.15;
        return _polar(radius, angle);
      case 6: // Ripple: rings pulse outward like rings on water.
        final slot = _ringSlot(i);
        final radius =
            slot.radius + jr + 14 * math.sin(slot.ring * 0.9 - t * 2);
        final angle = slot.angle + ja + t * 0.12 * (slot.ring.isEven ? 1 : -1);
        return _polar(radius, angle);
      default: // Radar: counter-rotating concentric rings.
        final slot = _ringSlot(i);
        final dir = slot.ring.isEven ? 1 : -1;
        final angle = slot.angle + ja + t * 0.3 * dir;
        return _polar(slot.radius + jr, angle);
    }
  }

  Vector2 _polar(double radius, double angle) =>
      Vector2(math.cos(angle) * radius, math.sin(angle) * radius);

  /// Places slot [i] on a concentric-ring layout where each ring holds as many
  /// ships as fit around it with [_arcGap] spacing, so nothing overlaps.
  ({double radius, double angle, int ring}) _ringSlot(int i) {
    var ring = 0;
    var placed = 0;
    while (true) {
      final radius = _innerRadius + ring * _ringGap;
      final capacity = math.max(1, (2 * math.pi * radius / _arcGap).floor());
      if (i - placed < capacity) {
        return (
          radius: radius,
          angle: 2 * math.pi * (i - placed) / capacity,
          ring: ring,
        );
      }
      placed += capacity;
      ring++;
    }
  }

  /// Deterministic jitter in [-amount, amount] from an integer [seed].
  double _jitter(int seed, double amount) {
    final hashed = (seed * 2654435761) & 0x7fffffff;
    return (hashed % 1000 / 1000 - 0.5) * 2 * amount;
  }

  /// The radius the fleet occupies for [n] ships, used to frame the camera.
  double _layoutRadius(int n) {
    var ring = 0;
    var placed = 0;
    while (placed < n) {
      final radius = _innerRadius + ring * _ringGap;
      placed += math.max(1, (2 * math.pi * radius / _arcGap).floor());
      ring++;
    }
    final ringOuter = (_innerRadius + math.max(0, ring - 1) * _ringGap) * 1.12;
    final spiralOuter = _innerRadius + 24 * math.sqrt(n.toDouble());
    final cols = math.max(1, math.sqrt(n).ceil());
    final gridOuter = cols * _arcGap / 2 * math.sqrt2;
    return math.max(ringOuter, math.max(spiralOuter, gridOuter));
  }

  void _processCommit(int i) {
    final commit = _timeline[i];
    final shooter = _ensureCommitter(commit);
    final shooterShip = shooter.ship!;

    final neighbour = _nearbyOpponent(i);
    if (neighbour != null) {
      final target = _ensureCommitter(neighbour);
      final targetPos = target.ship!.position.clone();
      _fire(shooterShip, targetPos, () {
        shooter.score++;
        _refreshLabels([shooter]);
        world.add(Explosion(position: targetPos, color: target.color));
      });
      shooterShip.aimAt(targetPos);
    } else {
      final from = shooterShip.position.clone();
      final aim = _planet.position.clone();
      _fire(shooterShip, aim, () {
        shooter.score++;
        _refreshLabels([shooter]);
        _planet.registerHit();
        world.add(
          Explosion(position: _surfacePoint(from), color: shooter.color),
        );
      });
      shooterShip.aimAt(aim);
    }
    _updateLeaderboard();
  }

  /// The commit of a *different* committer nearest in time and within
  /// [closeWindow], or null if this committer is working alone.
  GitCommit? _nearbyOpponent(int i) {
    final commit = _timeline[i];
    GitCommit? best;
    Duration? bestGap;

    void scan(int step) {
      for (var j = i + step; j >= 0 && j < _timeline.length; j += step) {
        final other = _timeline[j];
        final gap = other.date.difference(commit.date).abs();
        if (gap > closeWindow) {
          break;
        }
        if (other.identityKey == commit.identityKey) {
          continue;
        }
        if (bestGap == null || gap < bestGap!) {
          best = other;
          bestGap = gap;
        }
        break;
      }
    }

    scan(-1);
    scan(1);
    return best;
  }

  Committer _ensureCommitter(GitCommit commit) {
    final existing = committers[commit.identityKey];
    if (existing != null) {
      if (existing.ship == null) {
        existing.ship = _spawnShip(existing);
      } else if (existing.ship!.isLeaving) {
        existing.ship!.returnHome();
      }
      existing.lastCommitDate = commit.date;
      return existing;
    }

    final slotIndex = _spawnCount++;
    final committer = Committer(
      identityKey: commit.identityKey,
      displayName: commit.displayName,
      color: _colorFor(commit.identityKey),
      slotIndex: slotIndex,
      profileUrl: commit.profileUrl,
    );
    committer.lastCommitDate = commit.date;
    committer.ship = _spawnShip(committer);
    committers[commit.identityKey] = committer;
    _fitCamera();
    return committer;
  }

  Spaceship _spawnShip(Committer committer) {
    final spawn = _formationPosition(
      committer.slotIndex,
      math.max(1, _spawnCount),
      _formationTime,
    );
    final ship = Spaceship(
      color: committer.color,
      shipName: committer.displayName,
      spawn: spawn,
      initialScore: committer.score,
    );
    world.add(ship);
    return ship;
  }

  /// Send away any committer that has been quiet for longer than
  /// [inactivityLimit] relative to [now].
  void _checkInactivity(DateTime now) {
    for (final committer in committers.values) {
      final ship = committer.ship;
      final last = committer.lastCommitDate;
      if (ship == null || ship.isLeaving || last == null) {
        continue;
      }
      if (now.difference(last) > inactivityLimit) {
        ship.leave(() => committer.ship = null, _viewExtent);
      }
    }
  }

  void _fire(Spaceship shooter, Vector2 target, VoidCallback onHit) {
    world.add(
      Bullet(
        start: shooter.position,
        target: target,
        color: shooter.color,
        onHit: onHit,
      ),
    );
  }

  void _refreshLabels(List<Committer> changed) {
    for (final committer in changed) {
      committer.ship?.setScore(committer.score);
    }
  }

  void _updateLeaderboard() {
    final all = committers.values.toList()
      ..sort((a, b) => b.score.compareTo(a.score));
    leaderboard.value = all.take(8).toList();
  }

  Vector2 _surfacePoint(Vector2 from) {
    final dir = (_planet.position - from)..normalize();
    return _planet.position - dir * _planetRadius;
  }

  void _fitCamera() {
    _viewExtent = _layoutRadius(math.max(1, _spawnCount)) + 80;
    final shortest = math.min(size.x, size.y);
    if (shortest <= 0) {
      return;
    }
    camera.viewfinder.zoom = (shortest / 2) / _viewExtent;
  }

  @override
  void onGameResize(Vector2 size) {
    super.onGameResize(size);
    _fitCamera();
  }

  Color _colorFor(String key) {
    final hue = (key.hashCode & 0x7fffffff) % 360;
    return HSVColor.fromAHSV(1, hue.toDouble(), 0.65, 1).toColor();
  }
}
