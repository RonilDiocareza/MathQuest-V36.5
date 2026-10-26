import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_mathquest/screens/classroom_quest_screen.dart';

void main() {
  Future<void> startQuest(WidgetTester tester) async {
    var attemptNumber = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: ClassroomQuestScreen(
          saveAttempt: (_) async {},
          attemptIdGenerator: () => 'test-attempt-${attemptNumber++}',
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('timeout on the first question restarts with a fresh timer',
      (tester) async {
    await startQuest(tester);

    await tester.pump(const Duration(seconds: 60));
    await tester.pump();

    expect(find.text('Level 1 of 3'), findsOneWidget);
    expect(find.text("Time's Up!"), findsOneWidget);

    await tester.tap(find.text('Try Again'));
    await tester.pump();

    expect(find.text('Level 1 of 3'), findsOneWidget);
    expect(find.text('01:00'), findsOneWidget);
    expect(find.text("Time's Up!"), findsNothing);
  });

  testWidgets('timeout on a later question resets question and answer state',
      (tester) async {
    await startQuest(tester);

    await tester.enterText(find.byType(TextFormField), '3/4');
    await tester.tap(find.text('Submit Answer'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Level 2 of 3'), findsOneWidget);

    await tester.enterText(find.byType(TextFormField), '2/5');
    await tester.tap(find.text('Submit Answer'));
    await tester.pump();

    await tester.pump(const Duration(seconds: 60));
    await tester.pump();

    expect(find.text("Time's Up!"), findsOneWidget);
    expect(find.text('Level 1 of 3'), findsOneWidget);

    await tester.tap(find.text('Try Again'));
    await tester.pump();

    expect(find.text('01:00'), findsOneWidget);
    expect(
      tester.widget<TextFormField>(find.byType(TextFormField)).controller!.text,
      isEmpty,
    );
  });
}
