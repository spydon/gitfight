import 'dart:math' as math;
import 'dart:ui';

import 'package:flame/components.dart';

/// The big planet in the centre that lone committers fire at.
class Planet extends PositionComponent {
  Planet({required this.radius, super.position})
    : super(anchor: Anchor.center, size: Vector2.all(radius * 2));

  final double radius;

  double _spin = 0;
  double _hitPulse = 0;

  static const _glowColor = Color(0xFF3A6EA5);

  late final Paint _bodyPaint;
  late final Paint _bandPaint;
  late final Shader _restingGlow;
  late final Rect _bandRect;
  final Paint _glowPaint = Paint();

  void registerHit() => _hitPulse = 1;

  @override
  Future<void> onLoad() async {
    final center = Offset(radius, radius);
    _bodyPaint = Paint()
      ..shader = Gradient.radial(
        Offset(radius * 0.7, radius * 0.7),
        radius * 1.3,
        const [Color(0xFF6FB1E0), Color(0xFF1B3A5B)],
      );
    _bandPaint = Paint()
      ..color = const Color(0xFF234A6E).withValues(alpha: 0.5)
      ..style = PaintingStyle.stroke
      ..strokeWidth = radius * 0.12;
    _restingGlow = Gradient.radial(center, radius * 1.4, [
      _glowColor.withValues(alpha: 0.55),
      _glowColor.withValues(alpha: 0),
    ]);
    _glowPaint.shader = _restingGlow;
    _bandRect = Rect.fromCircle(center: center, radius: radius * 0.85);
  }

  @override
  void update(double dt) {
    super.update(dt);
    _spin += dt * 0.3;
    if (_hitPulse > 0) {
      _hitPulse = math.max(0, _hitPulse - dt * 2);
    }
  }

  @override
  void render(Canvas canvas) {
    final center = Offset(radius, radius);
    double glowRadius;
    if (_hitPulse > 0) {
      // Rebuild the glow only during the brief hit flash.
      glowRadius = radius * (1.4 + _hitPulse * 0.25);
      _glowPaint.shader = Gradient.radial(center, glowRadius, [
        _glowColor.withValues(alpha: 0.55 + _hitPulse * 0.3),
        _glowColor.withValues(alpha: 0),
      ]);
    } else {
      glowRadius = radius * 1.4;
      _glowPaint.shader = _restingGlow;
    }
    canvas.drawCircle(center, glowRadius, _glowPaint);
    canvas.drawCircle(center, radius, _bodyPaint);

    for (var i = 0; i < 3; i++) {
      canvas.drawArc(_bandRect, _spin + i, 1.2, false, _bandPaint);
    }
  }
}
