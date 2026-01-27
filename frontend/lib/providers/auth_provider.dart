import 'package:auth0_flutter/auth0_flutter.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';

class AuthState {
  final Credentials? credentials;
  final bool isLoading;
  final String? error;

  const AuthState({
    this.credentials,
    this.isLoading = false,
    this.error,
  });

  bool get isAuthenticated => credentials != null;

  AuthState copyWith({
    Credentials? credentials,
    bool? isLoading,
    String? error,
  }) {
    return AuthState(
      credentials: credentials ?? this.credentials,
      isLoading: isLoading ?? this.isLoading,
      error: error,
    );
  }
}

class AuthService {
  static const _auth0Domain = String.fromEnvironment('AUTH0_DOMAIN');
  static const _auth0ClientId = String.fromEnvironment('AUTH0_CLIENT_ID');
  static const _auth0Audience = String.fromEnvironment('AUTH0_AUDIENCE');
  static const _auth0RedirectUri = String.fromEnvironment('AUTH0_REDIRECT_URI');

  Auth0 get _auth0 => Auth0(_auth0Domain, _auth0ClientId);

  String get redirectUri =>
      _auth0RedirectUri.isNotEmpty ? _auth0RedirectUri : Uri.base.origin;

  void _ensureConfigured() {
    if (_auth0Domain.isEmpty || _auth0ClientId.isEmpty) {
      throw Exception('Auth0 is not configured. Set AUTH0_DOMAIN and AUTH0_CLIENT_ID.');
    }
  }

  Future<Credentials?> getStoredCredentials() async {
    _ensureConfigured();
    // Credentials manager is only supported on mobile platforms
    if (kIsWeb) {
      return null;
    }
    try {
      if (await _auth0.credentialsManager.hasValidCredentials()) {
        return _auth0.credentialsManager.credentials();
      }
    } catch (e) {
      // Credentials manager not available on this platform
      return null;
    }
    return null;
  }

  Future<Credentials> login() async {
    _ensureConfigured();
    return _auth0.webAuthentication().login(
          audience: _auth0Audience.isNotEmpty ? _auth0Audience : null,
          scopes: {'openid', 'profile', 'email'},
          redirectUrl: redirectUri,
        );
  }

  Future<void> logout() async {
    _ensureConfigured();
    await _auth0.webAuthentication().logout(
          returnTo: redirectUri,
        );
  }

  Future<void> storeCredentials(Credentials credentials) async {
    // Credentials manager is only supported on mobile platforms
    if (kIsWeb) {
      return;
    }
    try {
      await _auth0.credentialsManager.storeCredentials(credentials);
    } catch (e) {
      // Credentials manager not available on this platform
    }
  }

  Future<void> clearCredentials() async {
    // Credentials manager is only supported on mobile platforms
    if (kIsWeb) {
      return;
    }
    try {
      await _auth0.credentialsManager.clearCredentials();
    } catch (e) {
      // Credentials manager not available on this platform
    }
  }
}

final authServiceProvider = Provider<AuthService>((ref) => AuthService());

final authStateProvider = StateNotifierProvider<AuthNotifier, AuthState>((ref) {
  return AuthNotifier(ref.read(authServiceProvider));
});

class AuthNotifier extends StateNotifier<AuthState> {
  final AuthService _authService;

  AuthNotifier(this._authService) : super(const AuthState()) {
    _loadCredentials();
  }

  Future<void> _loadCredentials() async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final credentials = await _authService.getStoredCredentials();
      state = state.copyWith(credentials: credentials, isLoading: false);
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  Future<void> login() async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final credentials = await _authService.login();
      await _authService.storeCredentials(credentials);
      state = state.copyWith(credentials: credentials, isLoading: false);
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  Future<void> logout() async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      await _authService.logout();
      await _authService.clearCredentials();
      state = state.copyWith(credentials: null, isLoading: false);
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }
}
