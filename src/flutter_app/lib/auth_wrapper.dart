import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'home_screen.dart';
import 'login_screen.dart';

// For now, we'll use a simple boolean to represent auth state.
final isAuthenticatedProvider = StateProvider<bool>((ref) => false);

class AuthWrapper extends ConsumerWidget {
  const AuthWrapper({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isAuthenticated = ref.watch(isAuthenticatedProvider);

    if (isAuthenticated) {
      return const HomeScreen();
    } else {
      return const LoginScreen();
    }
  }
}