import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:metadata/core/bootstrap/app_bootstrap_gate.dart';
import 'package:metadata/core/bootstrap/session_initializer.dart';
import 'package:metadata/core/firebase/firebase_services.dart';
import 'package:metadata/models/user_profile.dart';
import 'package:metadata/utils/app_colors.dart';
import 'package:metadata/screens/home_screen.dart';
import 'package:metadata/screens/login_screen.dart';
import 'package:metadata/screens/name_screen.dart';

final authStateProvider = StreamProvider<User?>((ref) {
  return ref.watch(authServiceProvider).authStateChanges();
});

final userProfileStreamProvider = StreamProvider.autoDispose<UserProfile?>((ref) {
  final user = ref.watch(authStateProvider).value;
  if (user == null) return Stream.value(null);
  return ref.watch(userProfileServiceProvider).watchProfile();
});

/// Decides the initial screen based on real auth/profile state, so
/// relaunching the app with an existing session skips Login entirely.
class AuthGate extends ConsumerWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authStateProvider);

    return authState.when(
      data: (user) {
        if (user == null) return const LoginScreen();

        final profileAsync = ref.watch(userProfileStreamProvider);
        return profileAsync.when(
          data: (profile) {
            if (profile == null || profile.displayName.trim().isEmpty) {
              return const NameScreen();
            }
            return const SessionInitializer(child: HomeScreen());
          },
          loading: () => const BootstrapLoadingView(),
          // NOT LoginScreen. The user is authenticated at this point — the
          // only thing that failed is reading their profile, and the usual
          // cause is undeployed firestore.rules denying `users/{uid}`.
          // Sending them back to Login there produces an invisible loop:
          // sign in, bounce to Login, sign in again, forever, with the real
          // error never shown.
          error: (Object error, _) => _ProfileErrorView(
            error: error,
            onRetry: () => ref.invalidate(userProfileStreamProvider),
          ),
        );
      },
      loading: () => const BootstrapLoadingView(),
      // A broken auth *stream* is not the same as being signed out, so this
      // one is surfaced too rather than silently rendering Login.
      error: (Object error, _) => _ProfileErrorView(
        error: error,
        onRetry: () => ref.invalidate(authStateProvider),
      ),
    );
  }
}

/// Shown when the user is signed in but their profile cannot be read.
class _ProfileErrorView extends StatelessWidget {
  const _ProfileErrorView({required this.error, required this.onRetry});

  final Object error;
  final VoidCallback onRetry;

  bool get _isPermissionDenied {
    final e = error;
    return e is FirebaseException && e.code == 'permission-denied';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.white,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.lock_outline_rounded,
                  color: Colors.redAccent,
                  size: 34,
                ),
                const SizedBox(height: 14),
                Text(
                  _isPermissionDenied
                      ? "You're signed in, but this project's Firestore "
                            'security rules are blocking access to your '
                            'profile. Deploy firestore.rules to the Firebase '
                            'project, then retry.'
                      : 'Could not load your profile.\n\n$error',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontFamily: 'SF Pro Display',
                    fontSize: 14,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 18),
                TextButton(
                  onPressed: onRetry,
                  child: const Text('Retry'),
                ),
                TextButton(
                  onPressed: () => FirebaseAuth.instance.signOut(),
                  child: const Text('Sign out'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
