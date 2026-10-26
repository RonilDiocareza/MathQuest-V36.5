import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_mathquest/screens/module_lesson_screen.dart';
import 'package:flutter_mathquest/screens/modules_screen.dart';
import 'package:flutter_mathquest/services/user_progress_service.dart';
import 'package:flutter_mathquest/worksheet_lesson_data.dart';

UserProgress _progress(Set<int> completedLevels) => UserProgress(
      completedLevels: completedLevels.toList(),
      completedNpcQuestions: const [],
      unlockedLevels: 1,
      questAttempts: 0,
      maxUnlockedSubLevel: const {},
    );

void main() {
  test('module access requires all sequential completion milestones', () {
    final newStudent = _progress({});
    expect(newStudent.isWorksheetModuleUnlocked(1), isTrue);
    expect(newStudent.worksheetModuleUnlockLabel(1), 'Unlocked');
    for (var module = 2; module <= 8; module++) {
      expect(newStudent.isWorksheetModuleUnlocked(module), isFalse);
    }
    expect(newStudent.worksheetModuleUnlockLabel(2), 'Complete Stage 1 - 8');
    expect(newStudent.worksheetModuleUnlockLabel(3), 'Complete Stage 1 - 15');
    expect(newStudent.worksheetModuleUnlockLabel(4), 'Complete Stage 1 - 20');
    expect(
      newStudent.worksheetModuleUnlockLabel(5),
      'Complete Stage 1',
    );
    expect(
      newStudent.worksheetModuleUnlockLabel(6),
      'Complete Stage 2 - 10',
    );
    expect(
      newStudent.worksheetModuleUnlockLabel(7),
      'Complete Stage 2 - 15',
    );
    expect(
      newStudent.worksheetModuleUnlockLabel(8),
      'Complete Stage 1 and Stage 2',
    );

    expect(_progress({7}).isWorksheetModuleUnlocked(2), isFalse);
    expect(_progress({8}).isWorksheetModuleUnlocked(2), isTrue);
    expect(_progress({15}).isWorksheetModuleUnlocked(3), isFalse);
    expect(_progress({8, 20}).isWorksheetModuleUnlocked(4), isFalse);
    expect(_progress({8}).isWorksheetModuleUnlocked(2), isTrue);
    expect(_progress({8, 15}).isWorksheetModuleUnlocked(3), isTrue);
    expect(_progress({8, 15, 20}).isWorksheetModuleUnlocked(4), isTrue);
    expect(_progress({8, 15, 20}).worksheetModuleUnlockLabel(4), 'Unlocked');
    expect(_progress({8, 15, 20}).isWorksheetModuleUnlocked(5), isFalse);
    expect(_progress({8, 15, 20, 25}).isWorksheetModuleUnlocked(5), isTrue);
    expect(
      _progress({8, 15, 20, 25}).isWorksheetModuleUnlocked(6),
      isFalse,
    );
    expect(
      _progress({8, 15, 20, 25, 30}).isWorksheetModuleUnlocked(6),
      isTrue,
    );
    expect(
      _progress({8, 15, 20, 25, 30}).isWorksheetModuleUnlocked(7),
      isFalse,
    );
    expect(
      _progress({8, 15, 20, 25, 30, 35}).isWorksheetModuleUnlocked(7),
      isTrue,
    );

    final throughModuleSeven = {8, 15, 20, 25, 30, 35};
    expect(
      _progress({...throughModuleSeven, 41}).isWorksheetModuleUnlocked(8),
      isFalse,
    );
    expect(
      _progress({...throughModuleSeven, 42}).isWorksheetModuleUnlocked(8),
      isFalse,
    );
    expect(
      _progress({...throughModuleSeven, 41, 42}).isWorksheetModuleUnlocked(8),
      isTrue,
    );
    expect(
      _progress({...throughModuleSeven, 41, 42}).worksheetModuleUnlockLabel(8),
      'Unlocked',
    );
    expect(
        _progress({8, 15, 20, 25, 30, 35, 41, 42}).isWorksheetModuleUnlocked(8),
        isTrue);
    expect(newStudent.isWorksheetModuleUnlocked(0), isFalse);
    expect(newStudent.isWorksheetModuleUnlocked(9), isFalse);
  });

  testWidgets('locked modules cannot be opened from the Modules screen',
      (tester) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(800, 600);

    expect(worksheetTitles, hasLength(67));
    expect(
      worksheetTitles.take(3),
      [
        'Adding Similar Fractions',
        'Subtracting Similar Fractions',
        'Adding and Subtracting Mixed Numbers',
      ],
    );
    expect(worksheetTitles.last, 'Dividing Integers');
    for (var moduleIndex = 0;
        moduleIndex < worksheetModuleIds.length;
        moduleIndex++) {
      final moduleLessons = worksheetLessons
          .where((lesson) => lesson.moduleId == worksheetModuleIds[moduleIndex])
          .toList();
      expect(moduleLessons, isNotEmpty);
      expect(
        moduleLessons.every(
          (lesson) => worksheetModuleIndex(lesson.number) == moduleIndex,
        ),
        isTrue,
      );
    }

    await tester.pumpWidget(const MaterialApp(home: ModulesScreen()));
    await tester.pumpAndSettle();
    expect(find.text('Unlocked'), findsOneWidget);

    for (var moduleIndex = 1;
        moduleIndex < worksheetModuleNames.length;
        moduleIndex++) {
      final moduleName = worksheetModuleNames[moduleIndex];
      await tester.scrollUntilVisible(
        find.text(moduleName),
        250,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text(moduleName));
      await tester.pumpAndSettle();
      expect(find.byType(ModulesScreen), findsOneWidget);
      expect(find.text('Locked — complete the required stages to unlock.'),
          findsWidgets);
      expect(
        find.text(
          UserProgress.worksheetModuleRequirementLabel(moduleIndex + 1),
        ),
        findsOneWidget,
      );
    }
    final navigator = Navigator.of(tester.element(find.byType(ModulesScreen)));
    unawaited(
      navigator.push<void>(
        MaterialPageRoute<void>(
          builder: (_) => ModuleLessonScreen(
            module: {
              'id': worksheetModuleIds[1],
              'name': worksheetModuleNames[1],
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.text('Could not verify module access. Please try again.'),
      findsOneWidget,
    );
    expect(find.text('Worked Example'), findsNothing);
    await tester.tap(find.text('Back'));
    await tester.pumpAndSettle();

    await tester.drag(find.byType(Scrollable).first, const Offset(0, 2000));
    await tester.pumpAndSettle();
    await tester.tap(find.text(worksheetModuleNames.first));
    await tester.pumpAndSettle();
    expect(find.byType(ModuleLessonScreen), findsOneWidget);
    expect(find.text(worksheetLessons.first.title), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
