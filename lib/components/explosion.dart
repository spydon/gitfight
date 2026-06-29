import 'dart:ui';

import 'package:flame/components.dart';

/// A short expanding flash where a bullet lands.
class Explosion extends PositionComponent {
  Explosion({required super.position, required this.color, this.maxRadius = 26})
    : super(anchor: Anchor.center);

  final Color color;
  final double maxRadius;

  static const _lifetime = 0.4;
  double _age = 0;

  @override
  void update(double dt) {
    super.update(dt);
    _age += dt;
    if (_age >= _lifetime) {
      removeFromParent();
    }
  }

  @override
  void render(Canvas canvas) {
    final t = (_age / _lifetime).clamp(0.0, 1.0);
    canvas.drawCircle(
      Offset.zero,
      maxRadius * t,
      Paint()
        ..color = color.withValues(alpha: (1 - t) * 0.8)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3 * (1 - t),
    );
    canvas.drawCircle(
      Offset.zero,
      maxRadius * t * 0.5,
      Paint()..color = color.withValues(alpha: (1 - t) * 0.5),
    );
  }
}
