import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class LeaderboardEntry {
  final String uid;
  final String displayName;
  final int totalScore;
  final int highestCompletedLevel;
  final DateTime? createdAt;

  const LeaderboardEntry({
    required this.uid,
    required this.displayName,
    required this.totalScore,
    this.highestCompletedLevel = 0,
    this.createdAt,
  });
}

class LeaderboardService {
  static FirebaseFirestore? get _firestoreOrNull {
    try {
      return FirebaseFirestore.instance;
    } on FirebaseException {
      return null;
    } catch (_) {
      return null;
    }
  }

  static FirebaseAuth? get _authOrNull {
    try {
      return FirebaseAuth.instance;
    } on FirebaseException {
      return null;
    } catch (_) {
      return null;
    }
  }

  static const String collectionName = 'leaderboard';

  static CollectionReference<Map<String, dynamic>> get _collection {
    final firestore = _firestoreOrNull ??
        (throw StateError(
          'Firebase Firestore is not available because Firebase is not initialized.',
        ));
    return firestore.collection(collectionName);
  }

  static Stream<List<LeaderboardEntry>> watchTopEntries({
    int? limit,
  }) {
    return _collection.snapshots().map((snapshot) {
      final entries = sortEntries(
        snapshot.docs.map(_entryFromDocument).whereType<LeaderboardEntry>(),
      );
      return limit == null ? entries : entries.take(limit).toList();
    });
  }

  static List<LeaderboardEntry> sortEntries(
    Iterable<LeaderboardEntry> entries,
  ) {
    final sortedEntries = entries.toList()
      ..sort((first, second) {
        final scoreOrder = second.totalScore.compareTo(first.totalScore);
        if (scoreOrder != 0) return scoreOrder;

        final firstCreatedAt = first.createdAt;
        final secondCreatedAt = second.createdAt;
        if (firstCreatedAt != null && secondCreatedAt != null) {
          final creationOrder = firstCreatedAt.compareTo(secondCreatedAt);
          if (creationOrder != 0) return creationOrder;
        } else if (firstCreatedAt == null && secondCreatedAt != null) {
          return -1;
        } else if (firstCreatedAt != null && secondCreatedAt == null) {
          return 1;
        }

        return first.uid.compareTo(second.uid);
      });
    return sortedEntries;
  }

  static Stream<LeaderboardEntry?> watchCurrentEntry() {
    final user = _authOrNull?.currentUser;

    if (user == null) {
      return Stream.value(null);
    }

    return _collection.doc(user.uid).snapshots().map((document) {
      if (!document.exists) {
        return null;
      }

      return _entryFromDocument(document);
    });
  }

  static LeaderboardEntry? _entryFromDocument(
    DocumentSnapshot<Map<String, dynamic>> document,
  ) {
    final data = document.data();

    if (data == null) {
      return null;
    }

    final uid = (data['uid'] ?? document.id).toString();

    final displayName =
        (data['displayName'] ?? data['displayname'] ?? data['name'] ?? 'Player')
            .toString();

    final rawScore = data['totalScore'] ?? data['totalscore'] ?? 0;

    int totalScore;

    if (rawScore is int) {
      totalScore = rawScore;
    } else if (rawScore is num) {
      totalScore = rawScore.toInt();
    } else {
      totalScore = int.tryParse(rawScore.toString()) ?? 0;
    }

    return LeaderboardEntry(
      uid: uid,
      displayName: displayName,
      totalScore: totalScore,
      highestCompletedLevel:
          (data['highestCompletedLevel'] as num?)?.toInt() ?? 0,
      createdAt: _dateTimeFromValue(data['createdAt']),
    );
  }

  static DateTime? _dateTimeFromValue(Object? value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    if (value is String) return DateTime.tryParse(value);
    return null;
  }

  static int _progressScore(Map<String, dynamic> userData) {
    final progress = userData['progress'] as Map<String, dynamic>? ?? {};
    final completedLevels = <int>{};
    for (final value in progress['completedLevels'] as List<dynamic>? ?? []) {
      final level = int.tryParse(value.toString());
      if (level != null && level >= 1 && level <= 60) {
        completedLevels.add(level);
      }
    }

    final rawFinalScores =
        progress['gameModeFinalScores'] as Map<String, dynamic>? ?? {};
    final finalScores = <int, int>{};
    for (final entry in rawFinalScores.entries) {
      final level = int.tryParse(entry.key);
      final score = entry.value;
      if (level != null &&
          level >= 1 &&
          level <= 60 &&
          score is int &&
          score >= 0 &&
          score <= 70) {
        finalScores[level] = score;
      }
    }

    final savedScore = userData['gameScore'];
    final baseline = userData['scoreBaseline'];
    final earned = userData['scoreEarned'];
    final storedScore = savedScore is num
        ? savedScore.toInt()
        : baseline is num && earned is num
            ? baseline.toInt() + earned.toInt()
            : 0;
    final finalGameModeScore =
        finalScores.values.fold<int>(0, (total, score) => total + score);
    final legacyCompletedLevelScore = completedLevels
            .where((level) => !finalScores.containsKey(level))
            .length *
        10;
    final progressScore = finalGameModeScore + legacyCompletedLevelScore;
    return storedScore > progressScore ? storedScore : progressScore;
  }

  static int _highestCompletedLevel(Map<String, dynamic> userData) {
    final progress = userData['progress'] as Map<String, dynamic>? ?? {};
    final completedLevels =
        (progress['completedLevels'] as List<dynamic>? ?? [])
            .map((value) => int.tryParse(value.toString()))
            .whereType<int>()
            .where((level) => level >= 1 && level <= 60)
            .toList();
    if (completedLevels.isNotEmpty) {
      return completedLevels.reduce((a, b) => a > b ? a : b);
    }
    final unlocked = progress['unlockedLevels'];
    return unlocked is num ? unlocked.toInt() : 0;
  }

  static Future<void> createRegistrationEntry({
    required String uid,
    required String displayName,
  }) async {
    final firestore = _firestoreOrNull ??
        (throw StateError(
          'Firebase Firestore is not available because Firebase is not initialized.',
        ));
    final userRef = firestore.collection('users').doc(uid);
    final leaderboardRef = _collection.doc(uid);
    await firestore.runTransaction((transaction) async {
      final userSnapshot = await transaction.get(userRef);
      if (!userSnapshot.exists) {
        throw StateError('User profile not found.');
      }
      final userData = userSnapshot.data();
      if (userData == null ||
          userData['role']?.toString().toLowerCase() != 'student') {
        throw StateError('Only student accounts can join the leaderboard.');
      }

      final leaderboardSnapshot = await transaction.get(leaderboardRef);
      if (leaderboardSnapshot.exists) {
        final entryData = leaderboardSnapshot.data();
        if (entryData != null && entryData['createdAt'] == null) {
          transaction.update(leaderboardRef, {
            'createdAt': userData['createdAt'] ?? FieldValue.serverTimestamp(),
            'updatedAt': FieldValue.serverTimestamp(),
          });
        }
        return;
      }

      transaction.set(leaderboardRef, {
        'uid': uid,
        'displayName': (userData['name'] ?? displayName).toString(),
        'totalScore': 0,
        'createdAt': userData['createdAt'] ?? FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    });
  }

  static Future<void> ensureCurrentEntry() async {
    final user = _authOrNull?.currentUser;
    if (user == null) {
      throw StateError('No logged-in user.');
    }
    final firestore = _firestoreOrNull ??
        (throw StateError(
          'Firebase Firestore is not available because Firebase is not initialized.',
        ));
    final userRef = firestore.collection('users').doc(user.uid);
    final leaderboardRef = _collection.doc(user.uid);
    await firestore.runTransaction((transaction) async {
      final userSnapshot = await transaction.get(userRef);
      if (!userSnapshot.exists) {
        throw StateError('User profile not found.');
      }

      final userData = userSnapshot.data();
      if (userData == null ||
          userData['role']?.toString().toLowerCase() != 'student' ||
          userData['status']?.toString().toLowerCase() != 'approved') {
        throw StateError('Only approved students can join the leaderboard.');
      }

      final leaderboardSnapshot = await transaction.get(leaderboardRef);
      final displayName = (userData['name'] ?? 'Player').toString();
      final profileCreatedAt = userData['createdAt'];
      final createdAt = profileCreatedAt ?? FieldValue.serverTimestamp();
      if (leaderboardSnapshot.exists) {
        final existingData = leaderboardSnapshot.data();
        if (existingData == null) {
          throw StateError('Leaderboard entry data is empty.');
        }

        final updates = <String, dynamic>{};
        if (existingData['uid'] != user.uid) {
          updates['uid'] = user.uid;
        }
        if (existingData['displayName'] != displayName) {
          updates['displayName'] = displayName;
        }
        if (existingData['createdAt'] != profileCreatedAt &&
            profileCreatedAt != null) {
          updates['createdAt'] = profileCreatedAt;
        } else if (existingData['createdAt'] is! Timestamp &&
            profileCreatedAt == null) {
          updates['createdAt'] = FieldValue.serverTimestamp();
        }
        if (updates.isNotEmpty) {
          updates['updatedAt'] = FieldValue.serverTimestamp();
          transaction.update(leaderboardRef, updates);
        }
        return;
      }

      transaction.set(leaderboardRef, {
        'uid': user.uid,
        'displayName': displayName,
        'totalScore': 0,
        'createdAt': createdAt,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    });
  }

  static Future<void> initializeApprovedStudentEntry(String uid) async {
    final admin = _authOrNull?.currentUser;
    if (admin == null) {
      throw StateError('No logged-in admin.');
    }

    final firestore = _firestoreOrNull ??
        (throw StateError(
          'Firebase Firestore is not available because Firebase is not initialized.',
        ));
    final adminRef = firestore.collection('users').doc(admin.uid);
    final studentRef = firestore.collection('users').doc(uid);
    final leaderboardRef = _collection.doc(uid);
    await firestore.runTransaction((transaction) async {
      final adminSnapshot = await transaction.get(adminRef);
      final studentSnapshot = await transaction.get(studentRef);
      final leaderboardSnapshot = await transaction.get(leaderboardRef);

      if (adminSnapshot.data()?['role']?.toString().toLowerCase() != 'admin') {
        throw StateError('Only admins can initialize student entries.');
      }
      final studentData = studentSnapshot.data();
      if (!studentSnapshot.exists ||
          studentData?['role']?.toString().toLowerCase() != 'student' ||
          studentData?['status']?.toString().toLowerCase() != 'approved') {
        throw StateError('Student account is not approved.');
      }
      if (leaderboardSnapshot.exists) {
        final entryData = leaderboardSnapshot.data();
        if (entryData != null && entryData['createdAt'] == null) {
          transaction.update(leaderboardRef, {
            'createdAt':
                studentData?['createdAt'] ?? FieldValue.serverTimestamp(),
            'updatedAt': FieldValue.serverTimestamp(),
          });
        }
        return;
      }

      transaction.set(leaderboardRef, {
        'uid': uid,
        'displayName': (studentData?['name'] ?? 'Player').toString(),
        'totalScore': 0,
        'createdAt': studentData?['createdAt'] ?? FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    });
  }

  static Future<void> addPoints(int points) async {
    if (points != 5 && points != 10) {
      throw ArgumentError.value(
        points,
        'points',
        'Leaderboard awards must be 5 or 10 points.',
      );
    }

    await _addScore(points);
  }

  static Future<void> _addScore(int points) async {
    final user = _authOrNull?.currentUser;

    if (user == null) {
      throw Exception('No logged-in user.');
    }

    final firestore = _firestoreOrNull ??
        (throw StateError(
          'Firebase Firestore is not available because Firebase is not initialized.',
        ));
    final userRef = firestore.collection('users').doc(user.uid);

    final leaderboardRef = _collection.doc(user.uid);

    final userSnapshot = await userRef.get();

    if (!userSnapshot.exists) {
      throw Exception('User profile not found.');
    }

    final userData = userSnapshot.data();

    if (userData == null) {
      throw Exception('User profile data is empty.');
    }

    final role = userData['role']?.toString().toLowerCase();

    final status = userData['status']?.toString().toLowerCase();

    if (role != 'student') {
      throw Exception(
        'Only student accounts can have leaderboard scores.',
      );
    }

    if (status != 'approved') {
      throw Exception(
        'Student account is not approved.',
      );
    }

    final displayName = (userData['name'] ?? 'Player').toString();

    await firestore.runTransaction(
      (transaction) async {
        final leaderboardSnapshot = await transaction.get(leaderboardRef);

        if (!leaderboardSnapshot.exists) {
          transaction.set(
            leaderboardRef,
            {
              'uid': user.uid,
              'displayName': displayName,
              'totalScore': points,
              'createdAt':
                  userData['createdAt'] ?? FieldValue.serverTimestamp(),
              'updatedAt': FieldValue.serverTimestamp(),
            },
          );

          return;
        }

        final existingData = leaderboardSnapshot.data() ?? {};

        final rawScore =
            existingData['totalScore'] ?? existingData['totalscore'] ?? 0;

        int oldScore;

        if (rawScore is int) {
          oldScore = rawScore;
        } else if (rawScore is num) {
          oldScore = rawScore.toInt();
        } else {
          oldScore = int.tryParse(rawScore.toString()) ?? 0;
        }

        transaction.update(
          leaderboardRef,
          {
            'uid': user.uid,
            'displayName': displayName,
            'totalScore': oldScore + points,
            'createdAt': existingData['createdAt'] ??
                userData['createdAt'] ??
                FieldValue.serverTimestamp(),
            'updatedAt': FieldValue.serverTimestamp(),
          },
        );
      },
    );
  }

  static Future<int?> getRank() async {
    final user = _authOrNull?.currentUser;

    if (user == null) {
      return null;
    }

    final document = await _collection.doc(user.uid).get();

    if (!document.exists) {
      return null;
    }

    final entry = _entryFromDocument(document);

    if (entry == null) {
      return null;
    }

    final entries = await _collection.get();
    final sortedEntries = sortEntries(
      entries.docs.map(_entryFromDocument).whereType<LeaderboardEntry>(),
    );
    final rank =
        sortedEntries.indexWhere((candidate) => candidate.uid == user.uid);
    return rank < 0 ? null : rank + 1;
  }

  static Future<int> backfillEntries() async {
    final currentUser = _authOrNull?.currentUser;

    if (currentUser == null) {
      throw Exception('No logged-in user.');
    }

    final firestore = _firestoreOrNull ??
        (throw StateError(
          'Firebase Firestore is not available because Firebase is not initialized.',
        ));

    final adminSnapshot =
        await firestore.collection('users').doc(currentUser.uid).get();

    if (!adminSnapshot.exists) {
      throw Exception('Admin account not found.');
    }

    final adminData = adminSnapshot.data();

    if (adminData == null ||
        adminData['role']?.toString().toLowerCase() != 'admin') {
      throw Exception(
        'Only admins can sync the leaderboard.',
      );
    }

    final usersSnapshot = await firestore.collection('users').get();

    final leaderboardSnapshot = await _collection.get();

    final existingScores = <String, int>{};
    final existingCreationTimes = <String, Object?>{};

    for (final document in leaderboardSnapshot.docs) {
      final data = document.data();

      final rawScore = data['totalScore'] ?? data['totalscore'] ?? 0;

      int score;

      if (rawScore is int) {
        score = rawScore;
      } else if (rawScore is num) {
        score = rawScore.toInt();
      } else {
        score = int.tryParse(rawScore.toString()) ?? 0;
      }

      existingScores[document.id] = score;
      existingCreationTimes[document.id] = data['createdAt'];
    }

    final students = usersSnapshot.docs.where(
      (document) {
        final data = document.data();

        final role = data['role']?.toString().toLowerCase();

        return role == 'student';
      },
    ).toList();

    var processed = 0;
    for (var start = 0; start < students.length; start += 400) {
      final end = start + 400 < students.length ? start + 400 : students.length;

      final batch = firestore.batch();

      for (final userDocument in students.sublist(start, end)) {
        final data = userDocument.data();

        final uid = userDocument.id;

        final displayName = (data['name'] ?? 'Player').toString();

        final score = [
          existingScores[uid] ?? 0,
          _progressScore(data),
        ].reduce((left, right) => left > right ? left : right);
        final highestCompletedLevel = _highestCompletedLevel(data);

        final leaderboardRef = _collection.doc(uid);

        batch.set(
          leaderboardRef,
          {
            'uid': uid,
            'displayName': displayName,
            'totalScore': score,
            'highestCompletedLevel': highestCompletedLevel,
            'createdAt': data['createdAt'] ??
                existingCreationTimes[uid] ??
                FieldValue.serverTimestamp(),
            'updatedAt': FieldValue.serverTimestamp(),
          },
          SetOptions(merge: true),
        );
      }

      await batch.commit();
      processed += end - start;
    }
    return processed;
  }
}
