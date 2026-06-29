import 'dart:math' as math;

import 'package:flame/components.dart';
import 'package:flutter/widgets.dart';

/// A committer's ship. When idle it flies to the formation slot the game hands
/// it (including a depth/scale so formations can move in Z), nearly stops while
/// firing to take aim, and drives out of the scene when the committer goes
/// quiet. Its nickname and score are drawn with a contrasting outline.
///
/// Paints, paths and working vectors are allocated once and reused, since
/// [update] and [render] run every frame for every ship.
class Spaceship extends PositionComponent {
  Spaceship({
    required this.color,
    required this.shipName,
    required Vector2 spawn,
    this.initialScore = 0,
  }) : super(
         anchor: Anchor.center,
         position: spawn.clone(),
         size: Vector2(36, 36),
       );

  final Color color;
  final String shipName;
  final int initialScore;

  static const _maxSpeed = 150.0;
  static const _trackGain = 2.6;
  static const _steerLerp = 6.0;
  static const _firingSpeedScale = 0.06;
  static const _exitSpeed = 240.0;
  static const _engineColor = Color(0xFF8FE3FF);
  static const _flameColor = Color(0xFFFFD166);

  /// Muted highlight tone used instead of pure white, so ships are not glaring.
  static const _highlight = Color(0xFFAEC2D6);

  /// Distance from the centre within which the ship keeps its current depth
  /// priority (just clears the planet, which is at the origin).
  static const _planetClearance = 80.0;

  late final TextComponent _outline;
  late final TextComponent _label;
  int _score = 0;

  double _heading = -math.pi / 2;
  double _targetHeading = -math.pi / 2;
  double _fireFlash = 0;
  double _depthScale = 1;

  final Vector2 _velocity = Vector2.zero();
  final Vector2 _formationTarget = Vector2.zero();
  final Vector2 _aimTarget = Vector2.zero();
  final Vector2 _desired = Vector2.zero();

  bool _leaving = false;
  VoidCallback? _onExited;
  final Vector2 _exitTarget = Vector2.zero();
  double _exitBeyond = 0;

  // Reused paints/paths (built in onLoad once the colours are known).
  final Paint _auraPaint = Paint()
    ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);
  final Paint _enginePaint = Paint()
    ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5);
  final Paint _wingPaint = Paint();
  final Paint _hullPaint = Paint();
  final Paint _trimPaint = Paint();
  final Paint _outlinePaint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1.4
    ..color = _highlight.withValues(alpha: 0.4);
  final Paint _canopyOuterPaint = Paint()..color = _highlight;
  final Paint _canopyInnerPaint = Paint()..color = _engineColor;
  final Paint _flamePaint = Paint()
    ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2);
  late final Path _hullPath;
  late final Path _wingsPath;
  late final Path _highlightPath;

  bool get isLeaving => _leaving;

  @override
  Future<void> onLoad() async {
    _score = initialScore;
    _formationTarget.setFrom(position);

    _auraPaint.color = color.withValues(alpha: 0.16);
    _enginePaint.color = _engineColor.withValues(alpha: 0.45);
    _wingPaint.color = Color.lerp(color, const Color(0xFF05060D), 0.4)!;
    _hullPaint.color = color;
    _trimPaint.color = Color.lerp(color, _highlight, 0.4)!;
    _buildPaths();

    final contrast = color.computeLuminance() > 0.5
        ? const Color(0xFF06080F)
        : const Color(0xFFFFFFFF);
    final labelPosition = Vector2(0, size.y / 2 + 6);
    _outline = TextComponent(
      text: _labelText,
      anchor: Anchor.topCenter,
      position: labelPosition,
      textRenderer: TextPaint(
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          foreground: Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 3
            ..strokeJoin = StrokeJoin.round
            ..color = contrast,
        ),
      ),
    );
    _label = TextComponent(
      text: _labelText,
      anchor: Anchor.topCenter,
      position: labelPosition,
      textRenderer: TextPaint(
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
    add(_outline);
    add(_label);

    // Fly-in: ease up from nothing to the current depth scale.
    scale = Vector2.zero();
  }

  void _buildPaths() {
    final w = size.x;
    final h = size.y;
    _wingsPath = Path()
      ..moveTo(w * 0.16, h * 0.04)
      ..lineTo(w * 0.54, h * 0.46)
      ..lineTo(w * 0.12, h * 0.34)
      ..close()
      ..moveTo(-w * 0.16, h * 0.04)
      ..lineTo(-w * 0.54, h * 0.46)
      ..lineTo(-w * 0.12, h * 0.34)
      ..close();
    _hullPath = Path()
      ..moveTo(0, -h * 0.55)
      ..lineTo(w * 0.2, h * 0.12)
      ..lineTo(w * 0.15, h * 0.48)
      ..lineTo(-w * 0.15, h * 0.48)
      ..lineTo(-w * 0.2, h * 0.12)
      ..close();
    _highlightPath = Path()
      ..moveTo(0, -h * 0.55)
      ..lineTo(w * 0.2, h * 0.12)
      ..lineTo(0, h * 0.02)
      ..close();
  }

  String get _labelText => '$shipName  $_score';

  void setScore(int score) {
    _score = score;
    _label.text = _labelText;
    _outline.text = _labelText;
  }

  /// The fleet's formation slot this ship should fly to. Ignored while leaving.
  void setFormationTarget(double x, double y) {
    if (!_leaving) {
      _formationTarget.setValues(x, y);
    }
  }

  /// Depth of this ship in the formation, expressed as a render scale (smaller
  /// is "further away"). Ignored while leaving.
  void setDepth(double depthScale) {
    if (!_leaving) {
      _depthScale = depthScale;
    }
  }

  /// Turn to face [worldTarget] and flash the thrusters. Firing also makes the
  /// ship nearly stop so it looks like it is taking aim.
  void aimAt(Vector2 worldTarget) {
    _aimTarget.setFrom(worldTarget);
    _fireFlash = 1;
  }

  /// Drive off the screen, past [beyond] from the centre. [onExited] runs once
  /// the ship has left.
  void leave(VoidCallback onExited, double beyond) {
    if (_leaving) {
      return;
    }
    _leaving = true;
    _onExited = onExited;
    _exitBeyond = beyond;
    _depthScale = 1;
    if (position.length2 == 0) {
      _exitTarget.setValues(beyond + 400, 0);
    } else {
      _exitTarget
        ..setFrom(position)
        ..normalize()
        ..scale(beyond + 400);
    }
  }

  /// Rejoin the fleet and resume flying to formation slots.
  void returnHome() {
    if (!_leaving) {
      return;
    }
    _leaving = false;
    _onExited = null;
  }

  @override
  void update(double dt) {
    super.update(dt);
    if (_fireFlash > 0) {
      _fireFlash = math.max(0, _fireFlash - dt * 3);
    }

    if (_leaving) {
      _updateLeaving(dt);
    } else {
      _desired
        ..setFrom(_formationTarget)
        ..sub(position)
        ..scale(_trackGain);
      final speed = _desired.length;
      if (speed > _maxSpeed) {
        _desired.scale(_maxSpeed / speed);
      }
      if (_fireFlash > 0) {
        _desired.scale(_firingSpeedScale); // Nearly stop while taking a shot.
      }
      final lerp = math.min(1.0, dt * _steerLerp);
      _velocity
        ..scale(1 - lerp)
        ..addScaled(_desired, lerp);
      position.addScaled(_velocity, dt);
      _updateHeading(dt);
    }

    final s = scale.x + (_depthScale - scale.x) * math.min(1, dt * 4);
    scale.setValues(s, s);
    // Depth ordering: smaller (further) ships fall behind the planet, larger
    // (closer) ones stay in front. The planet sits at scale 1 -> priority 100.
    // Only re-decide front/behind while clear of the planet, so a ship doesn't
    // flip (and flicker) as it passes over it. Flame only reorders on change.
    if (position.length2 > _planetClearance * _planetClearance) {
      priority = (s * 100).round();
    }
  }

  void _updateLeaving(double dt) {
    _desired
      ..setFrom(_exitTarget)
      ..sub(position);
    final dist = _desired.length;
    if (dist > 0.5) {
      _velocity
        ..setFrom(_desired)
        ..scale(_exitSpeed / dist);
      position.addScaled(_velocity, dt);
    }
    if (position.length > _exitBeyond + 150) {
      _onExited?.call();
      removeFromParent();
      return;
    }
    _updateHeading(dt);
  }

  void _updateHeading(double dt) {
    if (_fireFlash > 0) {
      final dx = _aimTarget.x - position.x;
      final dy = _aimTarget.y - position.y;
      if (dx != 0 || dy != 0) {
        _targetHeading = math.atan2(dy, dx);
      }
    } else if (_velocity.length2 > 1) {
      _targetHeading = math.atan2(_velocity.y, _velocity.x);
    }

    var diff = _targetHeading - _heading;
    while (diff > math.pi) {
      diff -= 2 * math.pi;
    }
    while (diff < -math.pi) {
      diff += 2 * math.pi;
    }
    _heading += diff * math.min(1, dt * 8);
  }

  @override
  void render(Canvas canvas) {
    final w = size.x;
    final h = size.y;
    canvas.save();
    canvas.translate(w / 2, h / 2);
    canvas.rotate(_heading + math.pi / 2);

    canvas.drawCircle(Offset.zero, w * 0.66, _auraPaint);

    // Steady, gentle engine glow at the tail.
    canvas.drawCircle(Offset(0, h * 0.42), h * 0.24, _enginePaint);

    canvas.drawPath(_wingsPath, _wingPaint);
    canvas.drawPath(_hullPath, _hullPaint);
    canvas.drawPath(_highlightPath, _trimPaint);
    canvas.drawPath(_hullPath, _outlinePaint);

    canvas.drawCircle(Offset(0, -h * 0.12), w * 0.1, _canopyOuterPaint);
    canvas.drawCircle(Offset(0, -h * 0.12), w * 0.055, _canopyInnerPaint);

    // Tiny muzzle burst at the nose tip while firing.
    if (_fireFlash > 0) {
      _flamePaint.color = _flameColor.withValues(alpha: _fireFlash);
      canvas.drawCircle(
        Offset(0, -h * 0.55),
        w * 0.13 * _fireFlash,
        _flamePaint,
      );
    }
    canvas.restore();
  }
}
