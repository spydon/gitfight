import 'package:flutter/material.dart';
import 'package:gitfight/game/committer.dart';
import 'package:gitfight/game/git_fight_game.dart';
import 'package:url_launcher/url_launcher.dart';

/// On-screen overlay shown during playback: the date, progress, the
/// leaderboard and a speed control.
class Hud extends StatelessWidget {
  const Hud({
    required this.game,
    required this.onRestart,
    required this.onGoLive,
    super.key,
  });

  final GitFightGame game;
  final VoidCallback onRestart;
  final VoidCallback onGoLive;

  static const _months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];

  String _formatDate(DateTime date) =>
      '${date.day} ${_months[date.month - 1]} ${date.year}';

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [_datePanel(), const Spacer(), _leaderboard()],
            ),
            const Spacer(),
            _controls(),
          ],
        ),
      ),
    );
  }

  Widget _panel({required Widget child}) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
    decoration: BoxDecoration(
      color: const Color(0xBB0B1020),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: const Color(0x552C5A82)),
    ),
    child: child,
  );

  Widget _datePanel() => _panel(
    child: ValueListenableBuilder<DateTime?>(
      valueListenable: game.currentDate,
      builder: (_, date, _) => Text(
        date == null ? '' : _formatDate(date),
        style: const TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w600,
          color: Color(0xFFEAF6FF),
        ),
      ),
    ),
  );

  Widget _leaderboard() => _panel(
    child: ValueListenableBuilder<List<Committer>>(
      valueListenable: game.leaderboard,
      builder: (_, board, _) {
        if (board.isEmpty) {
          return const SizedBox.shrink();
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'TOP COMMITTERS',
              style: TextStyle(
                fontSize: 11,
                letterSpacing: 1.2,
                color: Color(0xFF9FB3C8),
              ),
            ),
            const SizedBox(height: 6),
            for (final c in board) _committerRow(c),
          ],
        );
      },
    ),
  );

  Widget _committerRow(Committer c) {
    final profileUrl = c.profileUrl;
    final clickable = profileUrl != null;
    final row = Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(width: 10, height: 10, color: c.color),
          const SizedBox(width: 8),
          SizedBox(
            width: 150,
            child: Text(
              c.displayName,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: const Color(0xFFEAF6FF),
                decoration: clickable ? TextDecoration.underline : null,
                decorationColor: const Color(0x66EAF6FF),
              ),
            ),
          ),
          Text(
            '${c.score}',
            style: const TextStyle(
              color: Color(0xFFFFD166),
              fontWeight: FontWeight.bold,
            ),
          ),
          if (clickable) ...[
            const SizedBox(width: 6),
            const Icon(Icons.open_in_new, size: 12, color: Color(0xFF9FB3C8)),
          ],
        ],
      ),
    );
    if (!clickable) {
      return row;
    }
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () => launchUrl(
          Uri.parse(profileUrl),
          mode: LaunchMode.externalApplication,
        ),
        child: row,
      ),
    );
  }

  Widget _controls() => _panel(
    child: ValueListenableBuilder<bool>(
      valueListenable: game.live,
      builder: (_, live, _) => live ? _liveControls() : _replayControls(),
    ),
  );

  Widget _replayControls() => Wrap(
    crossAxisAlignment: WrapCrossAlignment.center,
    spacing: 14,
    runSpacing: 8,
    children: [
      const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.play_arrow, size: 18, color: Color(0xFF9FB3C8)),
          SizedBox(width: 6),
          Text('Replaying history', style: TextStyle(color: Color(0xFF9FB3C8))),
        ],
      ),
      SizedBox(
        width: 160,
        child: ValueListenableBuilder<double>(
          valueListenable: game.progress,
          builder: (_, value, _) => ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(value: value, minHeight: 6),
          ),
        ),
      ),
      Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('Speed', style: TextStyle(color: Color(0xFF9FB3C8))),
          const SizedBox(width: 8),
          for (final s in const [0.5, 1.0, 2.0, 4.0, 10.0]) _speedButton(s),
        ],
      ),
      OutlinedButton.icon(
        onPressed: onGoLive,
        icon: const Icon(Icons.sensors, size: 18),
        label: const Text('Go live'),
      ),
      IconButton(
        tooltip: 'New repository',
        onPressed: onRestart,
        icon: const Icon(Icons.refresh),
      ),
    ],
  );

  Widget _liveControls() => Row(
    children: [
      Container(
        width: 10,
        height: 10,
        decoration: const BoxDecoration(
          color: Color(0xFFFF5470),
          shape: BoxShape.circle,
        ),
      ),
      const SizedBox(width: 8),
      const Text(
        'LIVE',
        style: TextStyle(
          color: Color(0xFFFF5470),
          fontWeight: FontWeight.bold,
          letterSpacing: 1.2,
        ),
      ),
      const SizedBox(width: 12),
      const Expanded(
        child: Text(
          'Watching for new commits as they land',
          style: TextStyle(color: Color(0xFF9FB3C8)),
        ),
      ),
      IconButton(
        tooltip: 'New repository',
        onPressed: onRestart,
        icon: const Icon(Icons.refresh),
      ),
    ],
  );

  Widget _speedButton(double s) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 2),
    child: OutlinedButton(
      onPressed: () => game.speed = s,
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        minimumSize: Size.zero,
      ),
      child: Text('${s}x'),
    ),
  );
}
