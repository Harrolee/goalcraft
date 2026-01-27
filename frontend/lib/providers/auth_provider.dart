import 'package:auth0_flutter/auth0_flutter.dart';
import 'package:auth0_flutter/auth0_flutter_web.dart';
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

  Auth0? _auth0Mobile;
  Auth0Web? _auth0Web;

  Auth0 get _auth0 {
    _auth0Mobile ??= Auth0(_auth0Domain, _auth0ClientId);
    return _auth0Mobile!;
  }

  Auth0Web get _auth0WebInstance {
    _auth0Web ??= Auth0Web(
      _auth0Domain,
      _auth0ClientId,
      redirectUrl: redirectUri,
      cacheLocation: CacheLocation.localStorage,
    );
    return _auth0Web!;
  }

  String get redirectUri =>
      _auth0RedirectUri.isNotEmpty ? _auth0RedirectUri : Uri.base.origin;

  void _ensureConfigured() {
    if (_auth0Domain.isEmpty || _auth0ClientId.isEmpty) {
      throw Exception('Auth0 is not configured. Set AUTH0_DOMAIN and AUTH0_CLIENT_ID.');
    }
  }

  Future<Credentials?> getStoredCredentials() async {
    _ensureConfigured();

    if (kIsWeb) {
      // On web, use Auth0Web onLoad to check for existing session
      try {
        return await _auth0WebInstance.onLoad(
          audience: _auth0Audience.isNotEmpty ? _auth0Audience : null,
          scopes: {'openid', 'profile', 'email'},
          useRefreshTokens: true,
        );
      } catch (e) {
        // No existing session
        return null;
      }
    } else {
      // On mobile, use credentials manager
      try {
        if (await _auth0.credentialsManager.hasValidCredentials()) {
          return _auth0.credentialsManager.credentials();
        }
      } catch (e) {
        return null;
      }
      return null;
    }
  }

  Future<Credentials> login() async {
    _ensureConfigured();

    if (kIsWeb) {
      // On web, use popup login (works better for SPAs)
      return _auth0WebInstance.loginWithPopup(
        audience: _auth0Audience.isNotEmpty ? _auth0Audience : null,
        scopes: {'openid', 'profile', 'email'},
      );
    } else {
      // On mobile, use web authentication
      return _auth0.webAuthentication().login(
        audience: _auth0Audience.isNotEmpty ? _auth0Audience : null,
        scopes: {'openid', 'profile', 'email'},
        redirectUrl: redirectUri,
      );
    }
  }

  Future<void> logout() async {
    _ensureConfigured();

    if (kIsWeb) {
      // On web, use Auth0Web logout
      await _auth0WebInstance.logout(
        returnToUrl: redirectUri,
      );
    } else {
      // On mobile, use web authentication logout
      await _auth0.webAuthentication().logout(
        returnTo: redirectUri,
      );
      await clearCredentials();
    }
  }

  Future<void> storeCredentials(Credentials credentials) async {
    // On web, credentials are automatically stored by Auth0Web
    if (kIsWeb) {
      return;
    }

    // On mobile, use credentials manager
    try {
      await _auth0.credentialsManager.storeCredentials(credentials);
    } catch (e) {
      // Credentials manager not available on this platform
    }
  }

  Future<void> clearCredentials() async {
    // On web, credentials are cleared by logout
    if (kIsWeb) {
      return;
    }

    // On mobile, use credentials manager
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
