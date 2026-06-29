import 'dart:ui';

import 'package:flame/components.dart';

/// A projectile that flies from a shooter to a target and reports a hit.
class Bullet extends PositionComponent {
  Bullet({
    required Vector2 start,
    required this.target,
    required this.color,
    required this.onHit,
  }) : super(
         position: start.clone(),
         anchor: Anchor.center,
         size: Vector2.all(8),
       );

  final Vector2 target;
  final Color color;
  final void Function() onHit;

  static const _speed = 520.0;
  Vector2 _velocity = Vector2.zero();

  @override
  Future<void> onLoad() async {
    _velocity = (target - position)..length = _speed;
  }

  @override
  void update(double dt) {
    super.update(dt);
    final step = _velocity * dt;
    if (position.distanceTo(target) <= step.length) {
      onHit();
      removeFromParent();
      return;
    }
    position += step;
  }

  @override
  void render(Canvas canvas) {
    final center = Offset(size.x / 2, size.y / 2);
    canvas.drawCircle(
      center,
      6,
      Paint()
        ..color = color.withValues(alpha: 0.4)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
    );
    canvas.drawCircle(center, 3, Paint()..color = color);
  }
}
