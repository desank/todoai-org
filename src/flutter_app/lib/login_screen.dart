import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'auth_wrapper.dart';

class LoginScreen extends ConsumerWidget {
  const LoginScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: const Text('Login')),
      body: Center(
        child: ElevatedButton(
          onPressed: () {
            // In this mock implementation, we'll just set the user as authenticated.
            ref.read(isAuthenticatedProvider.notifier).state = true;
          },
          child: const Text('Simulate Login'),
        ),
      ),
    );
  }
}