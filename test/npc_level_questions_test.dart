import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_mathquest/game/npc_question.dart';
import 'package:flutter_mathquest/services/user_progress_service.dart';
import 'package:flutter_mathquest/worksheet_lesson_data.dart';

void main() {
  test('every level receives lesson-aligned questions with valid choices', () {
    for (var questionNumber = 1;
        questionNumber <= NpcQuestion.all.length;
        questionNumber++) {
      for (var level = 1; level <= 60; level++) {
        final question = NpcQuestion.forLevel(questionNumber, level);
        final moduleIndex = gameModeModuleIndexForLevel(level);
        final moduleId = worksheetModuleIds[moduleIndex];
        final moduleLessons = worksheetLessons
            .where((lesson) => lesson.moduleId == moduleId)
            .toList(growable: false);
        final worksheetIndex =
            ((level - gameModeModuleStartLevels[moduleIndex]) *
                        NpcQuestion.all.length +
                    questionNumber -
                    1) %
                moduleLessons.length;
        final worksheet = moduleLessons[worksheetIndex];
        expect(question.semester, worksheet.semester);
        expect(question.module, worksheet.topic);
        expect(question.lesson, worksheet.title);
        expect(question.topic, worksheet.topic);
        expect(question.choices, hasLength(3));
        expect(
          question.correctAnswerIndex,
          inInclusiveRange(0, question.choices.length - 1),
        );
        expect(
          question.choices.toSet(),
          hasLength(3),
          reason: question.lesson,
        );
      }
    }
  });

  test('Game Mode topics follow the requested 60-level module sequence', () {
    expect(gameModeModuleStartLevels, [1, 8, 15, 21, 26, 31, 36, 41]);
    expect(gameModeModuleEndLevels, [7, 14, 20, 25, 30, 35, 40, 60]);

    for (var level = 1; level <= 60; level++) {
      final moduleIndex = gameModeModuleIndexForLevel(level);
      for (var questionNumber = 1;
          questionNumber <= NpcQuestion.all.length;
          questionNumber++) {
        final question = NpcQuestion.forLevel(questionNumber, level);
        expect(
          worksheetModuleIndex(
            worksheetLessons.indexWhere(
                  (lesson) =>
                      lesson.title == question.lesson &&
                      lesson.topic == question.topic &&
                      lesson.question == question.prompt,
                ) +
                1,
          ),
          moduleIndex,
          reason: 'Level $level, NPC $questionNumber',
        );
      }
    }
  });

  test('question choices vary by session and preserve the answer key', () {
    for (var questionNumber = 1;
        questionNumber <= NpcQuestion.all.length;
        questionNumber++) {
      final first = NpcQuestion.forLevel(
        questionNumber,
        1,
        questionSeed: 0,
      );
      final second = NpcQuestion.forLevel(
        questionNumber,
        1,
        questionSeed: 1,
      );

      expect(second.lesson, first.lesson);
      expect(first.choices[first.correctAnswerIndex], isNotEmpty);
      expect(second.choices[second.correctAnswerIndex], isNotEmpty);
      expect(first.choices.toSet(), hasLength(3));
      expect(second.choices.toSet(), hasLength(3));
    }
  });

  test('all worksheet lessons have distinct, keyed question choices', () {
    expect(worksheetLessons, hasLength(67));
    for (final worksheet in worksheetLessons) {
      expect(worksheet.choices, hasLength(3), reason: worksheet.title);
      expect(
        worksheet.choices.toSet(),
        hasLength(3),
        reason: worksheet.title,
      );
      expect(
        worksheet.choices[worksheet.correctAnswerIndex],
        worksheet.correctAnswer,
        reason: worksheet.title,
      );
    }
  });

  test('representative worksheet answers follow the stated calculations', () {
    const expectedAnswers = <int, String>{
      1: '1/2',
      2: '0',
      3: '3 3/4',
      4: '2 3/4',
      5: '1',
      6: '1/2',
      7: '1/2',
      8: '7/8',
      9: '5/8',
      10: '3',
      11: '3',
      12: '1',
      13: '2',
      19: '0.60',
      20: '3.60',
      21: '8',
      22: '30',
      23: '45.6',
      24: '9',
      25: '25.00',
      26: '0.36',
      36: '190 km',
      37: '195 km',
      38: '22 square units',
      41: '52 square units',
      42: '36 square units',
      43: '96 square units',
      44: '56 square units',
      45: '62.8 square units',
      46: '75.36 square units',
      47: '50.24 square units',
      48: '4',
      52: '8',
      53: '-10',
      54: '2',
      55: '2',
      56: '2',
      57: '-2',
      58: '20',
      59: '-22',
      60: '2',
      61: '168',
      62: '195',
      63: '-224',
      64: '255',
      65: '18',
      66: '-19',
      67: '20',
    };

    for (final entry in expectedAnswers.entries) {
      expect(
        worksheetLessons[entry.key - 1].correctAnswer,
        entry.value,
        reason: worksheetLessons[entry.key - 1].title,
      );
    }
  });

  test('saved Level Question answer preserves the generated expression', () {
    const savedAnswer = LevelQuestionAnswer(
      firstOperand: 12,
      secondOperand: 12,
      operation: '+',
      correctAnswer: 24,
    );

    final restored = LevelQuestionAnswer.fromData(savedAnswer.toData());

    expect(restored.firstOperand, 12);
    expect(restored.secondOperand, 12);
    expect(restored.operation, '+');
    expect(restored.correctAnswer, 24);
    expect(
      () => LevelQuestionAnswer.fromData({
        ...savedAnswer.toData(),
        'correctAnswer': 25,
      }),
      throwsFormatException,
    );
  });

  test('NPC completion is isolated to its Game Mode level', () {
    final progress = UserProgress(
      completedLevels: const [],
      completedNpcQuestions: const [1, 2, 3, 4, 5, 6],
      completedNpcQuestionsByLevel: const {
        2: [1, 2],
        3: [1, 2, 3, 4, 5, 6],
      },
      unlockedLevels: 1,
      questAttempts: 0,
      maxUnlockedSubLevel: const {1: 1, 2: 1, 3: 1},
    );

    expect(progress.areNpcQuestionsCompletedForLevel(1), isTrue);
    expect(progress.currentNpcQuestionNumberForLevel(2), 3);
    expect(progress.areNpcQuestionsCompletedForLevel(3), isTrue);
    expect(progress.currentNpcQuestionNumberForLevel(4), 1);
    expect(progress.areNpcQuestionsCompletedForLevel(4), isFalse);
  });

  test('Game Mode topics unlock after the previous topic is complete', () {
    final firstTopicComplete = UserProgress(
      completedLevels: const [],
      completedNpcQuestions: const [],
      unlockedLevels: 1,
      questAttempts: 0,
      maxUnlockedSubLevel: const {},
      gameModeFinalScores: const {
        1: 10,
        2: 10,
        3: 10,
        4: 10,
        5: 10,
        6: 10,
        7: 10
      },
    );
    expect(firstTopicComplete.isGameModeTopicUnlocked(1), isTrue);
    expect(firstTopicComplete.isGameModeTopicUnlocked(7), isTrue);
    expect(firstTopicComplete.isGameModeTopicUnlocked(8), isTrue);
    expect(firstTopicComplete.isGameModeTopicUnlocked(9), isTrue);
    expect(firstTopicComplete.isGameModeTopicUnlocked(15), isFalse);

    final allTransitionsComplete = UserProgress(
      completedLevels: const [],
      completedNpcQuestions: const [],
      unlockedLevels: 1,
      questAttempts: 0,
      maxUnlockedSubLevel: const {},
      gameModeFinalScores: {
        for (var level = 1; level <= 40; level++) level: 0,
      },
    );
    for (final level in [8, 15, 21, 26, 31, 36, 41, 60]) {
      expect(
        allTransitionsComplete.isGameModeTopicUnlocked(level),
        isTrue,
        reason: 'Level $level should unlock after its prior topic is complete',
      );
    }
    expect(
      allTransitionsComplete.nextRequiredGameModeLevelForTopic(41),
      null,
    );

    final problemLevelsOnly = UserProgress(
      completedLevels: List.generate(40, (index) => index + 1),
      completedNpcQuestions: const [],
      unlockedLevels: 40,
      questAttempts: 0,
      maxUnlockedSubLevel: const {},
    );
    expect(problemLevelsOnly.isGameModeTopicUnlocked(41), isFalse);
    expect(problemLevelsOnly.nextRequiredGameModeLevelForTopic(41), 1);
  });

  test('badge progress counts completed NPC answers and rounds', () {
    final progress = UserProgress(
      completedLevels: const [1, 2],
      completedNpcQuestions: const [1, 2, 3, 4, 5, 6],
      completedNpcQuestionsByLevel: const {
        2: [1, 2, 3],
        3: [1, 2, 3, 4, 5, 6],
      },
      unlockedLevels: 2,
      questAttempts: 4,
      maxUnlockedSubLevel: const {1: 1, 2: 1, 3: 1},
    );

    expect(progress.completedNpcQuestionCount, 15);
    expect(progress.completedNpcRoundCount, 2);
  });

  test('badge progress avoids double-counting legacy NPC level one data', () {
    final progress = UserProgress(
      completedLevels: const [],
      completedNpcQuestions: const [1, 2, 3, 4, 5, 6],
      completedNpcQuestionsByLevel: const {
        1: [1, 2, 3, 4, 5, 6],
      },
      unlockedLevels: 1,
      questAttempts: 0,
      maxUnlockedSubLevel: const {1: 1, 2: 1, 3: 1},
    );

    expect(progress.completedNpcQuestionCount, 6);
    expect(progress.completedNpcRoundCount, 1);
  });
}
