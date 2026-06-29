import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:gitfight/game/git_fight_game.dart';
import 'package:gitfight/ui/hud.dart';
import 'package:gitfight/ui/repo_entry.dart';

class GameScreen extends StatelessWidget {
  const GameScreen({super.key, this.gameFactory});

  /// Injectable for testing; defaults to creating a real [GitFightGame].
  final GitFightGame Function()? gameFactory;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: GameWidget<GitFightGame>.controlled(
        gameFactory: gameFactory ?? GitFightGame.new,
        initialActiveOverlays: const [GitFightGame.entryOverlay],
        overlayBuilderMap: {
          GitFightGame.entryOverlay: (_, game) => RepoEntry(
            error: game.error,
            launches: game.launches,
            onSubmit: game.submit,
          ),
          GitFightGame.loadingOverlay: (_, _) => const _LoadingOverlay(),
          GitFightGame.hudOverlay: (_, game) =>
              Hud(game: game, onRestart: game.restart, onGoLive: game.goLive),
        },
      ),
    );
  }
}

class _LoadingOverlay extends StatelessWidget {
  const _LoadingOverlay();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(),
          SizedBox(height: 16),
          Text(
            'Fetching commit history...',
            style: TextStyle(color: Color(0xFFEAF6FF), fontSize: 16),
          ),
        ],
      ),
    );
  }
}
