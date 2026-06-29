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
       ) {
    _glowPaint
      ..color = color.withValues(alpha: 0.4)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);
    _corePaint.color = color;
  }

  final Vector2 target;
  final Color color;
  final void Function() onHit;

  static const _speed = 520.0;
  final Vector2 _velocity = Vector2.zero();
  final Paint _glowPaint = Paint();
  final Paint _corePaint = Paint();

  @override
  Future<void> onLoad() async {
    _velocity
      ..setFrom(target)
      ..sub(position)
      ..length = _speed;
  }

  @override
  void update(double dt) {
    super.update(dt);
    if (position.distanceTo(target) <= _velocity.length * dt) {
      onHit();
      removeFromParent();
      return;
    }
    position.addScaled(_velocity, dt);
  }

  @override
  void render(Canvas canvas) {
    final center = Offset(size.x / 2, size.y / 2);
    canvas.drawCircle(center, 6, _glowPaint);
    canvas.drawCircle(center, 3, _corePaint);
  }
}
