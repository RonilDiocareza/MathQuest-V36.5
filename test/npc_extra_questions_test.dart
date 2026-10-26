import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_mathquest/game/math_world_game.dart';
import 'package:flutter_mathquest/game/npc_question.dart';
import 'package:flutter_mathquest/worksheet_lesson_data.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});

  test('each NPC gets ten unique extra questions from its level module', () {
    for (var level = 1; level <= 60; level++) {
      final moduleIndex = gameModeModuleIndexForLevel(level);
      for (var npcNumber = 1;
          npcNumber <= NpcQuestion.all.length;
          npcNumber++) {
        final extras = NpcQuestion.extraQuestionsForLevel(npcNumber, level);

        expect(extras, hasLength(10), reason: 'Level $level, NPC $npcNumber');
        expect(
          extras.map((question) => question.id).toSet(),
          hasLength(10),
          reason: 'Level $level, NPC $npcNumber',
        );
        expect(
          extras.map((question) => question.prompt).toSet(),
          hasLength(10),
          reason: 'Level $level, NPC $npcNumber',
        );
        for (final question in extras) {
          expect(question.isExtra, isTrue);
          expect(question.questionNumber, npcNumber);
          expect(question.moduleId, worksheetModuleIds[moduleIndex]);
          expect(question.topic, worksheetModuleNames[moduleIndex]);
          expect(question.choices, hasLength(3));
          expect(question.choices.toSet(), hasLength(3));
          expect(
            question.choices[question.correctAnswerIndex],
            isNotEmpty,
          );
        }
      }
    }
  });

  test('question cycles show originals then extras once before resetting', () {
    final original = NpcQuestion.forLevel(1, 1, questionSeed: 1);
    final extras = NpcQuestion.extraQuestionsForLevel(1, 1);
    final pool = [original, ...extras];
    final cycle = NpcQuestionCycle();

    expect(cycle.nextForNpc(pool).isExtra, isFalse);
    for (var index = 0; index < extras.length; index++) {
      expect(cycle.nextForNpc(pool).id, extras[index].id);
      expect(cycle.shownQuestionIdsForNpc(1), hasLength(index + 2));
    }
    expect(cycle.nextForNpc(pool).id, original.id);
    expect(cycle.shownQuestionIdsForNpc(1), {original.id});
  });

  test('each NPC keeps an independent question history', () {
    final firstNpcPool = [
      NpcQuestion.forLevel(1, 1),
      ...NpcQuestion.extraQuestionsForLevel(1, 1),
    ];
    final secondNpcPool = [
      NpcQuestion.forLevel(2, 1),
      ...NpcQuestion.extraQuestionsForLevel(2, 1),
    ];
    final cycle = NpcQuestionCycle();

    expect(cycle.nextForNpc(firstNpcPool).questionNumber, 1);
    expect(cycle.shownQuestionIdsForNpc(2), isEmpty);
    expect(cycle.nextForNpc(secondNpcPool).questionNumber, 2);
    expect(cycle.shownQuestionIdsForNpc(1), hasLength(1));
    expect(cycle.shownQuestionIdsForNpc(2), hasLength(1));
  });

  test('restored history resumes at the next unused question', () {
    final original = NpcQuestion.forLevel(1, 1);
    final extras = NpcQuestion.extraQuestionsForLevel(1, 1);
    final pool = [original, ...extras];
    final cycle = NpcQuestionCycle();
    cycle
      ..nextForNpc(pool)
      ..nextForNpc(pool);

    final restoredCycle = NpcQuestionCycle()
      ..restoreShownQuestionIds(
        1,
        [...cycle.shownQuestionIdsForNpc(1), 'stale-question'],
        validQuestionIds: pool.map((question) => question.id).toSet(),
      );

    expect(restoredCycle.nextForNpc(pool).id, extras[1].id);
    expect(restoredCycle.shownQuestionIdsForNpc(1), hasLength(3));
  });

  test('an NPC keeps its active question until explicitly advanced', () {
    final game = MathWorldGame(
      correctAnswer: 0,
      problem: 'test',
      level: 1,
    );
    final original = NpcQuestion.forLevel(1, 1);
    final currentQuestion = game.questionForNpc(original);

    expect(game.questionForNpc(original).id, currentQuestion.id);

    final nextQuestion = game.nextNpcQuestionAfterIncorrect(1);
    expect(nextQuestion.id, isNot(currentQuestion.id));
    expect(game.questionForNpc(original).id, nextQuestion.id);
  });
}
