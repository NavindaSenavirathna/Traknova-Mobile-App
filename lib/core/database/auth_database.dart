import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

class AuthDatabase {
  static Database? _database;
  static final AuthDatabase _instance = AuthDatabase._internal();
  
  factory AuthDatabase() => _instance;
  AuthDatabase._internal();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    String path = join(await getDatabasesPath(), 'auth_database.db');
    
    return await openDatabase(
      path,
      version: 1,
      onCreate: _createDatabase,
    );
  }

  Future<void> _createDatabase(Database db, int version) async {
    await db.execute('''
      CREATE TABLE auth_tokens(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        token TEXT NOT NULL,
        refresh_token TEXT,
        username TEXT NOT NULL,
        user_id TEXT,
        expires_at INTEGER,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        is_active INTEGER NOT NULL DEFAULT 1
      )
    ''');

    await db.execute('''
      CREATE TABLE user_sessions(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        username TEXT NOT NULL,
        login_timestamp INTEGER NOT NULL,
        last_activity INTEGER NOT NULL,
        device_info TEXT,
        is_active INTEGER NOT NULL DEFAULT 1
      )
    ''');

    await db.execute('''
      CREATE INDEX idx_auth_tokens_active ON auth_tokens(is_active)
    ''');
    
    await db.execute('''
      CREATE INDEX idx_user_sessions_active ON user_sessions(is_active)
    ''');
  }

  // Close database
  Future<void> close() async {
    if (_database != null) {
      await _database!.close();
      _database = null;
    }
  }
}

class AuthToken {
  final int? id;
  final String token;
  final String? refreshToken;
  final String username;
  final String? userId;
  final DateTime? expiresAt;
  final DateTime createdAt;
  final DateTime updatedAt;
  final bool isActive;

  AuthToken({
    this.id,
    required this.token,
    this.refreshToken,
    required this.username,
    this.userId,
    this.expiresAt,
    required this.createdAt,
    required this.updatedAt,
    this.isActive = true,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'token': token,
      'refresh_token': refreshToken,
      'username': username,
      'user_id': userId,
      'expires_at': expiresAt?.millisecondsSinceEpoch,
      'created_at': createdAt.millisecondsSinceEpoch,
      'updated_at': updatedAt.millisecondsSinceEpoch,
      'is_active': isActive ? 1 : 0,
    };
  }

  factory AuthToken.fromMap(Map<String, dynamic> map) {
    return AuthToken(
      id: map['id']?.toInt(),
      token: map['token'] ?? '',
      refreshToken: map['refresh_token'],
      username: map['username'] ?? '',
      userId: map['user_id'],
      expiresAt: map['expires_at'] != null 
          ? DateTime.fromMillisecondsSinceEpoch(map['expires_at'])
          : null,
      createdAt: DateTime.fromMillisecondsSinceEpoch(map['created_at'] ?? 0),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(map['updated_at'] ?? 0),
      isActive: (map['is_active'] ?? 1) == 1,
    );
  }

  bool get isExpired {
    if (expiresAt == null) return false;
    return DateTime.now().isAfter(expiresAt!);
  }

  AuthToken copyWith({
    int? id,
    String? token,
    String? refreshToken,
    String? username,
    String? userId,
    DateTime? expiresAt,
    DateTime? createdAt,
    DateTime? updatedAt,
    bool? isActive,
  }) {
    return AuthToken(
      id: id ?? this.id,
      token: token ?? this.token,
      refreshToken: refreshToken ?? this.refreshToken,
      username: username ?? this.username,
      userId: userId ?? this.userId,
      expiresAt: expiresAt ?? this.expiresAt,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? DateTime.now(),
      isActive: isActive ?? this.isActive,
    );
  }
}

class UserSession {
  final int? id;
  final String username;
  final DateTime loginTimestamp;
  final DateTime lastActivity;
  final String? deviceInfo;
  final bool isActive;

  UserSession({
    this.id,
    required this.username,
    required this.loginTimestamp,
    required this.lastActivity,
    this.deviceInfo,
    this.isActive = true,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'username': username,
      'login_timestamp': loginTimestamp.millisecondsSinceEpoch,
      'last_activity': lastActivity.millisecondsSinceEpoch,
      'device_info': deviceInfo,
      'is_active': isActive ? 1 : 0,
    };
  }

  factory UserSession.fromMap(Map<String, dynamic> map) {
    return UserSession(
      id: map['id']?.toInt(),
      username: map['username'] ?? '',
      loginTimestamp: DateTime.fromMillisecondsSinceEpoch(map['login_timestamp'] ?? 0),
      lastActivity: DateTime.fromMillisecondsSinceEpoch(map['last_activity'] ?? 0),
      deviceInfo: map['device_info'],
      isActive: (map['is_active'] ?? 1) == 1,
    );
  }

  Duration get sessionDuration => DateTime.now().difference(loginTimestamp);
}