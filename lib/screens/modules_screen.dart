import 'package:flutter/material.dart';
import '../services/user_progress_service.dart';
import '../widgets/custom_button.dart';
import '../widgets/math_background.dart';
import '../worksheet_lesson_data.dart';
import 'module_lesson_screen.dart';

class ModulesScreen extends StatefulWidget {
  const ModulesScreen({super.key});

  @override
  State<ModulesScreen> createState() => _ModulesScreenState();
}

class _ModulesScreenState extends State<ModulesScreen> {
  // Click protection flag
  bool _isProcessingClick = false;
  bool _isLoadingProgress = true;
  UserProgress? _progress;

  final List<Map<String, String>> modules = List.generate(
    worksheetModuleIds.length,
    (index) => {
      'id': worksheetModuleIds[index],
      'semester': worksheetModuleSemesters[index],
      'name': worksheetModuleNames[index],
      'description': 'Follow worksheets in the reference order.',
      'icon': const ['½', '×', '🔢', '📦', '⏱', '📐', '📋', '➕'][index],
      'topic': 'Worksheets ${[
        '1–8',
        '9–13',
        '14–26',
        '27–34',
        '35–37',
        '38–47',
        '48–51',
        '52–67',
      ][index]}',
      'lesson': const [
        'Similar and unlike fractions, mixed numbers, and word problems.',
        'Fractions and mixed numbers.',
        'Addition, subtraction, multiplication, and division.',
        'Solid figures and plane figures.',
        'Identify and calculate speed, distance, and time.',
        'Composite areas and surface areas of solid figures.',
        'List and count possible outcomes systematically.',
        'Add, subtract, multiply, and divide integers.',
      ][index],
    },
    growable: false,
  );

  @override
  void initState() {
    super.initState();
    _loadProgress();
  }

  Future<void> _loadProgress() async {
    try {
      final progress = await UserProgressService.getCurrentUserProgress(
        forceRefresh: true,
      );
      if (!mounted) return;
      setState(() {
        _progress = progress;
        _isLoadingProgress = false;
      });
    } catch (error, stackTrace) {
      debugPrint('Unable to load module unlock progress: $error');
      debugPrintStack(stackTrace: stackTrace);
      if (!mounted) return;
      setState(() {
        _progress = null;
        _isLoadingProgress = false;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
                'Could not load module progress. Only Module 1 is available.'),
          ),
        );
      });
    }
  }

  bool _canOpenModule(int index) =>
      index == 0 ||
      (!_isLoadingProgress &&
          (_progress?.isWorksheetModuleUnlocked(index + 1) ?? false));

  void _selectModule(Map<String, String> module, int index) {
    // Prevent multiple rapid clicks
    if (_isProcessingClick || !_canOpenModule(index)) return;

    _isProcessingClick = true;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ModuleLessonScreen(module: module),
      ),
    ).whenComplete(() {
      if (mounted) {
        _isProcessingClick = false;
        _loadProgress();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: MathBackground(
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(left: 18, top: 8, bottom: 8),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFF8B5E36).withValues(alpha: 0.45),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.18),
                        width: 1,
                      ),
                    ),
                    child: const Text(
                      'Modules',
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        color: Colors.black,
                        height: 1.1,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 25),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFF9B6B30),
                    borderRadius: BorderRadius.circular(18),
                    border:
                        Border.all(color: Colors.white.withValues(alpha: 0.55)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Learning Map',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                          color: Colors.black,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Fractions → Decimals → Figures and measurement → Outcomes → Integers',
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.white.withValues(alpha: 0.95),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                Expanded(
                  child: ListView.builder(
                    itemCount: modules.length,
                    itemBuilder: (context, index) {
                      final module = modules[index];
                      final isUnlocked = _canOpenModule(index);
                      final unlockLabel = _progress?.worksheetModuleUnlockLabel(
                            index + 1,
                          ) ??
                          UserProgress.worksheetModuleRequirementLabel(
                            index + 1,
                          );
                      return GestureDetector(
                        onTap: isUnlocked
                            ? () => _selectModule(module, index)
                            : null,
                        child: Container(
                          margin: const EdgeInsets.only(bottom: 15),
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            color: isUnlocked
                                ? const Color(0xFFF3D5AA)
                                : Colors.grey[300],
                            borderRadius: BorderRadius.circular(20),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.15),
                                blurRadius: 8,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Text(
                                    module['icon']!,
                                    style: const TextStyle(fontSize: 32),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          module['semester']!,
                                          style: const TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.w700,
                                            color: Color(0xFF725A41),
                                          ),
                                        ),
                                        const SizedBox(height: 3),
                                        Text(
                                          module['name']!,
                                          style: const TextStyle(
                                            fontSize: 18,
                                            fontWeight: FontWeight.bold,
                                            color: Colors.black,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          isUnlocked
                                              ? module['description']!
                                              : 'Locked — complete the required stages to unlock.',
                                          textAlign: TextAlign.justify,
                                          style: const TextStyle(
                                            fontSize: 13,
                                            color: Color(0xFF6B7280),
                                          ),
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        const SizedBox(height: 8),
                                        Text(
                                          'Topic: ${module['topic']!}',
                                          style: const TextStyle(
                                            fontSize: 11,
                                            color: Color(0xFF6B7280),
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          'Lesson: ${module['lesson']!}',
                                          style: const TextStyle(
                                            fontSize: 11,
                                            color: Color(0xFF6B7280),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Icon(
                                    isUnlocked
                                        ? Icons.arrow_forward
                                        : Icons.lock,
                                    color: const Color(0xFF2B3B5A),
                                    size: 20,
                                  ),
                                ],
                              ),
                              Padding(
                                padding:
                                    const EdgeInsets.only(left: 44, top: 8),
                                child: Text(
                                  unlockLabel,
                                  key: ValueKey(
                                    'module-unlock-label-${index + 1}',
                                  ),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  softWrap: true,
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    color: Color(0xFF725A41),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CustomButton(
              text: 'Back',
              onPressed: () => Navigator.pop(context),
            ),
            const SizedBox(height: 10),
          ],
        ),
      ),
    );
  }
}
