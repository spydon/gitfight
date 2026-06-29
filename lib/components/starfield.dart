import 'dart:math' as math;
import 'dart:ui';

import 'package:flame/components.dart';

/// A static, deterministic star backdrop drawn behind the world.
class Starfield extends Component with HasGameReference {
  Starfield({this.starCount = 220});

  final int starCount;
  final _random = math.Random(42);
  late final List<_Star> _stars;

  final Paint _backgroundPaint = Paint()..color = const Color(0xFF05060D);
  final Paint _starPaint = Paint();

  @override
  Future<void> onLoad() async {
    _stars = List.generate(starCount, (_) {
      final brightness = _random.nextDouble() * 0.6 + 0.2;
      return _Star(
        Offset(_random.nextDouble(), _random.nextDouble()),
        _random.nextDouble() * 1.4 + 0.3,
        const Color(0xFFFFFFFF).withValues(alpha: brightness),
      );
    });
  }

  @override
  void render(Canvas canvas) {
    final size = game.size;
    canvas.drawRect(Offset.zero & size.toSize(), _backgroundPaint);
    for (final star in _stars) {
      _starPaint.color = star.color;
      canvas.drawCircle(
        Offset(star.fraction.dx * size.x, star.fraction.dy * size.y),
        star.radius,
        _starPaint,
      );
    }
  }
}

class _Star {
  _Star(this.fraction, this.radius, this.color);

  final Offset fraction;
  final double radius;
  final Color color;
}
