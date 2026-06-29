import 'dart:math' as math;
import 'dart:ui';

import 'package:flame/components.dart';

/// A static, deterministic star backdrop drawn behind the world.
class Starfield extends Component with HasGameReference {
  Starfield({this.starCount = 220});

  final int starCount;
  final _random = math.Random(42);
  late final List<_Star> _stars;

  @override
  Future<void> onLoad() async {
    _stars = List.generate(
      starCount,
      (_) => _Star(
        Offset(_random.nextDouble(), _random.nextDouble()),
        _random.nextDouble() * 1.4 + 0.3,
        _random.nextDouble() * 0.6 + 0.2,
      ),
    );
  }

  @override
  void render(Canvas canvas) {
    final size = game.size;
    canvas.drawRect(
      Offset.zero & size.toSize(),
      Paint()..color = const Color(0xFF05060D),
    );
    final paint = Paint()..color = const Color(0xFFFFFFFF);
    for (final star in _stars) {
      paint.color = const Color(0xFFFFFFFF).withValues(alpha: star.brightness);
      canvas.drawCircle(
        Offset(star.fraction.dx * size.x, star.fraction.dy * size.y),
        star.radius,
        paint,
      );
    }
  }
}

class _Star {
  _Star(this.fraction, this.radius, this.brightness);

  final Offset fraction;
  final double radius;
  final double brightness;
}
