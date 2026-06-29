import 'dart:math' as math;

import 'package:flame/components.dart';
import 'package:flame/effects.dart';
import 'package:flutter/widgets.dart';

/// A committer's ship. When idle it flies to the formation slot the game hands
/// it, so the whole fleet moves together in shifting patterns. While firing it
/// nearly stops to take aim, and it drives out of the scene when the committer
/// goes quiet. Its nickname and score are drawn with a contrasting outline so
/// they stay readable over any colour.
class Spaceship extends PositionComponent {
  Spaceship({
    required this.color,
    required this.shipName,
    required Vector2 spawn,
    this.initialScore = 0,
  }) : super(
         anchor: Anchor.center,
         position: spawn.clone(),
         size: Vector2(34, 34),
       );

  final Color color;
  final String shipName;
  final int initialScore;

  static const _maxSpeed = 150.0;
  static const _trackGain = 2.6;
  static const _steerLerp = 6.0;
  static const _firingSpeedScale = 0.06;
  static const _exitSpeed = 240.0;

  late final TextComponent _outline;
  late final TextComponent _label;
  int _score = 0;

  double _heading = -math.pi / 2;
  double _targetHeading = -math.pi / 2;
  double _fireFlash = 0;

  Vector2 _velocity = Vector2.zero();
  Vector2 _formationTarget = Vector2.zero();
  Vector2 _aimTarget = Vector2.zero();

  bool _leaving = false;
  VoidCallback? _onExited;
  Vector2 _exitTarget = Vector2.zero();
  double _exitBeyond = 0;

  bool get isLeaving => _leaving;

  @override
  Future<void> onLoad() async {
    _score = initialScore;
    _formationTarget = position.clone();

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

    // Fly-in: pop into existence with a quick scale up.
    scale = Vector2.zero();
    add(
      ScaleEffect.to(
        Vector2.all(1),
        EffectController(duration: 0.4, curve: Curves.easeOutBack),
      ),
    );
  }

  String get _labelText => '$shipName  $_score';

  void setScore(int score) {
    _score = score;
    _label.text = _labelText;
    _outline.text = _labelText;
  }

  /// The fleet's formation slot this ship should fly to. Ignored while leaving.
  void setFormationTarget(Vector2 target) {
    if (!_leaving) {
      _formationTarget = target;
    }
  }

  /// Turn to face [worldTarget] and flash the thrusters. Firing also makes the
  /// ship nearly stop so it looks like it is taking aim.
  void aimAt(Vector2 worldTarget) {
    _aimTarget = worldTarget.clone();
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
    final base = position.length2 == 0 ? Vector2(1, 0) : position;
    _exitTarget = base.normalized() * (beyond + 400);
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
      return;
    }

    final toTarget = _formationTarget - position;
    var desired = toTarget * _trackGain;
    final speed = desired.length;
    if (speed > _maxSpeed) {
      desired *= _maxSpeed / speed;
    }
    // Nearly stop while taking a shot.
    if (_fireFlash > 0) {
      desired *= _firingSpeedScale;
    }
    _velocity += (desired - _velocity) * math.min(1, dt * _steerLerp);
    position += _velocity * dt;
    _updateHeading(dt);
  }

  void _updateLeaving(double dt) {
    final toTarget = _exitTarget - position;
    final dist = toTarget.length;
    if (dist > 0.5) {
      _velocity = toTarget / dist * _exitSpeed;
      position += _velocity * dt;
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
      final d = _aimTarget - position;
      if (d.length2 > 0) {
        _targetHeading = math.atan2(d.y, d.x);
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
    canvas.save();
    canvas.translate(size.x / 2, size.y / 2);
    canvas.rotate(_heading + math.pi / 2);

    final hull = Path()
      ..moveTo(0, -size.y / 2)
      ..lineTo(size.x / 2, size.y / 2)
      ..lineTo(0, size.y / 3)
      ..lineTo(-size.x / 2, size.y / 2)
      ..close();

    canvas.drawPath(
      hull,
      Paint()
        ..color = color.withValues(alpha: 0.25)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
    );
    canvas.drawPath(hull, Paint()..color = color);
    canvas.drawPath(
      hull,
      Paint()
        ..color = const Color(0xFFFFFFFF).withValues(alpha: 0.6)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );

    // Cockpit.
    canvas.drawCircle(
      const Offset(0, -2),
      4,
      Paint()..color = const Color(0xFFEAF6FF),
    );

    // Thruster flame when firing.
    if (_fireFlash > 0) {
      canvas.drawPath(
        Path()
          ..moveTo(-4, size.y / 2)
          ..lineTo(0, size.y / 2 + 10 * _fireFlash)
          ..lineTo(4, size.y / 2),
        Paint()..color = const Color(0xFFFFD166).withValues(alpha: _fireFlash),
      );
    }
    canvas.restore();
  }
}
