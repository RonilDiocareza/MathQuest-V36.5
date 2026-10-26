import 'package:flame/components.dart';
import 'dart:math';
import '../worksheet_lesson_data.dart';

class QuestionNpcPlacement {
  static const double physicalCollisionRadius = 8;

  final int level;
  final int questionNumber;
  final String questionId;
  final String topic;
  final Vector2 position;
  final String spriteAssetPath;
  final double collisionRadius;
  final int questionSeed;

  const QuestionNpcPlacement({
    this.level = 1,
    this.questionNumber = 1,
    required this.questionId,
    required this.topic,
    required this.position,
    this.spriteAssetPath = 'assets/images/npcs/np1.png',
    this.collisionRadius = physicalCollisionRadius,
    this.questionSeed = 0,
  });
}

class NpcQuestion {
  final String id;
  final int questionNumber;
  final String semester;
  final String module;
  final String moduleId;
  final String lesson;
  final String topic;
  final String prompt;
  final List<String> choices;
  final int correctAnswerIndex;
  final bool isExtra;

  const NpcQuestion({
    required this.id,
    this.questionNumber = 1,
    this.semester = '',
    this.module = '',
    this.moduleId = '',
    this.lesson = '',
    required this.topic,
    required this.prompt,
    required this.choices,
    required this.correctAnswerIndex,
    this.isExtra = false,
  });

  NpcQuestion withTopic(String topic) => NpcQuestion(
        id: id,
        questionNumber: questionNumber,
        semester: semester,
        module: module,
        moduleId: moduleId,
        lesson: lesson,
        topic: topic,
        prompt: prompt,
        choices: choices,
        correctAnswerIndex: correctAnswerIndex,
        isExtra: isExtra,
      );

  static final List<NpcQuestion> all = List.generate(
    6,
    (index) => _questionForWorksheet(worksheetLessons[index], index + 1, 0),
    growable: false,
  );

  static String _fraction(int numerator, int denominator) {
    var a = numerator.abs();
    var b = denominator.abs();
    while (b != 0) {
      final remainder = a % b;
      a = b;
      b = remainder;
    }
    final divisor = a == 0 ? 1 : a;
    final sign = numerator * denominator < 0 ? '-' : '';
    final reducedNumerator = numerator.abs() ~/ divisor;
    final reducedDenominator = denominator.abs() ~/ divisor;
    return reducedDenominator == 1
        ? '$sign$reducedNumerator'
        : '$sign$reducedNumerator/$reducedDenominator';
  }

  static String _decimal(int cents) =>
      '${cents ~/ 100}.${(cents % 100).toString().padLeft(2, '0')}';

  // Tiled-world coordinates for the four building entrances, central shrine,
  // and final NPC on the southern road near the map edge.
  static const List<(double, double)> _mapNpcPositions = [
    (535, 285),
    (1062, 340),
    (397, 553),
    (651, 584),
    (1120, 550),
    (468, 1016),
  ];

  static const List<String> _npcSpritePaths = [
    'assets/images/npcs/np1.png',
    'assets/images/npcs/npc2.png',
    'assets/images/npcs/npc3.png',
    'assets/images/npcs/npc4.png',
    'assets/images/npcs/npc5.png',
    'assets/images/npcs/npc6.png',
  ];

  static List<QuestionNpcPlacement> createNpcPlacements({
    required Vector2 playerSpawn,
    required bool Function(Vector2 center, double radius) canOccupy,
    int level = 1,
    Random? random,
  }) {
    final placements = <QuestionNpcPlacement>[];

    bool isClear(Vector2 feetPosition) {
      final radius = QuestionNpcPlacement.physicalCollisionRadius;
      final center = Vector2(feetPosition.x, feetPosition.y - radius);
      if (!canOccupy(center, radius)) return false;

      final playerFeet = Vector2(playerSpawn.x, playerSpawn.y + 21);
      if (center.distanceTo(playerFeet) < radius * 2 + 4) return false;

      return placements.every((placement) {
        final otherCenter = Vector2(
          placement.position.x,
          placement.position.y - placement.collisionRadius,
        );
        return center.distanceTo(otherCenter) >=
            radius + placement.collisionRadius + 4;
      });
    }

    for (var index = 0; index < _mapNpcPositions.length; index++) {
      final (x, y) = _mapNpcPositions[index];
      final position = Vector2(x, y);
      if (!isClear(position)) {
        throw StateError(
          'Question NPC ${index + 1} cannot be placed safely at its building door.',
        );
      }
      final questionSeed = random?.nextInt(1 << 31) ?? 0;
      placements.add(_placementAt(index, position, level, questionSeed));
    }

    if (placements.length != all.length) {
      throw StateError(
        'Only ${placements.length} of ${all.length} NPCs have a safe map location.',
      );
    }

    return placements;
  }

  static QuestionNpcPlacement _placementAt(
    int index,
    Vector2 position,
    int level,
    int questionSeed,
  ) {
    final question = forLevel(index + 1, level, questionSeed: questionSeed);
    return QuestionNpcPlacement(
      level: level,
      questionNumber: question.questionNumber,
      questionId: question.id,
      topic: question.topic,
      position: position,
      spriteAssetPath: _npcSpritePaths[index],
      questionSeed: questionSeed,
    );
  }

  static NpcQuestion? forPlacement(QuestionNpcPlacement placement) {
    final original = all.firstWhere(
      (question) =>
          question.id == placement.questionId &&
          question.questionNumber == placement.questionNumber,
      orElse: () => all.first,
    );
    if (original.id != placement.questionId ||
        original.questionNumber != placement.questionNumber) {
      return null;
    }
    return forLevel(
      placement.questionNumber,
      placement.level,
      questionSeed: placement.questionSeed,
    ).withTopic(placement.topic);
  }

  static NpcQuestion forLevel(
    int questionNumber,
    int level, {
    int? questionSeed,
  }) {
    if (questionNumber < 1 || questionNumber > all.length) {
      throw ArgumentError.value(questionNumber, 'questionNumber');
    }
    if (level < 1 || level > 60) {
      throw ArgumentError.value(level, 'level');
    }
    final moduleIndex = gameModeModuleIndexForLevel(level);
    final moduleId = worksheetModuleIds[moduleIndex];
    final moduleLessons = worksheetLessons
        .where((lesson) => lesson.moduleId == moduleId)
        .toList(growable: false);
    final lessonIndex =
        ((level - gameModeModuleStartLevels[moduleIndex]) * all.length +
                questionNumber -
                1) %
            moduleLessons.length;
    final seed = questionSeed ?? level * 101 + questionNumber;
    return _questionForWorksheet(
      moduleLessons[lessonIndex],
      questionNumber,
      seed,
    );
  }

  static List<NpcQuestion> extraQuestionsForLevel(
    int npcNumber,
    int level,
  ) {
    if (npcNumber < 1 || npcNumber > all.length) {
      throw ArgumentError.value(npcNumber, 'npcNumber');
    }
    if (level < 1 || level > 60) {
      throw ArgumentError.value(level, 'level');
    }

    final moduleIndex = gameModeModuleIndexForLevel(level);
    final moduleId = worksheetModuleIds[moduleIndex];
    final topic = worksheetModuleNames[moduleIndex];
    final semester = worksheetModuleSemesters[moduleIndex];
    return List.generate(
      10,
      (index) => _extraQuestion(
        npcNumber: npcNumber,
        level: level,
        moduleIndex: moduleIndex,
        moduleId: moduleId,
        topic: topic,
        semester: semester,
        questionIndex: index + 1,
      ),
      growable: false,
    );
  }

  static NpcQuestion _extraQuestion({
    required int npcNumber,
    required int level,
    required int moduleIndex,
    required String moduleId,
    required String topic,
    required String semester,
    required int questionIndex,
  }) {
    final seed = npcNumber * 17 + questionIndex * 11;
    late String prompt;
    late String answer;
    late List<String> distractors;

    switch (moduleIndex) {
      case 0:
        final denominator = 8 + questionIndex;
        final firstNumerator = denominator ~/ 2 + (seed % (denominator ~/ 3));
        final secondNumerator = 1 + (seed % (firstNumerator - 1));
        final subtract = questionIndex.isEven;
        final result = subtract
            ? firstNumerator - secondNumerator
            : firstNumerator + secondNumerator;
        final operation = subtract ? '−' : '+';
        prompt =
            'Calculate $firstNumerator/$denominator $operation $secondNumerator/$denominator.';
        answer = _fraction(result, denominator);
        distractors = [
          _fraction(result + 1, denominator),
          _fraction(result + 2, denominator),
        ];
      case 1:
        final firstNumerator = 1 + seed % 6;
        final firstDenominator = 2 + seed % 5;
        final secondNumerator = 2 + (seed + questionIndex) % 5;
        final secondDenominator = 2 + (seed + 2 * questionIndex) % 5;
        final divide = questionIndex.isEven;
        final numerator = divide
            ? firstNumerator * secondDenominator
            : firstNumerator * secondNumerator;
        final denominator = divide
            ? firstDenominator * secondNumerator
            : firstDenominator * secondDenominator;
        final operation = divide ? '÷' : '×';
        prompt =
            'Calculate $firstNumerator/$firstDenominator $operation $secondNumerator/$secondDenominator.';
        answer = _fraction(numerator, denominator);
        distractors = [
          _fraction(numerator + 1, denominator),
          _fraction(numerator + 2, denominator),
        ];
      case 2:
        final firstCents = 100 + seed * 20;
        final secondCents = 50 + (seed % 7) * 10;
        late int resultCents;
        late String operation;
        switch (questionIndex % 4) {
          case 0:
            operation = '+';
            resultCents = firstCents + secondCents;
          case 1:
            operation = '−';
            resultCents = firstCents - secondCents;
          case 2:
            operation = '×';
            resultCents = firstCents * 50 ~/ 100;
          default:
            operation = '÷';
            resultCents = firstCents * 2;
        }
        final secondOperand = operation == '×'
            ? '0.50'
            : operation == '÷'
                ? '0.50'
                : _decimal(secondCents);
        prompt = 'Calculate ${_decimal(firstCents)} $operation $secondOperand.';
        answer = _decimal(resultCents);
        distractors = [
          _decimal(resultCents + 10),
          _decimal(resultCents + 20),
        ];
      case 3:
        const facts = <(String, String, String, int)>[
          ('cube', 'faces', '6', 6),
          ('cube', 'edges', '12', 12),
          ('cube', 'vertices', '8', 8),
          ('triangular prism', 'faces', '5', 5),
          ('triangular prism', 'edges', '9', 9),
          ('triangular prism', 'vertices', '6', 6),
          ('square pyramid', 'faces', '5', 5),
          ('square pyramid', 'vertices', '5', 5),
          ('cylinder', 'circular bases', '2', 2),
          ('cone', 'vertices', '1', 1),
        ];
        final (shape, property, value, count) =
            facts[(questionIndex - 1) % facts.length];
        prompt = 'How many $property does a $shape have?';
        answer = value;
        distractors = ['${count + 1}', '${count + 2}'];
      case 4:
        final speed = 20 + seed * 5;
        final time = 2 + questionIndex % 5;
        final distance = speed * time;
        switch (questionIndex % 3) {
          case 0:
            prompt = 'A vehicle travels at $speed km/h for $time hours. '
                'How far does it travel?';
            answer = '$distance km';
            distractors = [
              '${distance + speed} km',
              '${distance + 2 * speed} km'
            ];
          case 1:
            prompt = 'A vehicle travels $distance km in $time hours. '
                'What is its average speed?';
            answer = '$speed km/h';
            distractors = ['${speed + 5} km/h', '${speed + 10} km/h'];
          default:
            prompt = 'A vehicle travels $distance km at $speed km/h. '
                'How long does the trip take?';
            answer = '$time hours';
            distractors = ['${time + 1} hours', '${time + 2} hours'];
        }
      case 5:
        switch (questionIndex % 3) {
          case 0:
            final length = 4 + seed % 9;
            final width = 3 + (seed + questionIndex) % 7;
            final area = length * width;
            prompt = 'A rectangle is $length units long and $width units wide. '
                'What is its area?';
            answer = '$area square units';
            distractors = [
              '${area + 1} square units',
              '${area + 2} square units',
            ];
          case 1:
            final side = 2 + seed % 8;
            final area = 6 * side * side;
            prompt = 'What is the surface area of a cube with side length '
                '$side units?';
            answer = '$area square units';
            distractors = [
              '${area + side} square units',
              '${area + 2 * side} square units',
            ];
          default:
            final length = 2 + seed % 5;
            final width = 3 + questionIndex % 4;
            final height = 2 + (seed + questionIndex) % 3;
            final area =
                2 * (length * width + length * height + width * height);
            prompt = 'What is the surface area of a rectangular prism with '
                'length $length, width $width, and height $height units?';
            answer = '$area square units';
            distractors = [
              '${area + 1} square units',
              '${area + 2} square units',
            ];
        }
      case 6:
        final coinCount = questionIndex + 1;
        final outcomes = 1 << coinCount;
        prompt = 'How many different outcomes are possible when tossing '
            '$coinCount coins?';
        answer = '$outcomes';
        distractors = ['${outcomes + 1}', '${outcomes + 2}'];
      case 7:
        final first = 2 + seed % 9;
        final second = 2 + (seed + questionIndex) % 7;
        switch (questionIndex % 4) {
          case 0:
            prompt = 'Calculate -$first + $second.';
            answer = '${-first + second}';
          case 1:
            prompt = 'Calculate $first - (-$second).';
            answer = '${first + second}';
          case 2:
            prompt = 'Calculate -$first × $second.';
            answer = '${-first * second}';
          default:
            prompt = 'Calculate -${first * second} ÷ $second.';
            answer = '${-first}';
        }
        final result = int.parse(answer);
        distractors = ['${result + 1}', '${result - 1}'];
      default:
        throw RangeError.index(moduleIndex, worksheetModuleIds);
    }

    final choices = [answer, ...distractors]
      ..shuffle(Random(level * 1009 + npcNumber * 101 + questionIndex));
    return NpcQuestion(
      id: 'npc_${npcNumber}_extra_${questionIndex}_$moduleId',
      questionNumber: npcNumber,
      semester: semester,
      module: topic,
      moduleId: moduleId,
      lesson: '$topic practice $questionIndex',
      topic: topic,
      prompt: prompt,
      choices: choices,
      correctAnswerIndex: choices.indexOf(answer),
      isExtra: true,
    );
  }

  static NpcQuestion _questionForWorksheet(
    WorksheetLesson lesson,
    int questionNumber,
    int choiceSeed,
  ) {
    final choices = [...lesson.choices]..shuffle(Random(choiceSeed));
    return NpcQuestion(
      id: 'npc_question_$questionNumber',
      questionNumber: questionNumber,
      semester: lesson.semester,
      module: lesson.topic,
      moduleId: lesson.moduleId,
      lesson: lesson.title,
      topic: lesson.topic,
      prompt: lesson.question,
      choices: choices,
      correctAnswerIndex: choices.indexOf(lesson.correctAnswer),
    );
  }
}

class NpcQuestionCycle {
  final Map<int, Set<String>> _shownQuestionIdsByNpc = {};

  NpcQuestion nextForNpc(List<NpcQuestion> questions) {
    if (questions.isEmpty) {
      throw ArgumentError.value(questions, 'questions', 'Must not be empty.');
    }

    final npcNumber = questions.first.questionNumber;
    if (questions.any((question) => question.questionNumber != npcNumber)) {
      throw ArgumentError.value(
        questions,
        'questions',
        'A question cycle must belong to one NPC.',
      );
    }
    if (questions.map((question) => question.id).toSet().length !=
        questions.length) {
      throw ArgumentError.value(
        questions,
        'questions',
        'A question cycle cannot contain duplicate IDs.',
      );
    }

    final shown = _shownQuestionIdsByNpc.putIfAbsent(npcNumber, () => {});
    NpcQuestion? next;
    for (final question in questions) {
      if (!shown.contains(question.id)) {
        next = question;
        break;
      }
    }
    if (next == null) {
      shown.clear();
      next = questions.first;
    }
    shown.add(next.id);
    return next;
  }

  Set<String> shownQuestionIdsForNpc(int npcNumber) =>
      Set.unmodifiable(_shownQuestionIdsByNpc[npcNumber] ?? const <String>{});

  void restoreShownQuestionIds(
    int npcNumber,
    Iterable<String> questionIds, {
    required Set<String> validQuestionIds,
  }) {
    if (npcNumber < 1) {
      throw ArgumentError.value(npcNumber, 'npcNumber');
    }
    final shown = _shownQuestionIdsByNpc.putIfAbsent(npcNumber, () => {});
    shown
      ..clear()
      ..addAll(questionIds.where(validQuestionIds.contains));
  }
}
