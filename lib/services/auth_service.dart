import 'dart:convert';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:crypto/crypto.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/user_account.dart';
import 'leaderboard_service.dart';

class AuthService {
  static FirebaseAuth get _auth {
    try {
      return FirebaseAuth.instance;
    } on FirebaseException {
      throw StateError(
          'Firebase Auth is not available because Firebase is not initialized.');
    } catch (_) {
      throw StateError(
          'Firebase Auth is not available because Firebase is not initialized.');
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

  static CollectionReference<Map<String, dynamic>> get _sessions {
    try {
      return FirebaseFirestore.instance.collection('activeSessions');
    } on FirebaseException {
      throw StateError(
          'Firebase Firestore is not available because Firebase is not initialized.');
    } catch (_) {
      throw StateError(
          'Firebase Firestore is not available because Firebase is not initialized.');
    }
  }

  static const _deviceIdKey = 'mathquest_device_id';
  static const _sessionIdKeyPrefix = 'mathquest_session_id_';

  static User? get currentUser {
    try {
      return FirebaseAuth.instance.currentUser;
    } on FirebaseException {
      return null;
    } catch (_) {
      return null;
    }
  }

  static Future<UserAccount?> restoreSignedInAccount() async {
    final user = _auth.currentUser;
    if (user == null) return null;

    final uid = user.uid;
    final preferences = await SharedPreferences.getInstance();
    final deviceId = preferences.getString(_deviceIdKey);
    final cachedSessionId = preferences.getString('$_sessionIdKeyPrefix$uid');
    if (deviceId == null ||
        deviceId.length < 16 ||
        cachedSessionId == null ||
        cachedSessionId.isEmpty) {
      await _discardLocalSession(uid);
      return null;
    }

    final sessionSnapshot = await _sessions.doc(uid).get(
          const GetOptions(source: Source.server),
        );
    final session = sessionSnapshot.data();
    if (!sessionSnapshot.exists ||
        session?['deviceId'] != deviceId ||
        session?['sessionId'] != cachedSessionId) {
      debugPrint(
        '[AuthService] Persisted Firebase user has no matching active device '
        'session: uid=$uid, sessionExists=${sessionSnapshot.exists}, '
        'deviceMatches=${session?['deviceId'] == deviceId}, '
        'sessionMatches=${session?['sessionId'] == cachedSessionId}.',
      );
      await _discardLocalSession(uid);
      return null;
    }

    final accountSnapshot = await _users.doc(uid).get(
          const GetOptions(source: Source.server),
        );
    final accountData = accountSnapshot.data();
    final account = accountData == null
        ? null
        : UserAccount.fromJson({...accountData, 'uid': accountSnapshot.id});
    final storedUid = accountData?['uid'];
    final validAccount = account != null &&
        (storedUid == null || storedUid == uid) &&
        account.isApproved &&
        (account.role.toLowerCase() == 'student' ||
            account.isTeacher ||
            account.isAdmin);
    if (!validAccount) {
      debugPrint(
        '[AuthService] Persisted Firebase user has no valid approved account: '
        'uid=$uid, accountExists=${accountSnapshot.exists}, '
        'storedUid=${storedUid ?? '(none)'}, '
        'role=${account?.role ?? '(none)'}, '
        'status=${account?.status ?? '(none)'}.',
      );
      await _releaseLoginSession(uid, deviceId, cachedSessionId);
      await _discardLocalSession(uid);
      return null;
    }

    await preferences.setString('current_user_email', account.email);
    await preferences.setString('current_user_name', account.name);
    await preferences.setString('current_user_role', account.role);
    await preferences.setString('current_user_lrn', account.lrn);
    await preferences.setString('current_user_address', account.address);
    return account;
  }

  static Future<void> _discardLocalSession(String uid) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.remove('$_sessionIdKeyPrefix$uid');
    await _auth.signOut();
  }

  static Future<UserAccount> signIn(String email, String password) async {
    final credential = await _auth.signInWithEmailAndPassword(
      email: email.trim().toLowerCase(),
      password: password,
    );
    final uid = credential.user!.uid;
    String? sessionId;
    String? deviceId;
    try {
      deviceId = await _getDeviceId();
      sessionId = await _claimLoginSession(uid, deviceId);

      final account = await getAccount(uid);
      if (account == null) {
        throw StateError(
          'Your account profile is missing for UID $uid. '
          'Create the users document with this exact ID in the same Firebase project.',
        );
      }
      if (!account.isApproved) {
        throw StateError('Account pending admin approval.');
      }
      final preferences = await SharedPreferences.getInstance();
      await preferences.setString(
        '$_sessionIdKeyPrefix$uid',
        sessionId,
      );
      return account;
    } catch (_) {
      var failedSessionId = sessionId;
      failedSessionId ??= sessionId;
      if (failedSessionId != null && deviceId != null) {
        try {
          await _releaseLoginSession(uid, deviceId, failedSessionId);
        } catch (error, stackTrace) {
          debugPrint('Unable to release failed login session: $error');
          debugPrintStack(stackTrace: stackTrace);
        }
      }
      await _auth.signOut();
      rethrow;
    }
  }

  static Future<UserAccount> register({
    required String email,
    required String password,
    required String name,
    required String address,
    required String lrn,
    required String character,
  }) async {
    final normalizedLrn = lrn.trim();
    if (!RegExp(r'^\d{12}$').hasMatch(normalizedLrn)) {
      throw ArgumentError('LRN must contain exactly 12 digits.');
    }

    final normalizedEmail = email.trim().toLowerCase();
    UserCredential credential;
    var createdAuthUser = false;
    try {
      credential = await _auth.createUserWithEmailAndPassword(
        email: normalizedEmail,
        password: password,
      );
      createdAuthUser = true;
    } on FirebaseAuthException catch (error) {
      if (error.code != 'email-already-in-use') rethrow;
      credential = await _auth.signInWithEmailAndPassword(
        email: normalizedEmail,
        password: password,
      );
    }

    final authUser = credential.user!;
    final account = UserAccount(
      uid: authUser.uid,
      email: normalizedEmail,
      role: 'student',
      status: 'pending',
      name: name.trim(),
      address: address.trim(),
      lrn: normalizedLrn,
      character: character == 'girl' ? 'girl' : 'boy',
    );
    try {
      await _createStudentProfile(
        uid: authUser.uid,
        email: normalizedEmail,
        name: name.trim(),
        address: address.trim(),
        lrn: normalizedLrn,
        character: character,
      );

      try {
        await LeaderboardService.createRegistrationEntry(
          uid: authUser.uid,
          displayName: name,
        );
      } catch (error, stackTrace) {
        debugPrint(
            'Unable to initialize pending student leaderboard entry: $error');
        debugPrintStack(stackTrace: stackTrace);
      }
    } catch (error, stackTrace) {
      if (createdAuthUser) {
        await _removeAuthUserIfProfileWasNotCreated(
          authUser: authUser,
          email: normalizedEmail,
          lrn: normalizedLrn,
        );
      }
      if (error is FirebaseException) {
        debugPrint(
          'Student profile registration failed: plugin=${error.plugin}, '
          'code=${error.code}, message=${error.message ?? '(none)'}.',
        );
        debugPrintStack(stackTrace: stackTrace);
      }
      rethrow;
    } finally {
      try {
        await _auth.signOut();
      } catch (error, stackTrace) {
        debugPrint('Unable to sign out after registration: $error');
        debugPrintStack(stackTrace: stackTrace);
      }
    }

    return account;
  }

  static Future<void> _removeAuthUserIfProfileWasNotCreated({
    required User authUser,
    required String email,
    required String lrn,
  }) async {
    try {
      final profileSnapshot = await _users.doc(authUser.uid).get();
      final profile = profileSnapshot.data();
      if (profileSnapshot.exists &&
          profile?['email'] == email &&
          profile?['lrn'] == lrn &&
          profile?['role'] == 'student') {
        return;
      }
      if (!profileSnapshot.exists) {
        await authUser.delete();
        return;
      }
      debugPrint(
        'Retaining newly created Auth user ${authUser.uid}: a user profile '
        'exists but does not match the attempted registration.',
      );
    } catch (error, stackTrace) {
      debugPrint(
        'Unable to verify or clean up incomplete registration for '
        '${authUser.uid}: $error',
      );
      debugPrintStack(stackTrace: stackTrace);
    }
  }

  static Future<void> _createStudentProfile({
    required String uid,
    required String email,
    required String name,
    required String address,
    required String lrn,
    required String character,
  }) async {
    final firestore = FirebaseFirestore.instance;
    final userRef = _users.doc(uid);
    final indexCollection = firestore.collection('lrnIndexes');
    final legacyIndexRef = indexCollection.doc(lrn);
    final hashedIndexRef =
        indexCollection.doc(sha256.convert(utf8.encode(lrn)).toString());

    await firestore.runTransaction<void>((transaction) async {
      final userSnapshot = await transaction.get(userRef);
      if (userSnapshot.exists) {
        final existing = userSnapshot.data()!;
        if (existing['email'] == email &&
            existing['lrn'] == lrn &&
            existing['role'] == 'student') {
          return;
        }
        throw StateError('This account is already registered.');
      }

      late final DocumentSnapshot<Map<String, dynamic>> hashedIndexSnapshot;
      late final DocumentSnapshot<Map<String, dynamic>> legacyIndexSnapshot;
      try {
        hashedIndexSnapshot = await transaction.get(hashedIndexRef);
        legacyIndexSnapshot = await transaction.get(legacyIndexRef);
      } on FirebaseException catch (error, stackTrace) {
        if (error.code == 'permission-denied') {
          debugPrint(
            'LRN index lookup denied: plugin=${error.plugin}, '
            'code=${error.code}, message=${error.message ?? '(none)'}, '
            'uid=$uid.',
          );
          debugPrintStack(stackTrace: stackTrace);
          throw StateError('This LRN is already registered.');
        }
        rethrow;
      }
      for (final snapshot in [hashedIndexSnapshot, legacyIndexSnapshot]) {
        if (snapshot.exists && snapshot.data()?['uid'] != uid) {
          throw StateError('This LRN is already registered.');
        }
      }

      if (!legacyIndexSnapshot.exists) {
        transaction.set(legacyIndexRef, {
          'uid': uid,
          'createdAt': FieldValue.serverTimestamp(),
        });
      }
      transaction.set(userRef, {
        'uid': uid,
        'email': email,
        'role': 'student',
        'status': 'pending',
        'name': name,
        'address': address,
        'lrn': lrn,
        'character': character == 'girl' ? 'girl' : 'boy',
        'profilePhotoUrl': '',
        'tutorialEligible': true,
        'tutorialCompleted': false,
        'createdAt': FieldValue.serverTimestamp(),
      });
    });
  }

  static Future<UserAccount?> getAccount(String uid) async {
    final snapshot = await _users.doc(uid).get();
    if (!snapshot.exists) return null;
    return UserAccount.fromJson({...snapshot.data()!, 'uid': snapshot.id});
  }

  static Future<List<UserAccount>> loadAccounts() async {
    final snapshot = await _users.orderBy('name').get();
    return snapshot.docs
        .map((doc) => UserAccount.fromJson({...doc.data(), 'uid': doc.id}))
        .toList();
  }

  static Future<void> approveAccountAsTeacher(String uid) async {
    final targetUid = uid.trim();
    if (targetUid.isEmpty || targetUid.contains('/')) {
      throw ArgumentError.value(uid, 'uid');
    }

    final targetRef = _users.doc(targetUid);
    await FirebaseFirestore.instance.runTransaction<void>((transaction) async {
      final snapshot = await transaction.get(targetRef);
      if (!snapshot.exists) {
        throw StateError('The selected account no longer exists.');
      }

      final account = snapshot.data()!;
      final role = account['role'];
      final status = account['status'];
      if (role == 'teacher' && status == 'approved') {
        return;
      }
      if (role != 'student' || (status != 'pending' && status != 'approved')) {
        throw StateError(
          'Only an existing student account can be approved as a teacher.',
        );
      }

      transaction.update(targetRef, {
        'role': 'teacher',
        'status': 'approved',
      });
    });
  }

  static Future<void> updateAccount(UserAccount account) {
    final currentLrn = account.lrn.trim();
    return _users.doc(account.uid).get().then((snapshot) {
      if (snapshot.data()?['lrn'] != currentLrn) {
        throw StateError('An account LRN cannot be changed.');
      }
      final data = account.toJson()..remove('uid');
      return _users.doc(account.uid).update(data);
    });
  }

  static Future<void> deleteAccount(UserAccount account) async {
    final lrnIndex =
        FirebaseFirestore.instance.collection('lrnIndexes').doc(account.lrn);
    await FirebaseFirestore.instance.runTransaction((transaction) async {
      final indexSnapshot = await transaction.get(lrnIndex);
      transaction.delete(_users.doc(account.uid));
      if (indexSnapshot.data()?['uid'] == account.uid) {
        transaction.delete(lrnIndex);
      }
    });
  }

  static Future<void> updateCurrentProfile({
    required String name,
    required String address,
    String? profilePhotoUrl,
  }) async {
    final user = currentUser;
    if (user == null) throw StateError('Not signed in.');
    final updates = <String, dynamic>{
      'name': name,
      'address': address,
    };
    if (profilePhotoUrl != null) {
      updates['profilePhotoUrl'] = profilePhotoUrl;
    }
    await _users.doc(user.uid).update(updates);
  }

  static Future<void> updateCurrentProfilePhotoUrl(String photoUrl) async {
    final user = currentUser;
    if (user == null) throw StateError('Not signed in.');
    await _users.doc(user.uid).update({'profilePhotoUrl': photoUrl});
  }

  static Future<String> _getDeviceId() async {
    final preferences = await SharedPreferences.getInstance();
    final existing = preferences.getString(_deviceIdKey);
    if (existing != null && existing.length >= 16) return existing;

    final random = Random.secure();
    final deviceId = List<int>.generate(
      32,
      (_) => random.nextInt(256),
    ).map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
    await preferences.setString(_deviceIdKey, deviceId);
    return deviceId;
  }

  static Future<String> _claimLoginSession(String uid, String deviceId) {
    final sessionRef = _sessions.doc(uid);
    return FirebaseFirestore.instance.runTransaction((transaction) async {
      final snapshot = await transaction.get(sessionRef);
      if (snapshot.exists) {
        final data = snapshot.data()!;
        if (data['deviceId'] != deviceId) {
          throw StateError(
            'This account is already active on another device. '
            'Sign out there first, or ask an admin to clear its session.',
          );
        }
        final existingSessionId = data['sessionId'];
        if (existingSessionId is! String || existingSessionId.isEmpty) {
          throw StateError(
            'This device session is incomplete. Ask an administrator to clear it.',
          );
        }
        return existingSessionId;
      }

      final sessionId = _generateSessionId();
      transaction.set(sessionRef, {
        'deviceId': deviceId,
        'sessionId': sessionId,
        'claimedAt': FieldValue.serverTimestamp(),
      });
      return sessionId;
    });
  }

  static String _generateSessionId() {
    final random = Random.secure();
    return List<int>.generate(32, (_) => random.nextInt(256))
        .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
        .join();
  }

  static Future<void> _releaseLoginSession(
    String uid,
    String deviceId,
    String sessionId,
  ) async {
    final sessionRef = _sessions.doc(uid);
    await FirebaseFirestore.instance.runTransaction((transaction) async {
      final snapshot = await transaction.get(sessionRef);
      if (!snapshot.exists) return;
      final data = snapshot.data()!;
      if (data['deviceId'] == deviceId && data['sessionId'] == sessionId) {
        transaction.delete(sessionRef);
      }
    });
  }

  static Future<void> signOut() async {
    final currentUid = _auth.currentUser?.uid;
    final uid = currentUid;
    final preferences = await SharedPreferences.getInstance();
    String? sessionId =
        uid == null ? null : preferences.getString('$_sessionIdKeyPrefix$uid');
    if (uid != null && _auth.currentUser != null) {
      final deviceId = await _getDeviceId();
      if (sessionId == null) {
        final snapshot = await _sessions.doc(uid).get();
        final data = snapshot.data();
        if (data?['deviceId'] == deviceId && data?['sessionId'] is String) {
          sessionId = data!['sessionId'] as String;
        }
      }
      if (sessionId != null) {
        await _releaseLoginSession(uid, deviceId, sessionId);
      }
    }
    if (uid != null) await preferences.remove('$_sessionIdKeyPrefix$uid');
    await _auth.signOut();
  }

  static Future<void> clearAccountLoginSession(String uid) async {
    await _sessions.doc(uid).delete();
  }
}
