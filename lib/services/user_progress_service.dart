import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'leaderboard_service.dart';
import '../worksheet_lesson_data.dart';

class UserProgress {
  static const int npcQuestionCount = 6;
  static const Map<int, List<int>> worksheetModuleRequiredCompletions = {
    2: [8],
    3: [15],
    4: [20],
    5: [25],
    6: [30],
    7: [35],
    8: [41, 42],
  };

  final List<int> completedLevels;
  final List<int> completedNpcQuestions;
  final Map<int, List<int>> completedNpcQuestionsByLevel;
  final int unlockedLevels;
  final int questAttempts;
  final Map<String, int> classroomQuestCompletionTimes;
  final Map<String, Map<String, dynamic>> classroomQuestResults;
  final Map<int, int> maxUnlockedSubLevel;
  final Map<int, LevelQuestionAnswer> levelQuestionAnswers;
  final Map<int, int> gameModeFinalScores;

  UserProgress({
    required this.completedLevels,
    required this.completedNpcQuestions,
    this.completedNpcQuestionsByLevel = const {},
    required this.unlockedLevels,
    required this.questAttempts,
    required this.maxUnlockedSubLevel,
    this.classroomQuestCompletionTimes = const {},
    this.classroomQuestResults = const {},
    this.levelQuestionAnswers = const {},
    this.gameModeFinalScores = const {},
  });

  int get completedCount => completedLevels.length;

  int get completedNpcQuestionCount {
    var count = 0;
    for (final entry in completedNpcQuestionsByLevel.entries) {
      count += entry.value.length;
    }
    if (!completedNpcQuestionsByLevel.containsKey(1)) {
      count += completedNpcQuestions.toSet().length;
    }
    return count;
  }

  int get completedNpcRoundCount {
    var count = completedNpcQuestionsByLevel.values
        .where((questions) => questions.length >= npcQuestionCount)
        .length;
    if (!completedNpcQuestionsByLevel.containsKey(1) &&
        completedNpcQuestions.toSet().length >= npcQuestionCount) {
      count++;
    }
    return count;
  }

  int get currentNpcQuestionNumber {
    for (var questionNumber = 1;
        questionNumber <= npcQuestionCount;
        questionNumber++) {
      if (!completedNpcQuestions.contains(questionNumber)) {
        return questionNumber;
      }
    }
    return npcQuestionCount;
  }

  bool get areNpcQuestionsCompleted =>
      List.generate(npcQuestionCount, (index) => index + 1)
          .every(completedNpcQuestions.contains);

  List<int> completedNpcQuestionsForLevel(int level) =>
      completedNpcQuestionsByLevel[level] ??
      (level == 1 ? completedNpcQuestions : const []);

  int currentNpcQuestionNumberForLevel(int level) {
    final completed = completedNpcQuestionsForLevel(level);
    for (var questionNumber = 1;
        questionNumber <= npcQuestionCount;
        questionNumber++) {
      if (!completed.contains(questionNumber)) return questionNumber;
    }
    return npcQuestionCount;
  }

  bool areNpcQuestionsCompletedForLevel(int level) {
    final completed = completedNpcQuestionsForLevel(level);
    return List.generate(npcQuestionCount, (index) => index + 1)
        .every(completed.contains);
  }

  int get highestCompletedLevel =>
      completedLevels.isEmpty ? 0 : completedLevels.reduce(max);

  int? nextRequiredGameModeLevelForTopic(int level) {
    final moduleIndex = gameModeModuleIndexForLevel(level);
    for (var requiredLevel = 1;
        requiredLevel < gameModeModuleStartLevels[moduleIndex];
        requiredLevel++) {
      if (!gameModeFinalScores.containsKey(requiredLevel)) {
        return requiredLevel;
      }
    }
    return null;
  }

  bool isGameModeTopicUnlocked(int level) =>
      nextRequiredGameModeLevelForTopic(level) == null;

  bool isWorksheetModuleUnlocked(int moduleNumber) {
    if (moduleNumber < 1 || moduleNumber > 8) return false;
    if (moduleNumber == 1) return true;

    for (var module = 2; module <= moduleNumber; module++) {
      if (!worksheetModuleRequiredCompletions[module]!
          .every(completedLevels.contains)) {
        return false;
      }
    }
    return true;
  }

  String worksheetModuleUnlockLabel(int moduleNumber) {
    if (isWorksheetModuleUnlocked(moduleNumber)) return 'Unlocked';
    return worksheetModuleRequirementLabel(moduleNumber);
  }

  static String worksheetModuleRequirementLabel(int moduleNumber) {
    final requiredLevels = worksheetModuleRequiredCompletions[moduleNumber];
    if (requiredLevels == null) return 'Unlocked';

    final labels = requiredLevels.map((globalLevel) {
      return switch (globalLevel) {
        8 => 'Stage 1 - 8',
        15 => 'Stage 1 - 15',
        20 => 'Stage 1 - 20',
        25 => 'Stage 1',
        30 => 'Stage 2 - 10',
        35 => 'Stage 2 - 15',
        41 => 'Stage 1',
        42 => 'Stage 2',
        _ => throw StateError(
            'No worksheet module label is defined for level $globalLevel.',
          ),
      };
    }).toList(growable: false);
    if (labels.length == 1) return 'Complete ${labels.single}';
    return 'Complete ${labels.sublist(0, labels.length - 1).join(', ')} '
        'and ${labels.last}';
  }
}

class ClassroomQuestAttempt {
  const ClassroomQuestAttempt({
    required this.id,
    required this.questionNumber,
    required this.answer,
    required this.isCorrect,
    required this.score,
    required this.attemptNumber,
    required this.timeSpentSeconds,
    required this.timedOut,
    required this.status,
    this.attemptedAt,
  });

  final String id;
  final int questionNumber;
  final String answer;
  final bool isCorrect;
  final int score;
  final int attemptNumber;
  final int timeSpentSeconds;
  final bool timedOut;
  final String status;
  final DateTime? attemptedAt;

  static ClassroomQuestAttempt? fromDocument(
    String id,
    Map<String, dynamic> data,
  ) {
    final questionNumber = data['questionNumber'];
    final answer = data['answer'];
    final isCorrect = data['isCorrect'];
    final score = data['score'];
    final attemptNumber = data['attemptNumber'];
    final timeSpentSeconds = data['timeSpentSeconds'];
    final timedOut = data['timedOut'];
    final status = data['status'];
    final attemptedAtValue = data['attemptedAt'];
    if (data['questId'] != UserProgressService.classroomQuestId ||
        data['type'] != 'answer' ||
        questionNumber is! int ||
        questionNumber < 1 ||
        questionNumber > 3 ||
        answer is! String ||
        isCorrect is! bool ||
        score is! int ||
        attemptNumber is! int ||
        attemptNumber < 1 ||
        timeSpentSeconds is! int ||
        timeSpentSeconds < 0 ||
        timeSpentSeconds > 60 ||
        timedOut is! bool ||
        status is! String ||
        (attemptedAtValue != null &&
            attemptedAtValue is! Timestamp &&
            attemptedAtValue is! DateTime)) {
      return null;
    }
    if (timedOut) {
      if (answer.isNotEmpty ||
          isCorrect ||
          score != 0 ||
          status != 'timed_out') {
        return null;
      }
    } else if (answer.isEmpty ||
        status != (isCorrect ? 'correct' : 'incorrect') ||
        score != (isCorrect ? 10 : 0)) {
      return null;
    }

    return ClassroomQuestAttempt(
      id: id,
      questionNumber: questionNumber,
      answer: answer,
      isCorrect: isCorrect,
      score: score,
      attemptNumber: attemptNumber,
      timeSpentSeconds: timeSpentSeconds,
      timedOut: timedOut,
      status: status,
      attemptedAt: attemptedAtValue is Timestamp
          ? attemptedAtValue.toDate()
          : attemptedAtValue as DateTime?,
    );
  }

  Map<String, dynamic> toDocument(String uid) => {
        'uid': uid,
        'questId': UserProgressService.classroomQuestId,
        'type': 'answer',
        'questionNumber': questionNumber,
        'answer': answer,
        'isCorrect': isCorrect,
        'score': score,
        'attemptNumber': attemptNumber,
        'timeSpentSeconds': timeSpentSeconds,
        'timedOut': timedOut,
        'status': status,
        'attemptedAt': FieldValue.serverTimestamp(),
      };
}

class GameModeAnswerAttempt {
  const GameModeAnswerAttempt({
    required this.id,
    required this.level,
    required this.questionNumber,
    required this.question,
    required this.selectedAnswer,
    required this.correctAnswer,
    required this.isCorrect,
    required this.scoreEarned,
    required this.scoreAfter,
    this.attemptedAt,
  });

  final String id;
  final int level;
  final int questionNumber;
  final String question;
  final String selectedAnswer;
  final String correctAnswer;
  final bool isCorrect;
  final int scoreEarned;
  final int scoreAfter;
  final DateTime? attemptedAt;

  static GameModeAnswerAttempt? fromDocument(
    String id,
    Map<String, dynamic> data,
  ) {
    final level = data['level'];
    final questionNumber = data['questionNumber'];
    final question = data['question'];
    final selectedAnswer = data['selectedAnswer'];
    final correctAnswer = data['correctAnswer'];
    final isCorrect = data['isCorrect'];
    final scoreEarned = data['scoreEarned'];
    final scoreAfter = data['scoreAfter'];
    final attemptedAt = data['attemptedAt'];
    if (level is! int ||
        level < 1 ||
        level > 60 ||
        questionNumber is! int ||
        questionNumber < 1 ||
        questionNumber > UserProgress.npcQuestionCount ||
        question is! String ||
        selectedAnswer is! String ||
        correctAnswer is! String ||
        isCorrect is! bool ||
        scoreEarned is! int ||
        scoreEarned != (isCorrect ? 10 : 0) ||
        scoreAfter is! int ||
        scoreAfter < scoreEarned ||
        scoreAfter > 70 ||
        (attemptedAt != null &&
            attemptedAt is! Timestamp &&
            attemptedAt is! DateTime)) {
      return null;
    }
    return GameModeAnswerAttempt(
      id: id,
      level: level,
      questionNumber: questionNumber,
      question: question,
      selectedAnswer: selectedAnswer,
      correctAnswer: correctAnswer,
      isCorrect: isCorrect,
      scoreEarned: scoreEarned,
      scoreAfter: scoreAfter,
      attemptedAt: attemptedAt is Timestamp
          ? attemptedAt.toDate()
          : attemptedAt as DateTime?,
    );
  }
}

class GameModeAnswerAttemptIds {
  GameModeAnswerAttemptIds({required String Function() createId})
      : _createId = createId;

  final String Function() _createId;
  final Map<(String, bool), String> _idsByAnswer = {};

  String forAnswer(String answer, bool isCorrect) =>
      _idsByAnswer.putIfAbsent((answer, isCorrect), _createId);
}

class ProblemLevelAnswerAttemptIds {
  ProblemLevelAnswerAttemptIds({required String Function() createId})
      : _createId = createId;

  final String Function() _createId;
  final Map<int, String> _idsByAnswer = {};

  String forAnswer(int answer) => _idsByAnswer.putIfAbsent(answer, _createId);
}

class LevelQuestionAnswer {
  const LevelQuestionAnswer({
    required this.firstOperand,
    required this.secondOperand,
    required this.operation,
    required this.correctAnswer,
  });

  final int firstOperand;
  final int secondOperand;
  final String operation;
  final int correctAnswer;

  factory LevelQuestionAnswer.fromData(Object? value) {
    if (value is! Map<String, dynamic>) {
      throw const FormatException('Invalid saved level question.');
    }
    final firstOperand = value['firstOperand'];
    final secondOperand = value['secondOperand'];
    final operation = value['operation'];
    final correctAnswer = value['correctAnswer'];
    if (firstOperand is! num ||
        secondOperand is! num ||
        operation is! String ||
        correctAnswer is! num ||
        (operation != '+' && operation != '-') ||
        (operation == '+' &&
            firstOperand.toInt() + secondOperand.toInt() !=
                correctAnswer.toInt()) ||
        (operation == '-' &&
            firstOperand.toInt() - secondOperand.toInt() !=
                correctAnswer.toInt())) {
      throw const FormatException('Invalid saved level question.');
    }
    return LevelQuestionAnswer(
      firstOperand: firstOperand.toInt(),
      secondOperand: secondOperand.toInt(),
      operation: operation,
      correctAnswer: correctAnswer.toInt(),
    );
  }

  Map<String, dynamic> toData() => {
        'firstOperand': firstOperand,
        'secondOperand': secondOperand,
        'operation': operation,
        'correctAnswer': correctAnswer,
      };
}

class LevelQuestionCompletion {
  const LevelQuestionCompletion({
    required this.answer,
    required this.wasAlreadyCompleted,
  });

  final LevelQuestionAnswer answer;
  final bool wasAlreadyCompleted;
}

class UserProgressService {
  static const String classroomQuestId = 'classroom_quest';

  static FirebaseAuth? get _authOrNull {
    try {
      return FirebaseAuth.instance;
    } on FirebaseException {
      return null;
    } catch (_) {
      return null;
    }
  }

  static CollectionReference<Map<String, dynamic>> get _users {
    try {
      return FirebaseFirestore.instance.collection('users');
    } on FirebaseException {
      throw StateError(
          'Firebase Firestore is not available because Firebase is not initialized.');
    } catch (_) {
      throw StateError(
          'Firebase Firestore is not available because Firebase is not initialized.');
    }
  }

  static const _gameModeFinalScoreKeyPrefix =
      'mathquest_game_mode_final_score_';
  static const _gameModeIntroKeyPrefix = 'mathquest_game_mode_intro_seen_';
  static String? _cachedCurrentUid;
  static Future<UserProgress>? _cachedCurrentProgress;

  static String _uid([String? uid]) {
    final resolved = uid ?? _authOrNull?.currentUser?.uid;
    if (resolved == null || resolved.isEmpty) {
      throw StateError('Not signed in.');
    }
    return resolved;
  }

  static String newClassroomQuestAttemptId() {
    return _users.doc(_uid()).collection('classroomQuestAttempts').doc().id;
  }

  static String newGameModeAnswerAttemptId() {
    return _users.doc(_uid()).collection('gameModeAttempts').doc().id;
  }

  static String newProblemLevelAnswerAttemptId() {
    return _users.doc(_uid()).collection('problemLevelAttempts').doc().id;
  }

  static Stream<UserProgress> watchCurrentUserProgress() {
    return _users
        .doc(_uid())
        .snapshots()
        .map((snapshot) => _fromData(snapshot.data()));
  }

  static Stream<List<GameModeAnswerAttempt>> watchGameModeAnswerAttempts({
    required String uid,
  }) {
    final authenticatedUid = _uid();
    if (uid != authenticatedUid) {
      throw StateError('Cannot watch another account\'s Game Mode history.');
    }
    return _users
        .doc(authenticatedUid)
        .collection('gameModeAttempts')
        .orderBy('attemptedAt', descending: true)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((document) => GameModeAnswerAttempt.fromDocument(
                document.id, document.data()))
            .whereType<GameModeAnswerAttempt>()
            .toList(growable: false));
  }

  static Future<void> recordGameModeAnswer({
    required String attemptId,
    required int level,
    required int questionNumber,
    required String question,
    required String selectedAnswer,
    required String correctAnswer,
    required bool isCorrect,
    required int scoreEarned,
    required int scoreAfter,
  }) async {
    if (attemptId.isEmpty || attemptId.length > 100) {
      throw ArgumentError.value(attemptId, 'attemptId');
    }
    if (level < 1 || level > 60) {
      throw ArgumentError.value(level, 'level');
    }
    if (questionNumber < 1 || questionNumber > UserProgress.npcQuestionCount) {
      throw ArgumentError.value(questionNumber, 'questionNumber');
    }
    if (question.isEmpty ||
        question.length > 500 ||
        selectedAnswer.isEmpty ||
        selectedAnswer.length > 120 ||
        correctAnswer.isEmpty ||
        correctAnswer.length > 120) {
      throw ArgumentError('Invalid Game Mode answer text.');
    }
    if (scoreEarned != (isCorrect ? 10 : 0) ||
        scoreAfter < scoreEarned ||
        scoreAfter > 70) {
      throw ArgumentError('Invalid Game Mode score.');
    }

    var stage = 'resolve authenticated student';
    try {
      final userId = _uid();
      final authUser = _authOrNull?.currentUser;
      debugPrint(
        'Game Mode answer save: authenticated=${authUser != null}, '
        'targetMatchesAuthenticated=${authUser?.uid == userId}, '
        'document=users/{uid}/gameModeAttempts/{attemptId}, '
        'write=create, level=$level, questionNumber=$questionNumber.',
      );
      final attemptRef =
          _users.doc(userId).collection('gameModeAttempts').doc(attemptId);
      final attemptData = <String, dynamic>{
        'uid': userId,
        'level': level,
        'questionNumber': questionNumber,
        'question': question,
        'selectedAnswer': selectedAnswer,
        'correctAnswer': correctAnswer,
        'isCorrect': isCorrect,
        'scoreEarned': scoreEarned,
        'scoreAfter': scoreAfter,
      };

      stage = 'read attempt document and commit transaction';
      await FirebaseFirestore.instance
          .runTransaction<void>((transaction) async {
        final snapshot = await transaction.get(attemptRef);
        if (snapshot.exists) {
          final saved = snapshot.data()!;
          final isSameAttempt = attemptData.entries
              .every((entry) => saved[entry.key] == entry.value);
          if (!isSameAttempt) {
            throw StateError(
              'This Game Mode answer attempt ID is already used.',
            );
          }
          return;
        }

        transaction.set(attemptRef, {
          ...attemptData,
          'attemptedAt': FieldValue.serverTimestamp(),
        });
      });
      debugPrint(
        'Game Mode answer save: transaction committed for '
        'users/{uid}/gameModeAttempts/{attemptId}.',
      );
    } on FirebaseException catch (error, stackTrace) {
      debugPrint(
        'Game Mode answer save failed during "$stage": '
        'plugin=${error.plugin}, code=${error.code}, '
        'message=${error.message}.',
      );
      debugPrintStack(stackTrace: stackTrace);
      Error.throwWithStackTrace(error, stackTrace);
    } catch (error, stackTrace) {
      debugPrint(
        'Game Mode answer save failed during "$stage": '
        'exceptionType=${error.runtimeType}, message=$error.',
      );
      debugPrintStack(stackTrace: stackTrace);
      Error.throwWithStackTrace(error, stackTrace);
    }
  }

  static Stream<List<ClassroomQuestAttempt>> watchClassroomQuestAttempts({
    String? uid,
  }) {
    return _users
        .doc(_uid(uid))
        .collection('classroomQuestAttempts')
        .orderBy('attemptedAt', descending: true)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((document) => ClassroomQuestAttempt.fromDocument(
                document.id, document.data()))
            .whereType<ClassroomQuestAttempt>()
            .toList(growable: false));
  }

  static Stream<int> watchClassroomQuestAttemptCount({String? uid}) {
    return _users
        .doc(_uid(uid))
        .snapshots()
        .map((snapshot) => _fromData(snapshot.data()).questAttempts);
  }

  static Future<void> recordClassroomQuestAttempt(
    ClassroomQuestAttempt attempt,
  ) async {
    final uid = _uid();
    final userRef = _users.doc(uid);
    final attemptRef =
        userRef.collection('classroomQuestAttempts').doc(attempt.id);
    await FirebaseFirestore.instance.runTransaction<void>((transaction) async {
      final userSnapshot = await transaction.get(userRef);
      final attemptSnapshot = await transaction.get(attemptRef);
      if (attemptSnapshot.exists) return;
      if (!userSnapshot.exists) {
        throw StateError('The user profile does not exist.');
      }

      final data = userSnapshot.data() ?? {};
      final rawProgress = data['progress'];
      if (rawProgress != null && rawProgress is! Map) {
        throw const FormatException('Invalid saved user progress.');
      }
      final progress = rawProgress is Map
          ? Map<String, dynamic>.from(rawProgress)
          : <String, dynamic>{};
      final savedAttempts = progress['questAttempts'] ?? 0;
      if (savedAttempts is! int || savedAttempts < 0) {
        throw const FormatException('Invalid saved Classroom Quest count.');
      }

      transaction.set(attemptRef, attempt.toDocument(uid));
      transaction.update(userRef, {
        'progress.questAttempts': savedAttempts + 1,
        'progress.latestClassroomQuestAttemptId': attempt.id,
      });
    });
    _invalidateCurrentProgressCache();
  }

  static UserProgress _fromData(Map<String, dynamic>? data) {
    final progress = data?['progress'] as Map<String, dynamic>? ?? {};
    final completed = (progress['completedLevels'] as List<dynamic>? ?? [])
        .map((value) => int.tryParse(value.toString()))
        .whereType<int>()
        .toSet()
        .toList()
      ..sort();
    final completedNpcQuestions =
        (progress['completedNpcQuestions'] as List<dynamic>? ?? [])
            .map((value) => int.tryParse(value.toString()))
            .where((value) => value != null && value >= 1 && value <= 8)
            .cast<int>()
            .toSet()
            .toList()
          ..sort();
    final rawNpcQuestionsByLevel =
        progress['completedNpcQuestionsByLevel'] as Map<String, dynamic>? ?? {};
    final completedNpcQuestionsByLevel = <int, List<int>>{};
    for (final entry in rawNpcQuestionsByLevel.entries) {
      final level = int.tryParse(entry.key);
      final questions = (entry.value as List<dynamic>? ?? [])
          .map((value) => int.tryParse(value.toString()))
          .where((value) =>
              value != null &&
              value >= 1 &&
              value <= UserProgress.npcQuestionCount)
          .cast<int>()
          .toSet()
          .toList()
        ..sort();
      if (level != null && level >= 1 && level <= 60) {
        completedNpcQuestionsByLevel[level] = questions;
      }
    }
    final rawSublevels =
        progress['maxUnlockedSubLevel'] as Map<String, dynamic>? ?? {};
    final rawClassroomQuestCompletionTimes =
        progress['classroomQuestCompletionTimes'] as Map<String, dynamic>? ??
            {};
    final rawClassroomQuestResults =
        progress['classroomQuestResults'] as Map<String, dynamic>? ?? {};
    final rawLevelQuestionAnswers =
        progress['levelQuestionAnswers'] as Map<String, dynamic>? ?? {};
    final rawGameModeFinalScores =
        progress['gameModeFinalScores'] as Map<String, dynamic>? ?? {};
    return UserProgress(
      completedLevels: completed,
      completedNpcQuestions: completedNpcQuestions,
      completedNpcQuestionsByLevel: completedNpcQuestionsByLevel,
      unlockedLevels: (progress['unlockedLevels'] as num?)?.toInt() ?? 1,
      questAttempts: (progress['questAttempts'] as num?)?.toInt() ?? 0,
      classroomQuestCompletionTimes: {
        for (final entry in rawClassroomQuestCompletionTimes.entries)
          if (entry.value is num && (entry.value as num) >= 0)
            entry.key: (entry.value as num).toInt(),
      },
      classroomQuestResults: {
        for (final entry in rawClassroomQuestResults.entries)
          if (entry.value is Map<String, dynamic>)
            entry.key: Map<String, dynamic>.from(entry.value as Map),
      },
      maxUnlockedSubLevel: {
        1: (rawSublevels['1'] as num?)?.toInt() ?? 1,
        2: (rawSublevels['2'] as num?)?.toInt() ?? 1,
        3: (rawSublevels['3'] as num?)?.toInt() ?? 1,
      },
      levelQuestionAnswers: {
        for (final entry in rawLevelQuestionAnswers.entries)
          if (int.tryParse(entry.key) case final int level
              when level >= 1 && level <= 60)
            level: LevelQuestionAnswer.fromData(entry.value),
      },
      gameModeFinalScores: {
        for (final entry in rawGameModeFinalScores.entries)
          if (int.tryParse(entry.key) case final int level
              when level >= 1 && level <= 60)
            if (entry.value is int && entry.value >= 0 && entry.value <= 70)
              level: entry.value as int,
      },
    );
  }

  static Future<UserProgress> getProgressForUid(String uid) async {
    final snapshot = await _users.doc(uid).get();
    return _fromData(snapshot.data());
  }

  static Future<UserProgress> getProgressForEmail(String email) async {
    final snapshot =
        await _users.where('email', isEqualTo: email).limit(1).get();
    return snapshot.docs.isEmpty
        ? _fromData(null)
        : _fromData(snapshot.docs.first.data());
  }

  static Future<UserProgress> getCurrentUserProgress(
      {bool forceRefresh = false}) {
    final uid = _uid();
    if (forceRefresh ||
        _cachedCurrentUid != uid ||
        _cachedCurrentProgress == null) {
      _cachedCurrentUid = uid;
      _cachedCurrentProgress = getProgressForUid(uid).then<UserProgress>(
        (progress) => progress,
        onError: (Object error, StackTrace stackTrace) {
          if (_cachedCurrentUid == uid) {
            _cachedCurrentUid = null;
            _cachedCurrentProgress = null;
          }
          Error.throwWithStackTrace(error, stackTrace);
        },
      );
    }
    return _cachedCurrentProgress!;
  }

  static Future<void> preloadCurrentUserProgress() async {
    await getCurrentUserProgress();
  }

  static void _invalidateCurrentProgressCache() {
    _cachedCurrentUid = null;
    _cachedCurrentProgress = null;
  }

  static Future<LevelQuestionCompletion> completeLevelQuestion(
    int level,
    LevelQuestionAnswer answer,
  ) async {
    if (level < 1 || level > 60) {
      throw ArgumentError.value(level, 'level');
    }

    var stage = 'resolve authenticated user';
    try {
      final authUser = _authOrNull?.currentUser;
      debugPrint(
        'Level Question save: authenticated=${authUser != null}.',
      );
      final uid = _uid();
      final userRef = _users.doc(uid);
      debugPrint(
        'Level Question save: targetMatchesAuthenticated=${authUser?.uid == uid}, '
        'document=users/{uid}, field=progress.levelQuestionAnswers.$level.',
      );

      stage = 'read user progress transaction';
      final completion = await FirebaseFirestore.instance
          .runTransaction<LevelQuestionCompletion>(
        (transaction) async {
          debugPrint('Level Question save: reading users/{uid}.');
          final snapshot = await transaction.get(userRef);
          debugPrint(
            'Level Question save: read completed; '
            'documentExists=${snapshot.exists}.',
          );
          if (!snapshot.exists) {
            throw StateError('The user progress document does not exist.');
          }

          stage = 'parse existing user progress';
          final progress = _fromData(snapshot.data());
          final savedAnswer = progress.levelQuestionAnswers[level];
          if (savedAnswer != null) {
            debugPrint(
              'Level Question save: level $level was already completed; '
              'no write required.',
            );
            return LevelQuestionCompletion(
              answer: savedAnswer,
              wasAlreadyCompleted: true,
            );
          }

          stage = 'write levelQuestionAnswers transaction';
          final payload = {
            'progress': {
              'levelQuestionAnswers': {
                ...progress.levelQuestionAnswers.map(
                  (savedLevel, saved) => MapEntry(
                    savedLevel.toString(),
                    saved.toData(),
                  ),
                ),
                level.toString(): answer.toData(),
              },
              'latestLevelQuestionAnswerLevel': level.toString(),
            },
          };
          debugPrint(
            'Level Question save: writing users/{uid}; '
            'payloadFields=progress.levelQuestionAnswers, '
            'answerFields=firstOperand,secondOperand,operation,correctAnswer.',
          );
          transaction.set(userRef, payload, SetOptions(merge: true));
          return LevelQuestionCompletion(
            answer: answer,
            wasAlreadyCompleted: false,
          );
        },
      );
      debugPrint(
        'Level Question save: transaction committed; '
        'alreadyCompleted=${completion.wasAlreadyCompleted}.',
      );
      _invalidateCurrentProgressCache();
      return completion;
    } on FirebaseException catch (error, stackTrace) {
      debugPrint(
        'Level Question save failed during "$stage": '
        '${error.runtimeType}, code=${error.code}, message=${error.message}.',
      );
      debugPrintStack(stackTrace: stackTrace);
      Error.throwWithStackTrace(error, stackTrace);
    } catch (error, stackTrace) {
      debugPrint(
        'Level Question save failed during "$stage": '
        '${error.runtimeType}: $error.',
      );
      debugPrintStack(stackTrace: stackTrace);
      Error.throwWithStackTrace(error, stackTrace);
    }
  }

  static Future<void> recordProblemLevelAnswer({
    required String attemptId,
    required int level,
    required String question,
    required int selectedAnswer,
    required int correctAnswer,
  }) async {
    if (attemptId.isEmpty || attemptId.length > 100) {
      throw ArgumentError.value(attemptId, 'attemptId');
    }
    if (level < 1 || level > 60) {
      throw ArgumentError.value(level, 'level');
    }
    if (question.isEmpty || question.length > 500) {
      throw ArgumentError.value(question, 'question');
    }

    final userId = _uid();
    final attemptRef =
        _users.doc(userId).collection('problemLevelAttempts').doc(attemptId);
    final attemptData = <String, dynamic>{
      'uid': userId,
      'level': level,
      'question': question,
      'selectedAnswer': selectedAnswer,
      'correctAnswer': correctAnswer,
      'isCorrect': selectedAnswer == correctAnswer,
    };

    var stage = 'read answer attempt and commit transaction';
    try {
      final authUser = _authOrNull?.currentUser;
      debugPrint(
        'Problem Level answer save: authenticated=${authUser != null}, '
        'targetMatchesAuthenticated=${authUser?.uid == userId}, '
        'document=users/{uid}/problemLevelAttempts/{attemptId}, '
        'write=create, level=$level, '
        'isCorrect=${selectedAnswer == correctAnswer}.',
      );
      await FirebaseFirestore.instance
          .runTransaction<void>((transaction) async {
        final snapshot = await transaction.get(attemptRef);
        if (snapshot.exists) {
          final saved = snapshot.data()!;
          final isSameAttempt = attemptData.entries
              .every((entry) => saved[entry.key] == entry.value);
          if (!isSameAttempt) {
            throw StateError(
              'This Problem Level answer attempt ID is already used.',
            );
          }
          return;
        }

        transaction.set(attemptRef, {
          ...attemptData,
          'attemptedAt': FieldValue.serverTimestamp(),
        });
      });
      debugPrint(
        'Problem Level answer save: transaction committed for '
        'users/{uid}/problemLevelAttempts/{attemptId}.',
      );
    } on FirebaseException catch (error, stackTrace) {
      debugPrint(
        'Problem Level answer save failed during "$stage": '
        'plugin=${error.plugin}, code=${error.code}, '
        'message=${error.message}.',
      );
      debugPrintStack(stackTrace: stackTrace);
      Error.throwWithStackTrace(error, stackTrace);
    } catch (error, stackTrace) {
      debugPrint(
        'Problem Level answer save failed during "$stage": '
        'exceptionType=${error.runtimeType}, message=$error.',
      );
      debugPrintStack(stackTrace: stackTrace);
      Error.throwWithStackTrace(error, stackTrace);
    }
  }

  static Future<int?> getGameModeFinalScore(int level, {String? uid}) async {
    if (level < 1 || level > 60) {
      throw ArgumentError.value(level, 'level');
    }
    final savedScore =
        (await getProgressForUid(_uid(uid))).gameModeFinalScores[level];
    if (savedScore != null) return savedScore;

    final preferences = await SharedPreferences.getInstance();
    return preferences.getInt(
      '$_gameModeFinalScoreKeyPrefix${_uid(uid)}_$level',
    );
  }

  static Future<bool> shouldShowGameModeIntroduction({String? uid}) async {
    final resolvedUid = _uid(uid);
    final preferences = await SharedPreferences.getInstance();
    return !(preferences.getBool('$_gameModeIntroKeyPrefix$resolvedUid') ??
        false);
  }

  static Future<void> markGameModeIntroductionSeen({String? uid}) async {
    final resolvedUid = _uid(uid);
    final preferences = await SharedPreferences.getInstance();
    await preferences.setBool('$_gameModeIntroKeyPrefix$resolvedUid', true);
  }

  static Future<void> completeGameMode(int level, int score) async {
    if (level < 1 || level > 60) {
      throw ArgumentError.value(level, 'level');
    }
    if (score < UserProgress.npcQuestionCount * 10 || score > 70) {
      throw ArgumentError.value(score, 'score');
    }

    final uid = _uid();
    final firestore = FirebaseFirestore.instance;
    final userRef = _users.doc(uid);
    final leaderboardRef =
        firestore.collection(LeaderboardService.collectionName).doc(uid);
    final awardRef = userRef.collection('scoreAwards').doc('game-mode-$level');

    await firestore.runTransaction<void>((transaction) async {
      final userSnapshot = await transaction.get(userRef);
      final leaderboardSnapshot = await transaction.get(leaderboardRef);
      final awardSnapshot = await transaction.get(awardRef);
      if (!userSnapshot.exists) {
        throw StateError('User profile not found.');
      }

      final userData = userSnapshot.data()!;
      if (userData['role']?.toString().toLowerCase() != 'student' ||
          userData['status']?.toString().toLowerCase() != 'approved') {
        throw StateError(
            'Only approved student accounts can save Game Mode scores.');
      }

      final savedProgress = _fromData(userData);
      final existingScore = savedProgress.gameModeFinalScores[level];
      if (existingScore != null) {
        if (existingScore != score) {
          throw StateError('A completed Game Mode score cannot be changed.');
        }
        return;
      }

      if (!savedProgress.areNpcQuestionsCompletedForLevel(level)) {
        throw StateError(
          'All NPC questions must be completed before saving a Game Mode score.',
        );
      }

      if (awardSnapshot.exists) {
        throw StateError(
          'Game Mode score award exists without a completed score record.',
        );
      }

      final baseline = userData['scoreBaseline'] ?? 0;
      final earned = userData['scoreEarned'] ?? 0;
      if (baseline is! int || baseline < 0 || earned is! int || earned < 0) {
        throw const FormatException('The saved total score data is invalid.');
      }
      final oldLeaderboardScore =
          _leaderboardScore(leaderboardSnapshot.data() ?? const {});
      final newEarned = earned + score;
      final newGameScore = baseline + newEarned;
      if (newGameScore < 0) {
        throw const FormatException('The saved total score data is invalid.');
      }

      final completed = {
        ...savedProgress.completedLevels,
        level,
      }.toList()
        ..sort();
      final mainLevel = ((level - 1) ~/ 20) + 1;
      final displayNumber = level % 20 == 0 ? 20 : level % 20;
      final nextSubLevel = displayNumber + 1;
      final sublevels = {...savedProgress.maxUnlockedSubLevel};
      if (nextSubLevel <= 20 && nextSubLevel > (sublevels[mainLevel] ?? 1)) {
        sublevels[mainLevel] = nextSubLevel;
      }
      final unlockedLevels = displayNumber == 20 && mainLevel < 3
          ? max(savedProgress.unlockedLevels, mainLevel + 1)
          : savedProgress.unlockedLevels;

      transaction.update(userRef, {
        'progress.completedLevels': completed,
        'progress.unlockedLevels': unlockedLevels,
        'progress.maxUnlockedSubLevel': {
          '1': sublevels[1] ?? 1,
          '2': sublevels[2] ?? 1,
          '3': sublevels[3] ?? 1,
        },
        'progress.gameModeFinalScores.$level': score,
        'progress.latestCompletedGameModeLevel': '$level',
        'scoreEarned': newEarned,
        'gameScore': newGameScore,
      });

      transaction.set(awardRef, {
        'points': score,
        'createdAt': FieldValue.serverTimestamp(),
      });

      final leaderboardData = leaderboardSnapshot.data();
      final displayName = (userData['name'] ?? 'Player').toString();
      final totalScore = oldLeaderboardScore + score;
      final createdAt = leaderboardData?['createdAt'] ??
          userData['createdAt'] ??
          FieldValue.serverTimestamp();
      if (leaderboardSnapshot.exists) {
        transaction.update(leaderboardRef, {
          'uid': uid,
          'displayName': displayName,
          'totalScore': totalScore,
          'createdAt': createdAt,
          'updatedAt': FieldValue.serverTimestamp(),
        });
      } else {
        transaction.set(leaderboardRef, {
          'uid': uid,
          'displayName': displayName,
          'totalScore': totalScore,
          'createdAt': createdAt,
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }
    });
    _invalidateCurrentProgressCache();
  }

  static int _leaderboardScore(Map<String, dynamic> data) {
    final rawScore = data['totalScore'] ?? data['totalscore'] ?? 0;
    if (rawScore is int && rawScore >= 0) return rawScore;
    if (rawScore is num && rawScore >= 0) return rawScore.toInt();
    final parsedScore = int.tryParse(rawScore.toString());
    if (parsedScore != null && parsedScore >= 0) return parsedScore;
    throw const FormatException('The saved leaderboard score is invalid.');
  }

  static Future<void> saveLevelCompletion(int level, {String? email}) async {
    final userRef = _users.doc(_uid());
    await FirebaseFirestore.instance.runTransaction((transaction) async {
      final snapshot = await transaction.get(userRef);
      final progress = _fromData(snapshot.data());
      final completed = {...progress.completedLevels, level}.toList()..sort();
      final mainLevel = ((level - 1) ~/ 20) + 1;
      final displayNumber = level % 20 == 0 ? 20 : level % 20;
      final nextSubLevel = displayNumber + 1;
      final sublevels = {...progress.maxUnlockedSubLevel};
      if (nextSubLevel <= 20 && nextSubLevel > (sublevels[mainLevel] ?? 1)) {
        sublevels[mainLevel] = nextSubLevel;
      }
      final unlockedLevels = displayNumber == 20 && mainLevel < 3
          ? max(progress.unlockedLevels, mainLevel + 1)
          : progress.unlockedLevels;
      transaction.set(
        userRef,
        {
          'progress': {
            'completedLevels': completed,
            'unlockedLevels': unlockedLevels,
            'questAttempts': progress.questAttempts,
            'maxUnlockedSubLevel': {
              '1': sublevels[1] ?? 1,
              '2': sublevels[2] ?? 1,
              '3': sublevels[3] ?? 1,
            },
          },
        },
        SetOptions(merge: true),
      );
    });
    _invalidateCurrentProgressCache();
  }

  static Future<bool> completeNpcQuestion(
    int questionNumber, {
    String? uid,
    int level = 1,
  }) async {
    if (questionNumber < 1 || questionNumber > UserProgress.npcQuestionCount) {
      throw ArgumentError.value(questionNumber, 'questionNumber');
    }
    if (level < 1 || level > 60) {
      throw ArgumentError.value(level, 'level');
    }

    final userRef = _users.doc(_uid(uid));
    return FirebaseFirestore.instance.runTransaction<bool>((transaction) async {
      final snapshot = await transaction.get(userRef);
      if (!snapshot.exists) {
        throw StateError('User profile not found.');
      }
      final progress = _fromData(snapshot.data());
      if (progress.areNpcQuestionsCompletedForLevel(level) ||
          progress.currentNpcQuestionNumberForLevel(level) != questionNumber) {
        return false;
      }

      final completed = {
        ...progress.completedNpcQuestionsForLevel(level),
        questionNumber,
      }.toList()
        ..sort();
      final completedByLevel = {
        for (final entry in progress.completedNpcQuestionsByLevel.entries)
          entry.key.toString(): entry.value,
        level.toString(): completed,
      };
      final updatedProgress = <String, dynamic>{
        'completedNpcQuestionsByLevel': completedByLevel,
        'latestCompletedNpcQuestionLevel': level.toString(),
      };
      if (level == 1) {
        updatedProgress['completedNpcQuestions'] = completed;
      }
      transaction.set(
        userRef,
        {'progress': updatedProgress},
        SetOptions(merge: true),
      );
      return true;
    }).then((completed) {
      if (completed) _invalidateCurrentProgressCache();
      return completed;
    });
  }

  static Future<void> resetNpcQuestionsForLevel(
    int level, {
    String? uid,
  }) async {
    if (level < 1 || level > 60) {
      throw ArgumentError.value(level, 'level');
    }

    final userRef = _users.doc(_uid(uid));
    await FirebaseFirestore.instance.runTransaction<void>((transaction) async {
      final snapshot = await transaction.get(userRef);
      if (!snapshot.exists) return;

      final progress = _fromData(snapshot.data());
      if (!progress.completedNpcQuestionsByLevel.containsKey(level) &&
          (level != 1 || progress.completedNpcQuestions.isEmpty)) {
        return;
      }

      final updates = <String, dynamic>{
        'progress.completedNpcQuestionsByLevel.$level': FieldValue.delete(),
      };
      if (level == 1) {
        updates['progress.completedNpcQuestions'] = <int>[];
      }
      transaction.update(userRef, updates);
    });
    _invalidateCurrentProgressCache();
  }

  static Future<void> saveClassroomQuestCompletion({
    required int completionTimeSeconds,
    required int correctAnswers,
    required int totalQuestions,
  }) async {
    if (completionTimeSeconds < 1) {
      throw ArgumentError.value(completionTimeSeconds, 'completionTimeSeconds');
    }
    if (totalQuestions < 1 ||
        correctAnswers != totalQuestions ||
        correctAnswers > 60) {
      throw ArgumentError(
        'A completed Classroom Quest must have all questions correct.',
      );
    }

    final userRef = _users.doc(_uid());
    await FirebaseFirestore.instance.runTransaction<void>((transaction) async {
      final snapshot = await transaction.get(userRef);
      if (!snapshot.exists) {
        throw StateError('The user progress document does not exist.');
      }
      final data = snapshot.data() ?? {};
      final progress = data['progress'] as Map<String, dynamic>? ?? {};
      final results = Map<String, dynamic>.from(
          progress['classroomQuestResults'] as Map? ?? {});
      if (results.containsKey(classroomQuestId)) return;
      final completionHistory = Map<String, dynamic>.from(
        progress['classroomQuestHistory'] as Map? ?? {},
      );
      final completionId =
          userRef.collection('classroomQuestAttempts').doc().id;

      final completionTimes = Map<String, dynamic>.from(
        progress['classroomQuestCompletionTimes'] as Map? ?? {},
      )..[classroomQuestId] = completionTimeSeconds;
      final completion = {
        'type': 'completion',
        'completionTimeSeconds': completionTimeSeconds,
        'score': correctAnswers * 10,
        'correctAnswers': correctAnswers,
        'totalQuestions': totalQuestions,
        'completedAt': FieldValue.serverTimestamp(),
      };
      completionHistory[completionId] = completion;
      results[classroomQuestId] = {
        'status': 'completed',
        'completionTimeSeconds': completionTimeSeconds,
        'score': correctAnswers * 10,
        'correctAnswers': correctAnswers,
        'totalQuestions': totalQuestions,
        'completedAt': FieldValue.serverTimestamp(),
      };
      transaction.update(userRef, {
        'progress.classroomQuestCompletionTimes': completionTimes,
        'progress.classroomQuestResults': results,
        'progress.classroomQuestHistory': completionHistory,
        'progress.latestClassroomQuestHistoryId': completionId,
      });
    });
    _invalidateCurrentProgressCache();
  }
}
