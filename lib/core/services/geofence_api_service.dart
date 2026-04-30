import 'dart:convert';
import 'dart:io';
import '../models/geofence_models.dart';
import 'auth_service.dart';

/// GeoFence API service — Web session (PHPSESSID) authenticated.
///
/// Uses dart:io HttpClient for proper cookie & redirect handling.
/// Logs in with web credentials to get PHPSESSID, then uses that
/// cookie for all geofence API calls via existing web endpoints.
class GeoFenceApiService {
  static final GeoFenceApiService _instance = GeoFenceApiService._internal();
  factory GeoFenceApiService() => _instance;
  GeoFenceApiService._internal();

  static const String _baseUrl = 'https://app.traknova.co.uk';

  /// Web session credentials (same user that logs into TrakNova web)
  static const String _webUsername = 'TrakNova';
  static const String _webPassword = '123';

  // ignore: unused_field
  AuthService? _authService;
  String? _phpSessionId;
  bool _isSessionValid = false;

  // ═══════════════════════════════════════════════════════════════════════
  //  Web Session Management (PHPSESSID) — dart:io for cookie control
  // ═══════════════════════════════════════════════════════════════════════

  /// Ensure we have a valid web session for API calls.
  Future<bool> ensureSession(AuthService authService) async {
    _authService = authService;

    if (_phpSessionId != null && _isSessionValid) {
      print('✅ [GeoFenceApi] PHPSESSID available: ${_phpSessionId!.substring(0, 8)}...');
      return true;
    }

    return await _webLogin();
  }

  /// Login to TrakNova web to obtain PHPSESSID cookie.
  /// Uses dart:io HttpClient with followRedirects=false to capture cookies.
  Future<bool> _webLogin() async {
    final client = HttpClient();
    client.badCertificateCallback = (cert, host, port) => true;

    try {
      print('🔐 [GeoFenceApi] Logging into web session...');

      // ── Step 1: GET login page → CSRF token + initial PHPSESSID ──
      final getReq = await client.getUrl(Uri.parse('$_baseUrl/'));
      getReq.followRedirects = false;
      getReq.headers.set('Accept', 'text/html');
      final getResp = await getReq.close();
      final loginHtml = await getResp.transform(utf8.decoder).join();

      String? sessionId = _extractSetCookie(getResp);
      print('📄 [GeoFenceApi] Login page: ${getResp.statusCode}, session: ${sessionId != null ? "${sessionId.substring(0, 8)}..." : "none"}');

      if (sessionId == null) {
        print('❌ [GeoFenceApi] No PHPSESSID from login page');
        client.close();
        return false;
      }

      final csrfToken = _extractCsrfToken(loginHtml);
      if (csrfToken == null) {
        print('❌ [GeoFenceApi] No CSRF token in login page');
        client.close();
        return false;
      }
      print('🔑 [GeoFenceApi] CSRF token: ${csrfToken.substring(0, 10)}...');

      // ── Step 2: POST login (followRedirects=false to capture 302 cookie) ──
      final postBody = 'username=${Uri.encodeComponent(_webUsername)}&password=${Uri.encodeComponent(_webPassword)}&token=${Uri.encodeComponent(csrfToken)}';
      final postReq = await client.postUrl(Uri.parse('$_baseUrl/'));
      postReq.followRedirects = false;
      postReq.headers.set('Content-Type', 'application/x-www-form-urlencoded');
      postReq.headers.set('Cookie', 'PHPSESSID=$sessionId');
      postReq.headers.set('Accept', 'text/html');
      postReq.write(postBody);
      final postResp = await postReq.close();
      await postResp.drain(); // consume response body

      // Capture new session from 302 redirect
      final newSession = _extractSetCookie(postResp);
      if (newSession != null) {
        sessionId = newSession;
      }

      print('🔐 [GeoFenceApi] Login POST: ${postResp.statusCode}, session: ${sessionId.substring(0, 8)}...');

      if (postResp.statusCode == 302 || postResp.statusCode == 303) {
        final location = postResp.headers.value('location');
        print('↪️ [GeoFenceApi] Redirect to: $location');

        // Follow redirect to complete session
        if (location != null) {
          final redirectUri = location.startsWith('http')
              ? Uri.parse(location)
              : Uri.parse('$_baseUrl$location');
          final redReq = await client.getUrl(redirectUri);
          redReq.followRedirects = false;
          redReq.headers.set('Cookie', 'PHPSESSID=$sessionId');
          final redResp = await redReq.close();
          await redResp.drain();

          final redSession = _extractSetCookie(redResp);
          if (redSession != null) {
            sessionId = redSession;
          }
          print('📄 [GeoFenceApi] Redirect: ${redResp.statusCode}');
        }

        // Session should be valid now — test it
        _phpSessionId = sessionId;
        _isSessionValid = true;
        print('✅ [GeoFenceApi] Web login SUCCESS! Session: ${sessionId.substring(0, 8)}...');
        client.close();
        return true;
      }

      // If 200 directly (no redirect), try using session anyway
      _phpSessionId = sessionId;
      _isSessionValid = true;
      print('⚠️ [GeoFenceApi] Login returned ${postResp.statusCode}, testing session...');

      // Validate session with a quick test
      final valid = await _testSession(client, sessionId);
      client.close();
      return valid;
    } catch (e) {
      print('❌ [GeoFenceApi] Web login error: $e');
      _isSessionValid = false;
      _phpSessionId = null;
      client.close();
      return false;
    }
  }

  /// Test if a session is valid by making a quick API call.
  Future<bool> _testSession(HttpClient client, String sessionId) async {
    try {
      final testReq = await client.postUrl(Uri.parse('$_baseUrl/geo-fence/api/getDesigns'));
      testReq.followRedirects = false;
      testReq.headers.set('Content-Type', 'application/json');
      testReq.headers.set('Cookie', 'PHPSESSID=$sessionId');
      testReq.write(json.encode({'mode': ['DEVICE', 'REGION'], 'modal': ['AREA', 'ROUTE']}));
      final testResp = await testReq.close();
      final testBody = await testResp.transform(utf8.decoder).join();

      print('🧪 [GeoFenceApi] Session test: ${testResp.statusCode} (${testBody.length}B)');

      if (testResp.statusCode == 200 && testBody.contains('"data"')) {
        print('✅ [GeoFenceApi] Session VALID!');
        return true;
      } else {
        print('❌ [GeoFenceApi] Session invalid: ${testBody.substring(0, testBody.length > 200 ? 200 : testBody.length)}');
        _isSessionValid = false;
        _phpSessionId = null;
        return false;
      }
    } catch (e) {
      print('❌ [GeoFenceApi] Session test error: $e');
      return false;
    }
  }

  /// Extract PHPSESSID from Set-Cookie header of HttpClientResponse.
  String? _extractSetCookie(HttpClientResponse resp) {
    String? sessionId;
    resp.headers.forEach((name, values) {
      if (name.toLowerCase() == 'set-cookie') {
        for (final v in values) {
          final match = RegExp(r'PHPSESSID=([^;]+)').firstMatch(v);
          if (match != null) {
            sessionId = match.group(1);
          }
        }
      }
    });
    return sessionId;
  }

  /// Extract CSRF token from login page HTML.
  String? _extractCsrfToken(String html) {
    final patterns = [
      RegExp('name=["\']token["\'][^>]*value=["\']([^"\']+)["\']'),
      RegExp('value=["\']([^"\']+)["\'][^>]*name=["\']token["\']'),
      RegExp('name=["\']_csrf_token["\'][^>]*value=["\']([^"\']+)["\']'),
      RegExp('value=["\']([^"\']+)["\'][^>]*name=["\']_csrf_token["\']'),
    ];
    for (final p in patterns) {
      final m = p.firstMatch(html);
      if (m != null) return m.group(1);
    }
    return null;
  }

  // ═══════════════════════════════════════════════════════════════════════
  //  HTTP POST — JSON via PHPSESSID cookie (dart:io)
  // ═══════════════════════════════════════════════════════════════════════

  /// JSON POST with web session cookie authentication.
  Future<_ApiResp?> _post(String path, Map<String, dynamic> body) async {
    if (_phpSessionId == null || !_isSessionValid) {
      print('⚠️ [GeoFenceApi] No valid session for $path, re-logging in...');
      final ok = await _webLogin();
      if (!ok) {
        print('❌ [GeoFenceApi] Re-login failed for $path');
        return null;
      }
    }

    final client = HttpClient();
    client.badCertificateCallback = (cert, host, port) => true;

    try {
      final jsonBody = json.encode(body);
      print('🌐 [GeoFenceApi] POST $path (session: ${_phpSessionId!.substring(0, 8)}...)');

      final req = await client.postUrl(Uri.parse('$_baseUrl$path'));
      req.followRedirects = false;
      req.headers.set('Content-Type', 'application/json');
      req.headers.set('Accept', 'application/json');
      req.headers.set('Cookie', 'PHPSESSID=$_phpSessionId');
      req.write(jsonBody);
      final resp = await req.close();
      final respBody = await resp.transform(utf8.decoder).join();

      print('📬 [GeoFenceApi] $path → ${resp.statusCode} (${respBody.length}B)');

      // Session expired — re-login and retry once
      if (resp.statusCode == 302 || resp.statusCode == 401 || resp.statusCode == 403) {
        print('⚠️ [GeoFenceApi] Session expired, re-logging in...');
        _isSessionValid = false;
        client.close();
        final ok = await _webLogin();
        if (ok) {
          return await _postOnce(path, body);
        }
        return null;
      }

      client.close();
      return _ApiResp(resp.statusCode, respBody);
    } catch (e) {
      print('❌ [GeoFenceApi] $path error: $e');
      client.close();
      return null;
    }
  }

  /// Single POST attempt (for retry after re-login).
  Future<_ApiResp?> _postOnce(String path, Map<String, dynamic> body) async {
    final client = HttpClient();
    client.badCertificateCallback = (cert, host, port) => true;
    try {
      final req = await client.postUrl(Uri.parse('$_baseUrl$path'));
      req.followRedirects = false;
      req.headers.set('Content-Type', 'application/json');
      req.headers.set('Accept', 'application/json');
      req.headers.set('Cookie', 'PHPSESSID=$_phpSessionId');
      req.write(json.encode(body));
      final resp = await req.close();
      final respBody = await resp.transform(utf8.decoder).join();
      print('📬 [GeoFenceApi] RETRY $path → ${resp.statusCode} (${respBody.length}B)');
      client.close();
      return _ApiResp(resp.statusCode, respBody);
    } catch (e) {
      print('❌ [GeoFenceApi] RETRY $path error: $e');
      client.close();
      return null;
    }
  }

  // ═══════════════════════════════════════════════════════════════════════
  //  API Methods — Using existing web endpoints
  // ═══════════════════════════════════════════════════════════════════════

  /// Get all GeoFence designs / configs.
  /// Uses: POST /geo-fence/api/getDesigns (web endpoint)
  Future<List<GeoFenceConfig>> getAllDesigns({
    List<String>? regions,
    List<String>? modes,
    List<String>? modals,
  }) async {
    try {
      final body = <String, dynamic>{
        'mode': modes ?? ['DEVICE', 'REGION'],
        'modal': modals ?? ['AREA', 'ROUTE'],
      };
      // Only include region if it's non-empty — empty array causes server to return no results
      if (regions != null && regions.isNotEmpty) {
        body['region'] = regions;
      }

      final r = await _post('/geo-fence/api/getDesigns', body);

      if (r == null) return [];

      if (r.statusCode == 200) {
        if (r.body.isEmpty) return [];
        final data = json.decode(r.body);

        // Log raw response for debugging
        print('📦 [GeoFenceApi] getDesigns raw (${r.body.length}B): ${r.body.substring(0, r.body.length > 300 ? 300 : r.body.length)}');

        if (data is Map && data['status'] == 200 && data['data'] is List) {
          final list = (data['data'] as List)
              .map((e) => GeoFenceConfig.fromJson(e as Map<String, dynamic>))
              .toList();
          print('✅ [GeoFenceApi] Loaded ${list.length} fence designs');
          return list;
        }
        if (data is Map && data['data'] is List) {
          return (data['data'] as List)
              .map((e) => GeoFenceConfig.fromJson(e as Map<String, dynamic>))
              .toList();
        }
        if (data is List) {
          return data
              .map((e) => GeoFenceConfig.fromJson(e as Map<String, dynamic>))
              .toList();
        }
        print('⚠️ [GeoFenceApi] getDesigns: unexpected format');
      } else {
        print('⚠️ [GeoFenceApi] getDesigns: HTTP ${r.statusCode}');
        if (r.body.isNotEmpty) {
          print('   Body: ${r.body.substring(0, r.body.length > 300 ? 300 : r.body.length)}');
        }
      }
      return [];
    } catch (e) {
      print('❌ [GeoFenceApi] getDesigns error: $e');
      return [];
    }
  }

  /// Get device-specific GeoFence configs.
  /// Uses: POST /user/home/api/geo-configs (web endpoint)
  Future<List<DeviceGeoFence>> getDeviceGeoConfigs({
    List<String>? deviceCodes,
    bool isAchieved = false,
  }) async {
    try {
      final body = <String, dynamic>{
        'isAchieved': isAchieved,
      };
      if (deviceCodes != null && deviceCodes.isNotEmpty) {
        body['deviceCode'] = deviceCodes;
      }
      final r = await _post('/user/home/api/geo-configs', body);
      if (r == null || r.statusCode != 200) return [];
      final data = json.decode(r.body);
      if (data is Map && data['data'] is List) {
        return (data['data'] as List)
            .map((e) => DeviceGeoFence.fromJson(e as Map<String, dynamic>))
            .toList();
      }
      if (data is List) {
        return data
            .map((e) => DeviceGeoFence.fromJson(e as Map<String, dynamic>))
            .toList();
      }
      return [];
    } catch (e) {
      print('❌ [GeoFenceApi] getDeviceGeoConfigs error: $e');
      return [];
    }
  }

  /// Get geofence violation history.
  /// Uses: POST /user/home/api/geo-history (web endpoint)
  Future<List<GeoFenceViolation>> getViolationHistory({
    required String deviceCode,
    required String configCode,
    String? date,
  }) async {
    try {
      final now = DateTime.now();
      final r = await _post('/user/home/api/geo-history', {
        'deviceCode': deviceCode,
        'code': configCode,
        'date': date ??
            '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}',
      });
      if (r == null || r.statusCode != 200) return [];
      final data = json.decode(r.body);
      if (data is Map && data['data'] is List) {
        return (data['data'] as List)
            .map((e) => GeoFenceViolation.fromJson(e as Map<String, dynamic>))
            .toList();
      }
      return [];
    } catch (e) {
      print('❌ [GeoFenceApi] getViolationHistory error: $e');
      return [];
    }
  }

  /// Get geofence alert notification history.
  Future<List<GeoFenceAlert>> getAlertHistory({
    required String from,
    required String to,
    int limit = 100,
  }) async {
    return [];
  }

  /// Generate geofence report.
  Future<List<GeoFenceReportEntry>> getReport({
    required String fromDate,
    required String fromTime,
    required String toDate,
    required String toTime,
    String? code,
    List<String>? modes,
    List<String>? vehicleCodes,
  }) async {
    return [];
  }

  /// Clear session (on logout).
  void clearSession() {
    _authService = null;
    _phpSessionId = null;
    _isSessionValid = false;
  }
}

/// Simple response wrapper.
class _ApiResp {
  final int statusCode;
  final String body;
  _ApiResp(this.statusCode, this.body);
}
