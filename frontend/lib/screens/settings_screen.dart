import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../providers/goals_provider.dart';

// User settings state
class UserSettings {
  final int? userId;
  final String? email;
  final String? phoneNumber;
  final bool isGoogleCalendarConnected;
  final bool isLoading;
  final String? error;

  const UserSettings({
    this.userId,
    this.email,
    this.phoneNumber,
    this.isGoogleCalendarConnected = false,
    this.isLoading = false,
    this.error,
  });

  UserSettings copyWith({
    int? userId,
    String? email,
    String? phoneNumber,
    bool? isGoogleCalendarConnected,
    bool? isLoading,
    String? error,
  }) {
    return UserSettings(
      userId: userId ?? this.userId,
      email: email ?? this.email,
      phoneNumber: phoneNumber ?? this.phoneNumber,
      isGoogleCalendarConnected: isGoogleCalendarConnected ?? this.isGoogleCalendarConnected,
      isLoading: isLoading ?? this.isLoading,
      error: error,
    );
  }
}

final userSettingsProvider = StateNotifierProvider<UserSettingsNotifier, UserSettings>((ref) {
  return UserSettingsNotifier(ref);
});

class UserSettingsNotifier extends StateNotifier<UserSettings> {
  final Ref _ref;

  UserSettingsNotifier(this._ref) : super(const UserSettings()) {
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    state = state.copyWith(isLoading: true);
    try {
      final apiService = _ref.read(apiServiceProvider);
      // For now, use a hardcoded user ID (in production, get from auth)
      const userId = 1;

      // Check Google Calendar connection status
      bool isConnected = false;
      try {
        isConnected = await apiService.getGoogleCalendarStatus(userId);
      } catch (e) {
        // Ignore - might not have user in DB yet
      }

      state = state.copyWith(
        userId: userId,
        email: 'dev@goalcraft.local',
        isGoogleCalendarConnected: isConnected,
        isLoading: false,
      );
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  Future<void> refreshGoogleCalendarStatus() async {
    if (state.userId == null) return;
    try {
      final apiService = _ref.read(apiServiceProvider);
      final isConnected = await apiService.getGoogleCalendarStatus(state.userId!);
      state = state.copyWith(isGoogleCalendarConnected: isConnected);
    } catch (e) {
      // Ignore errors
    }
  }

  Future<void> updatePhoneNumber(String phoneNumber) async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      // TODO: Call API to update phone number
      // await apiService.updateUser(phoneNumber: phoneNumber);
      state = state.copyWith(
        phoneNumber: phoneNumber,
        isLoading: false,
      );
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  void setGoogleCalendarConnected(bool connected) {
    state = state.copyWith(isGoogleCalendarConnected: connected);
  }
}

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  final _phoneController = TextEditingController();
  bool _isEditingPhone = false;

  @override
  void dispose() {
    _phoneController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(userSettingsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/'),
        ),
      ),
      body: settings.isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // Profile Section
                _buildSectionHeader('Profile'),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const CircleAvatar(
                              radius: 30,
                              child: Icon(Icons.person, size: 30),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    settings.email ?? 'Not logged in',
                                    style: Theme.of(context).textTheme.titleMedium,
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'User ID: ${settings.userId ?? "N/A"}',
                                    style: Theme.of(context).textTheme.bodySmall,
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 24),

                // Phone Number Section
                _buildSectionHeader('Check-In Calls'),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Phone Number',
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'We\'ll call you to check in on your goal progress. Add your phone number to enable voice check-ins.',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
                              ),
                        ),
                        const SizedBox(height: 16),
                        if (_isEditingPhone)
                          Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: _phoneController,
                                  decoration: const InputDecoration(
                                    labelText: 'Phone Number',
                                    hintText: '+1 (555) 123-4567',
                                    prefixIcon: Icon(Icons.phone),
                                  ),
                                  keyboardType: TextInputType.phone,
                                ),
                              ),
                              const SizedBox(width: 8),
                              IconButton(
                                icon: const Icon(Icons.check),
                                onPressed: () {
                                  ref.read(userSettingsProvider.notifier)
                                      .updatePhoneNumber(_phoneController.text);
                                  setState(() => _isEditingPhone = false);
                                },
                              ),
                              IconButton(
                                icon: const Icon(Icons.close),
                                onPressed: () {
                                  setState(() => _isEditingPhone = false);
                                  _phoneController.clear();
                                },
                              ),
                            ],
                          )
                        else
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: Icon(
                              settings.phoneNumber != null
                                  ? Icons.phone
                                  : Icons.phone_disabled,
                              color: settings.phoneNumber != null
                                  ? Colors.green
                                  : Theme.of(context).colorScheme.outline,
                            ),
                            title: Text(
                              settings.phoneNumber ?? 'No phone number added',
                            ),
                            trailing: TextButton(
                              onPressed: () {
                                _phoneController.text = settings.phoneNumber ?? '';
                                setState(() => _isEditingPhone = true);
                              },
                              child: Text(settings.phoneNumber != null ? 'Edit' : 'Add'),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 24),

                // Google Calendar Section
                _buildSectionHeader('Integrations'),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: Colors.blue.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Icon(
                                Icons.calendar_today,
                                color: Colors.blue,
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Google Calendar',
                                    style: Theme.of(context).textTheme.titleSmall,
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    settings.isGoogleCalendarConnected
                                        ? 'Connected'
                                        : 'Not connected',
                                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                          color: settings.isGoogleCalendarConnected
                                              ? Colors.green
                                              : Theme.of(context).colorScheme.outline,
                                        ),
                                  ),
                                ],
                              ),
                            ),
                            if (settings.isGoogleCalendarConnected)
                              TextButton(
                                onPressed: () => _disconnectGoogleCalendar(),
                                child: const Text('Disconnect'),
                              )
                            else
                              ElevatedButton.icon(
                                onPressed: () => _connectGoogleCalendar(),
                                icon: const Icon(Icons.link),
                                label: const Text('Connect'),
                              ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'Connect your Google Calendar to automatically add milestone due dates as events.',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
                              ),
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 24),

                // About Section
                _buildSectionHeader('About'),
                Card(
                  child: Column(
                    children: [
                      ListTile(
                        leading: const Icon(Icons.info_outline),
                        title: const Text('Version'),
                        trailing: const Text('1.0.0'),
                      ),
                      const Divider(height: 1),
                      ListTile(
                        leading: const Icon(Icons.description_outlined),
                        title: const Text('Terms of Service'),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () {
                          // TODO: Open terms
                        },
                      ),
                      const Divider(height: 1),
                      ListTile(
                        leading: const Icon(Icons.privacy_tip_outlined),
                        title: const Text('Privacy Policy'),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () {
                          // TODO: Open privacy policy
                        },
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
      ),
    );
  }

  Future<void> _connectGoogleCalendar() async {
    final settings = ref.read(userSettingsProvider);
    if (settings.userId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please log in first')),
      );
      return;
    }

    // In a real app, this would:
    // 1. Call the backend to get the OAuth URL
    // 2. Open a browser/webview for the user to authorize
    // 3. Handle the callback to store the token

    // For now, show a dialog explaining the flow
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Connect Google Calendar'),
        content: const Text(
          'This will open Google\'s authorization page where you can grant GoalCraft access to create events in your calendar.\n\n'
          'We only request permission to create and manage events - we cannot see your other calendar data.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _initiateGoogleOAuth();
            },
            child: const Text('Continue'),
          ),
        ],
      ),
    );
  }

  Future<void> _initiateGoogleOAuth() async {
    final settings = ref.read(userSettingsProvider);
    final apiService = ref.read(apiServiceProvider);

    // The redirect URI for the OAuth flow
    // Detect if running locally or in production
    final currentUri = Uri.base;
    final isLocal = currentUri.host == 'localhost' || currentUri.host == '127.0.0.1';
    final redirectUri = isLocal
        ? 'http://localhost:3001/auth/google/callback'
        : 'https://harrolee.github.io/goalcraft/auth/google/callback';

    try {
      // Get the authorization URL from the backend
      final authUrl = await apiService.getGoogleAuthUrl(
        settings.userId!,
        redirectUri,
      );

      // Launch the URL in a new browser tab
      final uri = Uri.parse(authUrl);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, webOnlyWindowName: '_blank');

        // Show a dialog to confirm when they're done
        if (mounted) {
          final confirmed = await showDialog<bool>(
            context: context,
            barrierDismissible: false,
            builder: (context) => AlertDialog(
              title: const Text('Complete Authorization'),
              content: const Text(
                'After authorizing in the browser, click "Done" to refresh your connection status.',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('Done'),
                ),
              ],
            ),
          );

          if (confirmed == true) {
            // Refresh the connection status
            await ref.read(userSettingsProvider.notifier).refreshGoogleCalendarStatus();
            if (mounted) {
              final newSettings = ref.read(userSettingsProvider);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    newSettings.isGoogleCalendarConnected
                        ? 'Google Calendar connected successfully!'
                        : 'Connection not detected. Please try again.',
                  ),
                ),
              );
            }
          }
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Could not open browser')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }

  Future<void> _disconnectGoogleCalendar() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Disconnect Google Calendar?'),
        content: const Text(
          'This will remove the connection to your Google Calendar. '
          'Existing events will not be deleted, but new milestones won\'t be added automatically.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Disconnect'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final settings = ref.read(userSettingsProvider);
      final apiService = ref.read(apiServiceProvider);

      try {
        await apiService.disconnectGoogleCalendar(settings.userId!);
        ref.read(userSettingsProvider.notifier).setGoogleCalendarConnected(false);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Google Calendar disconnected')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error disconnecting: $e')),
          );
        }
      }
    }
  }
}
