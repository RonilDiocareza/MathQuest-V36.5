import 'dart:async';
import 'dart:ui' as ui;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../services/leaderboard_service.dart';
import '../widgets/custom_button.dart';
import '../widgets/math_background.dart';

class LeaderboardScreen extends StatefulWidget {
  const LeaderboardScreen({super.key});

  @override
  State<LeaderboardScreen> createState() => _LeaderboardScreenState();
}

class _LeaderboardScreenState extends State<LeaderboardScreen> {
  StreamSubscription<List<LeaderboardEntry>>? _topSubscription;

  StreamSubscription<LeaderboardEntry?>? _currentSubscription;

  List<LeaderboardEntry> _entries = const [];

  LeaderboardEntry? _currentEntry;

  Object? _streamError;

  Object? _rankError;

  int? _currentRank;

  int _rankRequest = 0;

  bool _loading = true;

  bool _rankLoading = true;

  String? get _uid => AuthService.currentUser?.uid;

  @override
  void initState() {
    super.initState();
    _start();
  }

  void _start() {
    final uid = _uid;

    debugPrint(
      '========================================',
    );

    debugPrint(
      'LEADERBOARD SCREEN START',
    );

    debugPrint(
      'Authenticated: '
      '${uid != null && uid.isNotEmpty}',
    );

    debugPrint(
      'UID: '
      '${uid == null || uid.isEmpty ? 'none' : uid}',
    );

    debugPrint(
      '========================================',
    );

    if (uid == null || uid.isEmpty) {
      if (!mounted) return;

      setState(() {
        _loading = false;
        _rankLoading = false;
        _streamError = StateError(
          'Sign in to view the leaderboard.',
        );
      });

      return;
    }

    _topSubscription?.cancel();
    _currentSubscription?.cancel();

    setState(() {
      _loading = true;
      _rankLoading = true;
      _streamError = null;
      _rankError = null;
      _currentRank = null;
    });

    _topSubscription = LeaderboardService.watchTopEntries().listen(
      (entries) {
        debugPrint(
          'Leaderboard screen received '
          '${entries.length} entries.',
        );

        if (!mounted) return;

        setState(() {
          _entries = entries;
          _loading = false;
          _streamError = null;
        });

        _refreshRank();
      },
      onError: (Object error) {
        debugPrint(
          '========================================',
        );

        debugPrint(
          'LEADERBOARD SCREEN ERROR',
        );

        debugPrint(
          'Error: $error',
        );

        debugPrint(
          '========================================',
        );

        if (!mounted) return;

        setState(() {
          _loading = false;
          _streamError = error;
        });
      },
    );

    _currentSubscription = LeaderboardService.watchCurrentEntry().listen(
      (entry) {
        debugPrint(
          'Current leaderboard entry received: '
          '${entry?.displayName ?? 'none'}',
        );

        if (!mounted) return;

        setState(() {
          _currentEntry = entry;
        });

        _refreshRank();
      },
      onError: (Object error) {
        debugPrint(
          'Current leaderboard entry error: $error',
        );

        if (!mounted) return;

        setState(() {
          _currentEntry = null;
          _rankLoading = false;
          _streamError = error;
        });
      },
    );

    unawaited(_ensureCurrentEntry());
  }

  Future<void> _ensureCurrentEntry() async {
    try {
      await LeaderboardService.ensureCurrentEntry();
    } catch (error, stackTrace) {
      debugPrint('Unable to initialize leaderboard entry: $error');
      debugPrintStack(stackTrace: stackTrace);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Could not create your leaderboard record. Check that your '
            'student account is approved and try again.',
          ),
        ),
      );
    }
  }

  Future<void> _refreshRank() async {
    final entry = _currentEntry;

    final request = ++_rankRequest;

    if (entry == null) {
      if (!mounted || request != _rankRequest) {
        return;
      }

      setState(() {
        _currentRank = null;
        _rankLoading = false;
        _rankError = null;
      });

      return;
    }

    if (mounted) {
      setState(() {
        _rankLoading = true;
        _rankError = null;
      });
    }

    try {
      final rank = await LeaderboardService.getRank();

      if (!mounted || request != _rankRequest) {
        return;
      }

      setState(() {
        _currentRank = rank;
        _rankLoading = false;
        _rankError = null;
      });
    } catch (error) {
      debugPrint(
        'Unable to calculate leaderboard rank: '
        '$error',
      );

      if (!mounted || request != _rankRequest) {
        return;
      }

      setState(() {
        _rankError = error;
        _rankLoading = false;
      });
    }
  }

  Future<void> _retry() async {
    await _topSubscription?.cancel();
    await _currentSubscription?.cancel();

    _topSubscription = null;
    _currentSubscription = null;

    if (!mounted) return;

    setState(() {
      _loading = true;
      _rankLoading = true;
      _streamError = null;
      _rankError = null;
      _currentRank = null;
      _currentEntry = null;
      _entries = const [];
    });

    _start();
  }

  @override
  void dispose() {
    _rankRequest++;

    _topSubscription?.cancel();
    _currentSubscription?.cancel();

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final uid = _uid;
    final displayEntries = LeaderboardService.sortEntries([
      ..._entries.where((entry) => entry.uid != _currentEntry?.uid),
      if (_currentEntry != null) _currentEntry!,
    ]);

    final displayName = _currentEntry?.displayName ?? 'Not ranked yet';

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        leading: const SizedBox(width: 56),
        title: const Text(
          'Leaderboard',
          style: TextStyle(color: Colors.black),
        ),
      ),
      body: MathBackground(
        child: Stack(
          children: [
            Positioned.fill(
              child: BackdropFilter(
                filter: ui.ImageFilter.blur(sigmaX: 1.5, sigmaY: 1.5),
                child: Container(color: Colors.transparent),
              ),
            ),
            SafeArea(
              child: Column(
                children: [
                  Expanded(
                    child: _streamError != null
                        ? _buildError()
                        : _loading
                            ? const Center(
                                child: CircularProgressIndicator(),
                              )
                            : Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  _buildCurrentSummary(displayName),
                                  Padding(
                                    padding: const EdgeInsets.fromLTRB(
                                      20,
                                      8,
                                      20,
                                      12,
                                    ),
                                    child: const Text(
                                      'All Players',
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.bold,
                                        letterSpacing: 1.2,
                                        color: Colors.black,
                                      ),
                                    ),
                                  ),
                                  Expanded(
                                    child: displayEntries.isEmpty
                                        ? const Center(
                                            child: Text('No scores yet.'),
                                          )
                                        : ListView.builder(
                                            padding: const EdgeInsets.fromLTRB(
                                              16,
                                              0,
                                              16,
                                              16,
                                            ),
                                            itemCount: displayEntries.length,
                                            itemBuilder: (context, index) {
                                              final entry =
                                                  displayEntries[index];
                                              return _buildEntryRow(
                                                entry,
                                                index + 1,
                                                isCurrent: entry.uid == uid,
                                              );
                                            },
                                          ),
                                  ),
                                  Transform.translate(
                                    offset: const Offset(0, -35),
                                    child: Center(
                                      child: CustomButton(
                                        text: 'Back',
                                        onPressed: () {
                                          if (Navigator.canPop(context)) {
                                            Navigator.pop(context);
                                          } else {
                                            Navigator.pushReplacementNamed(
                                                context, '/home');
                                          }
                                        },
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 16),
                                ],
                              ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCurrentSummary(
    String displayName,
  ) {
    return Card(
      margin: const EdgeInsets.fromLTRB(
        16,
        16,
        16,
        8,
      ),
      color: const Color(0xFFFFE4BC),
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            const CircleAvatar(
              backgroundColor: Color(0xFFD09F5C),
              child: Icon(
                Icons.person,
                color: Colors.white,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    displayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(_rankLabel),
                ],
              ),
            ),
            Text(
              _formatScore(
                _currentEntry?.totalScore ?? 0,
              ),
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Color(0xFF744411),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String get _rankLabel {
    if (_rankLoading) {
      return 'Your Rank: loading...';
    }

    if (_rankError != null) {
      return 'Your Rank: unavailable';
    }

    return 'Your Rank: '
        '${_currentRank == null ? '—' : '#$_currentRank'}';
  }

  Widget _buildEntryRow(
    LeaderboardEntry entry,
    int? rank, {
    required bool isCurrent,
  }) {
    final rankLabel = rank == null ? '—' : '$rank';

    final medal = switch (rank) {
      1 => '🥇',
      2 => '🥈',
      3 => '🥉',
      _ => null,
    };

    return Card(
      margin: const EdgeInsets.symmetric(
        vertical: 4,
      ),
      color: isCurrent ? const Color(0xFFF4DDB8) : const Color(0xFFFFF8EB),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(
          color: Color(0xFF785333),
          width: 1.3,
        ),
      ),
      elevation: 3,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 13,
        ),
        child: Row(
          children: [
            SizedBox(
              width: 55,
              child: Text(
                medal == null ? rankLabel : '$medal $rankLabel',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            Expanded(
              child: Text(
                entry.displayName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
                ),
              ),
            ),
            if (entry.highestCompletedLevel > 0) ...[
              const SizedBox(width: 8),
              Text(
                'Stage ${entry.highestCompletedLevel}',
                style: const TextStyle(
                  color: Color(0xFF785333),
                  fontSize: 12,
                ),
              ),
            ],
            const SizedBox(width: 12),
            Text(
              _formatScore(
                entry.totalScore,
              ),
              style: const TextStyle(
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.cloud_off,
              size: 48,
              color: Color(0xFF785333),
            ),
            const SizedBox(height: 12),
            const Text(
              'Could not load the leaderboard.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _friendlyError(),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: _retry,
              child: const Text('Try Again'),
            ),
          ],
        ),
      ),
    );
  }

  String _friendlyError() {
    final error = _streamError;

    if (error is FirebaseException) {
      switch (error.code) {
        case 'permission-denied':
          return 'Firebase denied access to the leaderboard. Check Firestore rules.';
        case 'failed-precondition':
          return 'Firestore requires an index for the leaderboard query.';
        case 'unauthenticated':
          return 'Your Firebase session is no longer authenticated.';
        case 'unavailable':
          return 'Firebase is temporarily unavailable. Check your internet connection.';
        case 'not-found':
          return 'The leaderboard data could not be found.';
        default:
          return 'Firebase error: ${error.code}';
      }
    }

    return 'The leaderboard is temporarily unavailable. Please try again.';
  }

  String _formatScore(int score) {
    return score.toString().replaceAllMapped(
          RegExp(r'\B(?=(\d{3})+(?!\d))'),
          (_) => ',',
        );
  }
}
