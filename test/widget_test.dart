import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gitfight/ui/repo_entry.dart';

void main() {
  testWidgets('repo entry shows the launch button and submits the URL', (
    tester,
  ) async {
    String? submitted;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RepoEntry(
            error: ValueNotifier<String?>(null),
            launches: ValueNotifier<int?>(null),
            onSubmit: (url) => submitted = url,
          ),
        ),
      ),
    );

    expect(find.text('Git Fight'), findsOneWidget);
    await tester.tap(find.text('Launch'));
    expect(submitted, isNotNull);
  });
}
