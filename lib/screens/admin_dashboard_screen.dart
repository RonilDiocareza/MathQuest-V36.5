import 'package:flutter/material.dart';
import 'package:cloud_functions/cloud_functions.dart';
import '../models/user_account.dart';
import '../services/auth_service.dart';
import '../services/leaderboard_service.dart';
import '../services/user_progress_service.dart';
import '../widgets/math_background.dart';
import 'login_screen.dart';

class AdminDashboardScreen extends StatefulWidget {
  const AdminDashboardScreen({super.key});

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen> {
  List<UserAccount> accounts = [];
  Map<String, UserProgress> progressByEmail = {};
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadAccounts();
  }

  Future<void> _loadAccounts() async {
    setState(() => isLoading = true);
    final loaded = await AuthService.loadAccounts();
    final progressEntries = await Future.wait(loaded.map((account) async {
      final progress = await UserProgressService.getProgressForUid(account.uid);
      return MapEntry(account.email, progress);
    }));
    setState(() {
      accounts = loaded;
      progressByEmail = Map.fromEntries(progressEntries);
      isLoading = false;
    });
  }

  Future<void> _approveAccount(UserAccount account) async {
    final updatedAccount = account.copyWith(status: 'approved');
    await AuthService.updateAccount(updatedAccount);
    var leaderboardInitialized = true;
    try {
      await LeaderboardService.initializeApprovedStudentEntry(account.uid);
    } catch (error, stackTrace) {
      debugPrint(
          'Unable to initialize approved student leaderboard entry: $error');
      debugPrintStack(stackTrace: stackTrace);
      leaderboardInitialized = false;
    }
    _loadAccounts();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            leaderboardInitialized
                ? 'Student approved and added to the leaderboard.'
                : 'Student approved, but leaderboard record creation failed. '
                    'Use Sync leaderboard to retry.',
          ),
          backgroundColor: leaderboardInitialized ? Colors.green : Colors.red,
        ),
      );
    }
  }

  Future<void> _approveAsTeacher(UserAccount account) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Approve as Teacher?'),
        content: Text(
          'This will change ${account.name.isEmpty ? account.email : account.name} '
          'to an approved Teacher Account. They will keep their existing login '
          'credentials and account.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Approve as Teacher'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    try {
      await AuthService.approveAccountAsTeacher(account.uid);
      await _loadAccounts();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${account.name.isEmpty ? account.email : account.name} '
            'is now an approved teacher.',
          ),
          backgroundColor: Colors.green,
        ),
      );
    } on FirebaseFunctionsException catch (error, stackTrace) {
      debugPrint(
        'Unable to approve account ${account.uid} as teacher '
        '(${error.code}): ${error.message}',
      );
      debugPrintStack(stackTrace: stackTrace);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            error.code == 'permission-denied'
                ? 'Only an authorized admin can approve teachers.'
                : 'Could not approve this account as a teacher '
                    '(${error.code}): ${error.message ?? 'No server detail provided.'}',
          ),
          backgroundColor: Colors.red,
        ),
      );
    } catch (error, stackTrace) {
      debugPrint('Unable to approve account ${account.uid} as teacher: $error');
      debugPrintStack(stackTrace: stackTrace);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not approve this account as a teacher. Retry.'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _deleteAccount(UserAccount account) async {
    await AuthService.deleteAccount(account);
    _loadAccounts();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Account deleted.'), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _clearLoginSession(UserAccount account) async {
    try {
      await AuthService.clearAccountLoginSession(account.uid);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Cleared ${account.name.isEmpty ? account.email : account.name}\'s device session.',
          ),
        ),
      );
    } on FirebaseFunctionsException catch (error, stackTrace) {
      debugPrint('Unable to clear account device session: $error');
      debugPrintStack(stackTrace: stackTrace);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not clear the device session (${error.code}).'),
          backgroundColor: Colors.red,
        ),
      );
    } catch (error, stackTrace) {
      debugPrint('Unable to clear account device session: $error');
      debugPrintStack(stackTrace: stackTrace);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not clear the device session. Please retry.'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _backfillLeaderboard() async {
    try {
      final count = await LeaderboardService.backfillEntries();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Initialized leaderboard records for $count registered students.',
          ),
        ),
      );
    } catch (error, stackTrace) {
      debugPrint('Unable to sync leaderboard records: $error');
      debugPrintStack(stackTrace: stackTrace);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Could not sync leaderboard records. Confirm you are signed in '
            'as an admin and check your connection.',
          ),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final pending = accounts.where((a) => a.isPending).toList();
    final approvedStudents =
        accounts.where((a) => !a.isAdmin && a.isApproved).toList();

    final media = MediaQuery.of(context);
    final screenHeight = media.size.height;
    final isSmall = media.size.width < 600; // treat <600px as mobile

    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF8B5E3C),
        title: const Text('Admin Dashboard'),
        actions: [
          IconButton(
            onPressed: _backfillLeaderboard,
            icon: const Icon(Icons.sync),
            tooltip: 'Sync all registered students to the leaderboard',
          ),
          IconButton(
            onPressed: () async {
              final navigator = Navigator.of(context);
              final messenger = ScaffoldMessenger.maybeOf(context);

              try {
                await AuthService.signOut();
                if (!mounted) return;
                await navigator.pushAndRemoveUntil(
                  MaterialPageRoute(builder: (_) => const LoginScreen()),
                  (route) => false,
                );
              } catch (error, stackTrace) {
                debugPrint('Unable to sign out admin session: $error');
                debugPrintStack(stackTrace: stackTrace);
                if (!mounted) return;
                messenger?.showSnackBar(
                  const SnackBar(
                    content: Text(
                      'Could not release this device session. Check your connection and try again.',
                    ),
                    backgroundColor: Colors.red,
                  ),
                );
              }
            },
            icon: const Icon(Icons.logout),
            tooltip: 'Logout',
          ),
        ],
      ),
      body: Stack(
        children: [
          // Fixed background
          Positioned.fill(
            child: IgnorePointer(
              child: MathBackground(
                child: SizedBox.expand(
                  child: Container(
                    color: Colors.transparent,
                  ),
                ),
              ),
            ),
          ),
          // Scrollable content on top — ensure it fills the viewport
          isLoading
              ? const Center(child: CircularProgressIndicator())
              : SingleChildScrollView(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                        minHeight: screenHeight - kToolbarHeight),
                    child: Padding(
                      padding: EdgeInsets.symmetric(
                          horizontal: isSmall ? 12.0 : 24.0, vertical: 16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Pending Student Signups',
                            style: TextStyle(
                              fontSize: isSmall ? 20 : 22,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(height: 8),
                          if (pending.isEmpty)
                            Text('No pending signups.',
                                style: TextStyle(color: Colors.white70))
                          else
                            ...pending.map(_buildAccountCard),
                          const SizedBox(height: 24),
                          Text(
                            'Approved Students',
                            style: TextStyle(
                              fontSize: isSmall ? 20 : 22,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(height: 8),
                          if (approvedStudents.isEmpty)
                            Text('No approved student accounts yet.',
                                style: TextStyle(color: Colors.white70))
                          else
                            ...approvedStudents.map(_buildAccountCard),
                          // add some spacing at the bottom so last card isn't flush to edge
                          SizedBox(height: isSmall ? 24 : 48),
                        ],
                      ),
                    ),
                  ),
                ),
        ],
      ),
    );
  }

  Widget _buildAccountCard(UserAccount account) {
    final isAdmin = account.isAdmin;
    return GestureDetector(
      onTap: () => _showAccountDetails(account),
      child: Card(
        color: const Color(0xFFF1D0AD),
        elevation: 4,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        margin: const EdgeInsets.only(bottom: 14),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      account.name.isNotEmpty ? account.name : account.email,
                      style: const TextStyle(
                          fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      account.email,
                      style: const TextStyle(color: Colors.black87),
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 6),
                    if (!isAdmin)
                      Text(
                        'Progress: ${progressByEmail[account.email]?.completedCount ?? 0} stages completed • Highest Stage ${progressByEmail[account.email]?.highestCompletedLevel ?? 0}',
                        style: const TextStyle(color: Colors.black87),
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
                ),
              ),
              if (!isAdmin)
                IconButton(
                  icon: const Icon(Icons.delete_outline, color: Colors.red),
                  tooltip: 'Delete account',
                  onPressed: () => _deleteAccount(account),
                ),
            ],
          ),
        ),
      ),
    );
  }

  void _showAccountDetails(UserAccount account) {
    final isAdmin = account.isAdmin;
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(account.name.isNotEmpty ? account.name : account.email),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Email: ${account.email}'),
              Text('Role: ${account.role}'),
              Text('Status: ${account.status}'),
              if (account.lrn.isNotEmpty) Text('LRN: ${account.lrn}'),
              if (account.address.isNotEmpty)
                Text('Address: ${account.address}'),
              if (!isAdmin) ...[
                const SizedBox(height: 8),
                Text(
                    'Completed Stages: ${progressByEmail[account.email]?.completedCount ?? 0}'),
                Text(
                    'Highest Completed Stage: ${progressByEmail[account.email]?.highestCompletedLevel ?? 0}'),
                Text(
                    'Unlocked Chapters: ${progressByEmail[account.email]?.unlockedLevels ?? 1}'),
                Text(
                    'Quest Attempts: ${progressByEmail[account.email]?.questAttempts ?? 0}'),
              ],
            ],
          ),
          actions: [
            if (account.role.toLowerCase() == 'student')
              TextButton(
                onPressed: () {
                  Navigator.of(context).pop();
                  _approveAsTeacher(account);
                },
                child: const Text('Approve as Teacher'),
              ),
            if (account.isPending && !isAdmin)
              TextButton(
                onPressed: () {
                  Navigator.of(context).pop();
                  _approveAccount(account);
                },
                child: const Text('Approve'),
              ),
            if (!isAdmin)
              TextButton(
                onPressed: () async {
                  Navigator.of(context).pop();
                  final confirmed = await showDialog<bool>(
                    context: this.context,
                    builder: (dialogContext) => AlertDialog(
                      title: const Text('Clear Device Session?'),
                      content: Text(
                        'This will sign out ${account.name.isEmpty ? account.email : account.name} from the current device and let them sign in again.',
                      ),
                      actions: [
                        TextButton(
                          onPressed: () =>
                              Navigator.of(dialogContext).pop(false),
                          child: const Text('Cancel'),
                        ),
                        TextButton(
                          onPressed: () =>
                              Navigator.of(dialogContext).pop(true),
                          child: const Text('Clear Session'),
                        ),
                      ],
                    ),
                  );
                  if (confirmed == true) await _clearLoginSession(account);
                },
                child: const Text('Clear Device Session'),
              ),
            if (!isAdmin)
              TextButton(
                onPressed: () {
                  Navigator.of(context).pop();
                  _deleteAccount(account);
                },
                child:
                    const Text('Delete', style: TextStyle(color: Colors.red)),
              ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }
}
