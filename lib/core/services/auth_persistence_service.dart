import 'dart:async';
import 'package:sqflite/sqflite.dart';
import '../database/auth_database.dart';

class AuthPersistenceService {
  static final AuthPersistenceService _instance = AuthPersistenceService._internal();
  factory AuthPersistenceService() => _instance;
  AuthPersistenceService._internal();

  final AuthDatabase _authDatabase = AuthDatabase();

  // Save authentication token to database
  Future<int> saveAuthToken({
    required String token,
    required String username,
    String? refreshToken,
    String? userId,
    DateTime? expiresAt,
  }) async {
    try {
      print('💾 Saving auth token to database for user: $username');
      final db = await _authDatabase.database;
      
      // Deactivate any existing tokens for this user
      await _deactivateUserTokens(username);
      
      // Create new auth token
      final authToken = AuthToken(
        token: token,
        refreshToken: refreshToken,
        username: username,
        userId: userId,
        expiresAt: expiresAt,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
      
      // Insert new token
      final id = await db.insert(
        'auth_tokens',
        authToken.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      
      // Save user session
      await _saveUserSession(username);
      
      print('✅ Auth token saved with ID: $id');
      return id;
    } catch (e) {
      print('❌ Error saving auth token: $e');
      rethrow;
    }
  }

  // Get current active auth token
  Future<AuthToken?> getActiveAuthToken() async {
    try {
      final db = await _authDatabase.database;
      
      final List<Map<String, dynamic>> maps = await db.query(
        'auth_tokens',
        where: 'is_active = ?',
        whereArgs: [1],
        orderBy: 'created_at DESC',
        limit: 1,
      );

      if (maps.isNotEmpty) {
        final token = AuthToken.fromMap(maps.first);
        
        // Check if token is expired
        if (token.isExpired) {
          print('⚠️ Found expired token for user: ${token.username}');
          await _deactivateToken(token.id!);
          return null;
        }
        
        print('🔑 Found active token for user: ${token.username}');
        return token;
      }
      
      print('🔓 No active auth token found');
      return null;
    } catch (e) {
      print('❌ Error getting active auth token: $e');
      return null;
    }
  }

  // Check if user has valid stored credentials
  Future<bool> hasValidStoredCredentials() async {
    final token = await getActiveAuthToken();
    return token != null && !token.isExpired;
  }

  // Get stored username for auto-fill
  Future<String?> getLastLoggedInUsername() async {
    try {
      final db = await _authDatabase.database;
      
      final List<Map<String, dynamic>> maps = await db.query(
        'user_sessions',
        where: 'is_active = ?',
        whereArgs: [1],
        orderBy: 'last_activity DESC',
        limit: 1,
      );

      if (maps.isNotEmpty) {
        final session = UserSession.fromMap(maps.first);
        return session.username;
      }
      
      return null;
    } catch (e) {
      print('❌ Error getting last logged in username: $e');
      return null;
    }
  }

  // Clear all stored credentials (logout)
  Future<void> clearStoredCredentials() async {
    try {
      print('🗑️ Clearing all stored credentials...');
      final db = await _authDatabase.database;
      
      // Deactivate all tokens
      await db.update(
        'auth_tokens',
        {'is_active': 0, 'updated_at': DateTime.now().millisecondsSinceEpoch},
        where: 'is_active = ?',
        whereArgs: [1],
      );
      
      // Deactivate all sessions
      await db.update(
        'user_sessions',
        {'is_active': 0, 'last_activity': DateTime.now().millisecondsSinceEpoch},
        where: 'is_active = ?',
        whereArgs: [1],
      );
      
      print('✅ All stored credentials cleared');
    } catch (e) {
      print('❌ Error clearing stored credentials: $e');
    }
  }

  // Update last activity timestamp
  Future<void> updateLastActivity(String username) async {
    try {
      final db = await _authDatabase.database;
      
      await db.update(
        'user_sessions',
        {'last_activity': DateTime.now().millisecondsSinceEpoch},
        where: 'username = ? AND is_active = ?',
        whereArgs: [username, 1],
      );
    } catch (e) {
      print('❌ Error updating last activity: $e');
    }
  }

  // Get user session info
  Future<UserSession?> getUserSession(String username) async {
    try {
      final db = await _authDatabase.database;
      
      final List<Map<String, dynamic>> maps = await db.query(
        'user_sessions',
        where: 'username = ? AND is_active = ?',
        whereArgs: [username, 1],
        orderBy: 'last_activity DESC',
        limit: 1,
      );

      if (maps.isNotEmpty) {
        return UserSession.fromMap(maps.first);
      }
      
      return null;
    } catch (e) {
      print('❌ Error getting user session: $e');
      return null;
    }
  }

  // Private helper methods
  Future<void> _deactivateUserTokens(String username) async {
    final db = await _authDatabase.database;
    
    await db.update(
      'auth_tokens',
      {'is_active': 0, 'updated_at': DateTime.now().millisecondsSinceEpoch},
      where: 'username = ? AND is_active = ?',
      whereArgs: [username, 1],
    );
  }

  Future<void> _deactivateToken(int tokenId) async {
    final db = await _authDatabase.database;
    
    await db.update(
      'auth_tokens',
      {'is_active': 0, 'updated_at': DateTime.now().millisecondsSinceEpoch},
      where: 'id = ?',
      whereArgs: [tokenId],
    );
  }

  Future<void> _saveUserSession(String username) async {
    final db = await _authDatabase.database;
    
    // Deactivate existing sessions for this user
    await db.update(
      'user_sessions',
      {'is_active': 0, 'last_activity': DateTime.now().millisecondsSinceEpoch},
      where: 'username = ? AND is_active = ?',
      whereArgs: [username, 1],
    );
    
    // Create new session
    final session = UserSession(
      username: username,
      loginTimestamp: DateTime.now(),
      lastActivity: DateTime.now(),
      deviceInfo: 'Flutter App', // You can enhance this with actual device info
    );
    
    await db.insert(
      'user_sessions',
      session.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  // Initialize service
  Future<void> initialize() async {
    try {
      print('🔧 Initializing AuthPersistenceService...');
      
      // Clean up expired tokens
      await _cleanupExpiredTokens();
      
      print('✅ AuthPersistenceService initialized');
    } catch (e) {
      print('❌ Error initializing AuthPersistenceService: $e');
    }
  }

  Future<void> _cleanupExpiredTokens() async {
    try {
      final db = await _authDatabase.database;
      
      // Get all active tokens
      final List<Map<String, dynamic>> maps = await db.query(
        'auth_tokens',
        where: 'is_active = ?',
        whereArgs: [1],
      );

      for (final map in maps) {
        final token = AuthToken.fromMap(map);
        if (token.isExpired) {
          await _deactivateToken(token.id!);
          print('🗑️ Cleaned up expired token for user: ${token.username}');
        }
      }
    } catch (e) {
      print('❌ Error cleaning up expired tokens: $e');
    }
  }

  // Dispose service
  Future<void> dispose() async {
    await _authDatabase.close();
  }
}