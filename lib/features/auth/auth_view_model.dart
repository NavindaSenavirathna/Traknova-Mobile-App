import '../../core/viewmodels/base_view_model.dart';
import '../../core/services/auth_service.dart';
import 'auth_model.dart';

class AuthViewModel extends BaseViewModel {
  final AuthService _authService;
  AuthModel _auth = AuthModel();
  bool _isPasswordVisible = false;
  String? _token;
  String? _username;

  AuthViewModel(this._authService) {
    _initializeAuth();
  }

  String get email => _auth.email;
  String get password => _auth.password;
  bool get isPasswordVisible => _isPasswordVisible;
  String? get token => _token;
  String? get username => _username;
  bool get isLoggedIn => _token != null && _token!.isNotEmpty;
  
  // Expose auth service for initialization
  AuthService get authService => _authService;

  // Initialize auth state from stored data
  Future<void> _initializeAuth() async {
    _token = await _authService.getStoredToken();
    _username = await _authService.getStoredUsername();
    
    if (_username != null) {
      _auth = _auth.copyWith(email: _username!);
    }
    
    notifyListeners();
  }

  // Check if user is already logged in
  Future<bool> checkLoginStatus() async {
    return await _authService.isLoggedIn();
  }

  void updateEmail(String value) {
    _auth = _auth.copyWith(email: value);
    notifyListeners();
  }

  void updatePassword(String value) {
    _auth = _auth.copyWith(password: value);
    notifyListeners();
  }

  void togglePasswordVisibility() {
    _isPasswordVisible = !_isPasswordVisible;
    notifyListeners();
  }

  Future<bool> login() async {
    if (_auth.email.isEmpty || _auth.password.isEmpty) {
      setError('Please enter both email and password');
      return false;
    }

    bool loginSuccess = false;
    
    await runSafe(() async {
      try {
        _token = await _authService.login(
          username: _auth.email,
          password: _auth.password,
        );
        
        if (_token != null && _token!.isNotEmpty) {
          // Login successful - get stored username
          _username = await _authService.getStoredUsername();
          loginSuccess = true;
        } else {
          setError('Invalid response from server');
          loginSuccess = false;
        }
      } catch (e) {
        setError(_formatAuthError(e));
        loginSuccess = false;
      }
    });

    return loginSuccess;
  }

  String _formatAuthError(Object error) {
    final message = error.toString().replaceFirst('Exception: ', '').trim();

    if (message == 'USER_ALREADY_LOGGED_IN') {
      return 'This account is already signed in on another device. Sign out there first and try again.';
    }

    if (message.startsWith('Login failed: ')) {
      return message.substring('Login failed: '.length).trim();
    }

    if (message.startsWith('Failed to parse login response: ')) {
      return 'Unexpected login response from the server. Please try again later.';
    }

    return message.isNotEmpty ? message : 'Unable to sign in. Please try again.';
  }

  Future<void> logout() async {
    print('🔄 AuthViewModel.logout() started');
    
    try {
      setLoading(true);
      clearError();
      
      print('🔄 Calling AuthService.logout()...');
      await _authService.logout();
      
      print('🔄 Clearing local auth state...');
      // Clear local state
      _token = null;
      _username = null;
      _auth = AuthModel(); // Reset auth data
      
      print('✅ AuthViewModel logout completed successfully');
      
    } catch (e) {
      print('❌ AuthViewModel logout error: $e');
      
      // Even if logout fails, clear local data
      _token = null;
      _username = null;
      _auth = AuthModel();
      clearError();
    } finally {
      setLoading(false);
      notifyListeners();
    }
    
    print('✅ AuthViewModel.logout() finished');
  }

  // Get auth headers for API calls
  Future<Map<String, String>> getAuthHeaders() async {
    return await _authService.getAuthHeaders();
  }

  // Change password
  Future<bool> changePassword({
    required String currentPassword,
    required String newPassword,
    required String confirmPassword,
  }) async {
    print('🔄 AuthViewModel.changePassword() started');

    // Validate inputs
    if (currentPassword.isEmpty) {
      setError('Current password is required');
      return false;
    }

    if (newPassword.isEmpty) {
      setError('New password is required');
      return false;
    }

    if (confirmPassword.isEmpty) {
      setError('Password confirmation is required');
      return false;
    }

    if (newPassword != confirmPassword) {
      setError('New password and confirmation do not match');
      return false;
    }

    if (newPassword.length < 6) {
      setError('New password must be at least 6 characters long');
      return false;
    }

    if (currentPassword == newPassword) {
      setError('New password must be different from current password');
      return false;
    }

    bool changeSuccess = false;

    await runSafe(() async {
      try {
        await _authService.changePassword(
          currentPassword: currentPassword,
          newPassword: newPassword,
        );
        
        print('✅ Password changed successfully');
        changeSuccess = true;
        clearError();
        
      } catch (e) {
        print('❌ Password change error: $e');
        setError(e.toString().replaceAll('Exception: ', ''));
        changeSuccess = false;
      }
    });

    print('✅ AuthViewModel.changePassword() finished with result: $changeSuccess');
    return changeSuccess;
  }
}