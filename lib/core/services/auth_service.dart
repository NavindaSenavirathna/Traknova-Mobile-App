import 'dart:convert';
import 'package:http/http.dart' as http;
import 'auth_persistence_service.dart';

class AuthService {
  static const String _baseUrl = 'https://app.traknova.co.uk';
  static const String _tokenPath = '/ext/authentication/token';
  static const String _logoutPath = '/ext/drive-master/api/v1/security/logout';
  static const String _changePasswordPath = '/ext/drive-master/api/v1/security/change-password';

  final AuthPersistenceService _authPersistence = AuthPersistenceService();
  
  String? _currentToken;
  String? _currentUsername;
  String? _currentPassword; // memory-only — needed for web session login

  // Initialize service
  Future<void> initialize() async {
    await _authPersistence.initialize();
    
    // Load stored credentials
    final storedToken = await _authPersistence.getActiveAuthToken();
    if (storedToken != null) {
      _currentToken = storedToken.token;
      _currentUsername = storedToken.username;
      print('🔑 Loaded stored credentials for user: ${storedToken.username}');
    }
  }

  // Get stored token
  Future<String?> getStoredToken() async {
    if (_currentToken != null) return _currentToken;
    
    final authToken = await _authPersistence.getActiveAuthToken();
    if (authToken != null && !authToken.isExpired) {
      _currentToken = authToken.token;
      return _currentToken;
    }
    
    return null;
  }

  // Get stored username
  Future<String?> getStoredUsername() async {
    if (_currentUsername != null) return _currentUsername;
    
    final authToken = await _authPersistence.getActiveAuthToken();
    if (authToken != null) {
      _currentUsername = authToken.username;
      return _currentUsername;
    }
    
    return null;
  }

  // Store token and username in SQLite
  Future<void> _storeCredentials(String token, String username, {String? password}) async {
    await _authPersistence.saveAuthToken(
      token: token,
      username: username,
      refreshToken: password, // store password for web-session login
      expiresAt: DateTime.now().add(const Duration(hours: 24)), // Set 24-hour expiration
    );
    _currentToken = token;
    _currentUsername = username;
    print('✅ Credentials stored in SQLite for user: $username');
  }

  // Clear stored credentials
  Future<void> _clearCredentials() async {
    await _authPersistence.clearStoredCredentials();
    _currentToken = null;
    _currentUsername = null;
    _currentPassword = null;
    print('🗑️ Credentials cleared from SQLite');
  }

  // Check if user is logged in
  Future<bool> isLoggedIn() async {
    return await _authPersistence.hasValidStoredCredentials();
  }

  // Auto-login using stored credentials
  Future<bool> tryAutoLogin() async {
    try {
      final hasValidCredentials = await _authPersistence.hasValidStoredCredentials();
      if (hasValidCredentials) {
        final authToken = await _authPersistence.getActiveAuthToken();
        if (authToken != null) {
          _currentToken = authToken.token;
          _currentUsername = authToken.username;
          _currentPassword = authToken.refreshToken; // restore password for web session
          
          // Update last activity
          await _authPersistence.updateLastActivity(authToken.username);
          
          print('✅ Auto-login successful for user: ${authToken.username}');
          return true;
        }
      }
      
      print('🔓 No valid stored credentials for auto-login');
      return false;
    } catch (e) {
      print('❌ Auto-login failed: $e');
      return false;
    }
  }

  String _readErrorMessage(dynamic value) {
    if (value == null) {
      return '';
    }

    if (value is String) {
      return value.trim();
    }

    if (value is Map) {
      const preferredKeys = [
        'message',
        'error',
        'detail',
        'details',
        'description',
        'title',
        'reason',
      ];

      for (final key in preferredKeys) {
        final extracted = _readErrorMessage(value[key]);
        if (extracted.isNotEmpty) {
          return extracted;
        }
      }

      for (final key in ['content', 'result', 'data', 'response']) {
        final extracted = _readErrorMessage(value[key]);
        if (extracted.isNotEmpty) {
          return extracted;
        }
      }
    }

    if (value is List) {
      for (final item in value) {
        final extracted = _readErrorMessage(item);
        if (extracted.isNotEmpty) {
          return extracted;
        }
      }
    }

    return '';
  }

  String _normalizeLoginErrorMessage(String message, int statusCode) {
    final normalized = message.trim();
    final lower = normalized.toLowerCase();

    if (lower.contains('already logged in') ||
        lower.contains('already logged') ||
        lower.contains('another device') ||
        lower.contains('sign out from other device')) {
      return 'This account is already signed in on another device. Sign out there first and try again.';
    }

    if (lower.contains('invalid') &&
        (lower.contains('credential') ||
            lower.contains('username') ||
            lower.contains('password'))) {
      return 'Invalid username or password.';
    }

    if (lower.contains('unauthorized') ||
        lower.contains('authentication failed')) {
      return 'Authentication failed. Please check your credentials and try again.';
    }

    if (lower.contains('locked')) {
      return 'Your account is locked. Please contact support.';
    }

    if (lower.contains('disabled')) {
      return 'Your account is disabled. Please contact support.';
    }

    if (lower.contains('expired')) {
      return 'Your session has expired. Please sign in again.';
    }

    if (lower.contains('too many') || lower.contains('attempt')) {
      return 'Too many login attempts. Please wait and try again.';
    }

    if (statusCode == 401) {
      return 'Invalid username or password.';
    }

    if (statusCode == 403) {
      return 'You do not have permission to sign in.';
    }

    if (statusCode == 408) {
      return 'Login request timed out. Please try again.';
    }

    if (statusCode == 429) {
      return 'Too many login attempts. Please wait and try again.';
    }

    if (statusCode >= 500 && statusCode < 600) {
      return 'Server error. Please try again later.';
    }

    return normalized.isNotEmpty ? normalized : 'Login failed ($statusCode).';
  }

  String _extractLoginErrorMessage(http.Response response) {
    final rawBody = response.body.trim();
    String parsedMessage = '';

    if (rawBody.isNotEmpty) {
      try {
        final decoded = jsonDecode(rawBody);
        parsedMessage = _readErrorMessage(decoded);
      } catch (_) {
        parsedMessage = rawBody;
      }
    }

    return _normalizeLoginErrorMessage(parsedMessage, response.statusCode);
  }

  Future<String> login({required String username, required String password}) async {
    final uri = Uri.parse('$_baseUrl$_tokenPath');
    final headers = {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
    };
    final body = jsonEncode({
      '_username': username,
      '_password': password,
    });

    final resp = await http.post(uri, headers: headers, body: body).timeout(const Duration(seconds: 20));

    if (resp.statusCode >= 200 && resp.statusCode < 300) {
      // Try to parse token from response
      try {
        final data = jsonDecode(resp.body);
        String token;
        
        print('🔍 DEBUG: Login API response structure: ${data.runtimeType}');
        print('🔍 DEBUG: Full response body: ${resp.body}');
        print('🔍 DEBUG: Response data keys: ${data is Map ? data.keys.toList() : 'Not a Map'}');
        
        if (data is Map) {
          print('🔍 DEBUG: Checking content field type: ${data['content']?.runtimeType}');
          if (data.containsKey('content') && data['content'] != null) {
            print('🔍 DEBUG: Content field value: ${data['content']}');
          }
        }
        
        // Check various possible response structures with more robust parsing
        if (data is Map && data.containsKey('token') && data['token'] is String) {
          // Direct token field
          token = data['token'] as String;
          print('🔍 DEBUG: Found token in "token" field');
        } else if (data is Map && data.containsKey('content') && data['content'] != null) {
          // Token nested in content field - handle different content types
          final content = data['content'];
          if (content is Map && content.containsKey('token') && content['token'] is String) {
            token = content['token'] as String;
            print('🔍 DEBUG: Found token in "content.token" field');
          } else if (content is String) {
            // Content field might directly contain the token
            token = content;
            print('🔍 DEBUG: Found token as direct "content" string field');
          } else {
            print('🔍 DEBUG: Content field exists but doesn\'t contain token: $content');
            throw Exception('Login response content field does not contain a valid token. Content: $content');
          }
        } else if (data is Map && data.containsKey('result') && data['result'] is Map) {
          // Token nested in result field
          final result = data['result'] as Map;
          if (result.containsKey('token') && result['token'] is String) {
            token = result['token'] as String;
            print('🔍 DEBUG: Found token in "result.token" field');
          } else {
            throw Exception('Login response result field does not contain a valid token. Result: $result');
          }
        } else if (data is Map && data.containsKey('data') && data['data'] is String) {
          // Token in data field as string
          token = data['data'] as String;
          print('🔍 DEBUG: Found token in "data" field');
        } else if (data is String && data.isNotEmpty) {
          // If API returns raw string token
          token = data;
          print('🔍 DEBUG: Response is string token');
        } else {
          // No valid token structure found
          print('❌ DEBUG: No valid token found in response structure');
          throw Exception('Login response does not contain a valid token. Response structure: ${data.runtimeType}, Keys: ${data is Map ? data.keys.toList() : 'N/A'}');
        }
        
        print('🔍 DEBUG: Extracted token (FULL): $token');
        print('🔍 DEBUG: Token length: ${token.length}');
        print('🔍 DEBUG: Token starts with {: ${token.startsWith('{')}');
        print('🔍 DEBUG: Token is valid JWT format: ${token.contains('.') && token.split('.').length == 3}');
        
        // Validate token format before storing
        if (token.startsWith('{')) {
          print('❌ ERROR: Token still appears to be JSON instead of actual token');
          print('❌ Raw token: $token');
          throw Exception('Token extraction failed - still getting JSON response instead of token');
        }
        
        // Store token, username, and password for future use
        await _storeCredentials(token, username, password: password);
        _currentPassword = password; // keep in memory for web session
        print('✅ Token stored successfully for username: $username');
        return token;
      } catch (e) {
        print('❌ Error parsing login response: $e');
        print('📥 Raw response body: ${resp.body}');
        throw Exception('Failed to parse login response: $e');
      }
    } else {
      throw Exception(_extractLoginErrorMessage(resp));
    }
  }

  Future<void> logout() async {
    final token = await getStoredToken();
    
    if (token == null || token.isEmpty) {
      // Already logged out
      await _clearCredentials();
      print('✅ Already logged out - no token found');
      return;
    }

    try {
      print('🔍 DEBUG: Logout endpoint = $_baseUrl$_logoutPath');
      print('� Making logout API call...');
      
      final uri = Uri.parse('$_baseUrl$_logoutPath');
      final headers = {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
        'X-FMS-EXT-TOKEN': token, // Send token in header
        'Authorization': 'Bearer $token', // Also send as Bearer token
      };

      print('📤 Request headers: ${headers.keys.join(', ')}');

      final resp = await http.post(uri, headers: headers).timeout(const Duration(seconds: 20));
      
      print('📥 Logout API response status: ${resp.statusCode}');
      print('📥 Logout API response body: ${resp.body}');

      // Always clear credentials first, regardless of API response
      await _clearCredentials();

      if (resp.statusCode >= 200 && resp.statusCode < 300) {
        print('✅ Logout API call successful');
        return;
      } else if (resp.statusCode == 401) {
        // Token already expired/invalid or user not found - this is expected and OK
        print('ℹ️ Token already expired/invalid (401) - local logout completed');
        return;
      } else {
        // Log the error but don't throw - we've already cleared local data
        print('⚠️ Logout API returned ${resp.statusCode}: ${resp.body}');
        print('✅ Local logout completed despite API warning');
        // Don't throw error - local logout is more important
        return;
      }
    } catch (e) {
      // Clear credentials even if logout API fails
      await _clearCredentials();
      print('❌ Logout API error: $e');
      print('✅ Local logout completed despite network error');
      
      // Re-throw the error so the UI can show it to user
      throw Exception('Logout API failed: $e');
    }
  }

  /// Password stored in-memory only — used by DeviceDataService for web login.
  String? get currentPassword => _currentPassword;

  /// Set password manually (e.g. when user provides it via a re-auth prompt).
  /// Saves to memory AND persists in SQLite so it survives restarts.
  Future<void> setPasswordForWebSession(String password) async {
    _currentPassword = password;
    // Re-save credentials with the password included
    if (_currentToken != null && _currentUsername != null) {
      await _storeCredentials(_currentToken!, _currentUsername!, password: password);
      print('🔑 Password saved for web session (user: $_currentUsername)');
    }
  }

  // Get current token for API calls
  Future<Map<String, String>> getAuthHeaders() async {
    final token = await getStoredToken();
    
    if (token == null || token.isEmpty) {
      return {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      };
    }
    
    return {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
      'X-FMS-EXT-TOKEN': token
    };
  }

  // Change password
  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    final token = await getStoredToken();
    
    if (token == null || token.isEmpty) {
      throw Exception('No authentication token found. Please log in first.');
    }

    try {
      print('🔍 DEBUG: Change password endpoint = $_baseUrl$_changePasswordPath');
      print('📤 Making change password API call...');
      
      final uri = Uri.parse('$_baseUrl$_changePasswordPath');
      final headers = {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
        'X-FMS-EXT-TOKEN': token,
        'Authorization': 'Bearer $token',
      };

      final body = jsonEncode({
        'oldPassword': currentPassword,
        'password': newPassword,
        'reTypePassword': newPassword,
      });

      print('📤 Request headers: ${headers.keys.join(', ')}');
      print('📤 Request body: $body');
      
      final resp = await http.post(uri, headers: headers, body: body).timeout(const Duration(seconds: 20));
      
      print('📥 Change password API response status: ${resp.statusCode}');
      print('📥 Change password API response body: ${resp.body}');

      if (resp.statusCode >= 200 && resp.statusCode < 300) {
        print('✅ Password changed successfully');
        return;
      } else if (resp.statusCode == 400) {
        throw Exception('Invalid password or password requirements not met');
      } else if (resp.statusCode == 401) {
        throw Exception('Current password is incorrect');
      } else if (resp.statusCode == 403) {
        throw Exception('You are not authorized to change password');
      } else {
        throw Exception('Password change failed (${resp.statusCode}): ${resp.body}');
      }
    } catch (e) {
      print('❌ Change password API error: $e');
      
      if (e is Exception) {
        rethrow;
      } else {
        throw Exception('Password change failed: $e');
      }
    }
  }
}