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

  void registerHit() => _hitPulse = 1;

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
    final glowRadius = radius * (1.4 + _hitPulse * 0.25);
    final glow = Paint()
      ..shader = Gradient.radial(center, glowRadius, [
        const Color(0xFF3A6EA5).withValues(alpha: 0.55 + _hitPulse * 0.3),
        const Color(0x003A6EA5),
      ]);
    canvas.drawCircle(center, glowRadius, glow);

    final body = Paint()
      ..shader = Gradient.radial(
        Offset(radius * 0.7, radius * 0.7),
        radius * 1.3,
        [const Color(0xFF6FB1E0), const Color(0xFF1B3A5B)],
      );
    canvas.drawCircle(center, radius, body);

    // A couple of rotating bands so the planet feels alive.
    final band = Paint()
      ..color = const Color(0xFF2C5A82).withValues(alpha: 0.6)
      ..style = PaintingStyle.stroke
      ..strokeWidth = radius * 0.12;
    for (var i = 0; i < 3; i++) {
      final offset = math.sin(_spin + i) * radius * 0.4;
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius * 0.85),
        _spin + i,
        1.2,
        false,
        band..color = const Color(0xFF234A6E).withValues(alpha: 0.5),
      );
      canvas.save();
      canvas.translate(0, offset);
      canvas.restore();
    }
  }
}
