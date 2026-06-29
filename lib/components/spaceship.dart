import 'dart:math' as math;

import 'package:flame/components.dart';
import 'package:flame/effects.dart';
import 'package:flutter/widgets.dart';

/// A committer's ship. When idle it meanders naturally around its home slot, it
/// turns to face whatever it is firing at, and it can drive out of the scene
/// when the committer goes quiet. Its nickname and score are drawn with a
/// contrasting outline so they stay readable over any colour.
class Spaceship extends PositionComponent {
  Spaceship({
    required this.color,
    required this.shipName,
    required this.home,
    this.initialScore = 0,
  }) : super(
         anchor: Anchor.center,
         position: home.clone(),
         size: Vector2(34, 34),
       );

  final Color color;
  final String shipName;
  final Vector2 home;
  final int initialScore;

  // Steering parameters for the idle meander.
  static const _cruiseSpeed = 26.0;
  static const _maxSpeed = 46.0;
  static const _turnJitter = 2.6;
  static const _homePull = 0.7;
  static const _steer = 1.8;

  static const _exitSpeed = 230.0;
  static const _exitMargin = 560.0;

  late final TextComponent _outline;
  late final TextComponent _label;
  int _score = 0;

  double _heading = -math.pi / 2;
  double _targetHeading = -math.pi / 2;
  double _fireFlash = 0;

  final _rng = math.Random();
  Vector2 _velocity = Vector2.zero();
  double _wanderAngle = 0;
  Vector2 _aimTarget = Vector2.zero();

  bool _leaving = false;
  VoidCallback? _onExited;
  Vector2 _exitTarget = Vector2.zero();

  bool get isLeaving => _leaving;

  @override
  Future<void> onLoad() async {
    _score = initialScore;
    _wanderAngle = _rng.nextDouble() * 2 * math.pi;
    _velocity =
        Vector2(math.cos(_wanderAngle), math.sin(_wanderAngle)) * _cruiseSpeed;

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

  /// Turn to face [worldTarget] and flash the thrusters.
  void aimAt(Vector2 worldTarget) {
    _aimTarget = worldTarget.clone();
    _fireFlash = 1;
  }

  /// Drive off the screen. [onExited] runs once the ship has left.
  void leave(VoidCallback onExited) {
    if (_leaving) {
      return;
    }
    _leaving = true;
    _onExited = onExited;
    final base = position.length2 == 0 ? home : position;
    _exitTarget = base.normalized() * (home.length + _exitMargin + 200);
  }

  /// Come back and resume meandering around the home slot.
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
    _updateWander(dt);
    _updateHeading(dt);
  }

  void _updateWander(double dt) {
    // Reynolds-style wander: a heading that random-walks gives smooth, curving
    // paths, while a spring back towards home keeps the ship in its area.
    _wanderAngle += (_rng.nextDouble() * 2 - 1) * _turnJitter * dt;
    final cruise =
        Vector2(math.cos(_wanderAngle), math.sin(_wanderAngle)) * _cruiseSpeed;
    final pull = (home - position) * _homePull;
    final desired = cruise + pull;

    _velocity += (desired - _velocity) * math.min(1, _steer * dt);
    final speed = _velocity.length;
    if (speed > _maxSpeed) {
      _velocity *= _maxSpeed / speed;
    }
    position += _velocity * dt;
  }

  void _updateLeaving(double dt) {
    final toTarget = _exitTarget - position;
    final dist = toTarget.length;
    if (dist > 0.5) {
      _velocity = toTarget / dist * _exitSpeed;
      position += _velocity * math.min(dt, dist / _exitSpeed);
    }
    if (position.length > home.length + _exitMargin) {
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
    } else if (_velocity.length2 > 0) {
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
