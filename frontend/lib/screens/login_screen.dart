import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../providers/auth_provider.dart';

class LoginScreen extends ConsumerWidget {
  const LoginScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authStateProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Login'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/'),
        ),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Card(
            margin: const EdgeInsets.all(16),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.lock_outline, size: 48),
                  const SizedBox(height: 12),
                  Text(
                    authState.isAuthenticated
                        ? 'You are logged in'
                        : 'Log in to your GoalCraft account',
                    style: Theme.of(context).textTheme.titleMedium,
                    textAlign: TextAlign.center,
                  ),
                  if (authState.credentials?.user.email != null) ...[
                    const SizedBox(height: 6),
                    Text(
                      authState.credentials!.user.email!,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                  const SizedBox(height: 20),
                  if (authState.error != null)
                    Text(
                      authState.error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: authState.isLoading
                          ? null
                          : () async {
                              if (authState.isAuthenticated) {
                                await ref.read(authStateProvider.notifier).logout();
                              } else {
                                await ref.read(authStateProvider.notifier).login();
                              }
                              if (context.mounted) {
                                context.go('/');
                              }
                            },
                      child: Text(
                        authState.isAuthenticated ? 'Log out' : 'Log in with Auth0',
                      ),
                    ),
                  ),
                  if (authState.isLoading) ...[
                    const SizedBox(height: 12),
                    const CircularProgressIndicator(),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
