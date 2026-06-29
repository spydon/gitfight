import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gitfight/app.dart';
import 'package:gitfight/game/git_fight_game.dart';
import 'package:gitfight/git/git_commit.dart';
import 'package:gitfight/git/git_service.dart';
import 'package:gitfight/git/stats_service.dart';

class _FakeGitService extends GitService {
  @override
  Future<List<GitCommit>> fetchHistory(String rawUrl) async => [
    GitCommit(
      displayName: 'alice',
      identityKey: 'alice@example.com',
      date: DateTime.utc(2024),
    ),
    GitCommit(
      displayName: 'bob',
      identityKey: 'bob@example.com',
      date: DateTime.utc(2024, 1, 2),
    ),
  ];

  @override
  Future<List<GitCommit>> fetchSince(String rawUrl, DateTime since) async => [];
}

class _FakeStatsService extends StatsService {
  @override
  Future<int?> launches() async => null;
}

void main() {
  testWidgets('entry modal closes after pressing Launch', (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: GameScreen(
          gameFactory: () => GitFightGame(
            service: _FakeGitService(),
            stats: _FakeStatsService(),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Git Fight'), findsOneWidget);

    await tester.tap(find.text('Launch'));
    // Let the fetch future resolve and overlays update.
    await tester.pump();
    await tester.pump();

    expect(find.text('Git Fight'), findsNothing);
  });
}
