import 'dart:convert';
import 'dart:io' show HttpClient, ContentType;
import 'package:http/http.dart' as http;
import '../models/traknova_device.dart';
import 'auth_service.dart';

/// Fetches the device list from the TrakNova web dashboard by scraping
/// the `/user/home` page and extracting the DEVICES[] JavaScript variable.
///
/// The web dashboard uses PHP session-based auth (PHPSESSID cookie),
/// NOT the API token. So we first do a web login POST to get a session,
/// then scrape the dashboard page.
class DeviceDataService {
  static final DeviceDataService _instance = DeviceDataService._internal();
  factory DeviceDataService() => _instance;
  DeviceDataService._internal();

  static const String _baseUrl = 'https://app.traknova.co.uk';

  List<TraknovaDevice> _devices = [];
  Map<String, dynamic> _sensors = {};
  Map<String, dynamic> _levels = {};
  String _entityCode = '';
  bool _isLoaded = false;
  String? _sessionCookie; // PHPSESSID from web login

  List<TraknovaDevice> get devices => _devices;
  Map<String, dynamic> get sensors => _sensors;
  Map<String, dynamic> get levels => _levels;
  String get entityCode => _entityCode;
  bool get isLoaded => _isLoaded;

  // ── Public API ──────────────────────────────────────────────────────────

  /// Load device list from the web dashboard.
  /// 1. Web-login to get PHPSESSID
  /// 2. Scrape /user/home with that cookie
  Future<List<TraknovaDevice>> loadDevices(AuthService authService) async {
    try {
      print('📡 [DeviceDataService] Loading devices from web dashboard...');

      // Step 1: Get a web session cookie
      _sessionCookie = await _getWebSession(authService);

      String html;

      if (_sessionCookie != null) {
        // Step 2a: Scrape using web session
        print('🍪 [DeviceDataService] Got web session, scraping dashboard...');
        html = await _fetchWithSession(_sessionCookie!);
      } else {
        // Step 2b: Fallback — try with API token headers
        print('⚠️ [DeviceDataService] No web session, trying token auth...');
        html = await _fetchWithToken(authService);
      }

      _parseHtml(html);

      print('✅ [DeviceDataService] Loaded ${_devices.length} devices');
      for (final d in _devices) {
        print('   📍 ${d.vehicleNo} (${d.imei}) — ${d.isOnline ? "ONLINE" : "OFFLINE"}');
      }

      _isLoaded = true;
      return _devices;
    } catch (e) {
      print('❌ [DeviceDataService] Error loading devices: $e');
      return _devices;
    }
  }

  // ── Web session login ───────────────────────────────────────────────────

  /// Perform web login to get a PHPSESSID cookie.
  /// The login form at `/` uses fields: username, password, token (CSRF).
  /// Flow: GET / → extract CSRF token → POST / with credentials.
  Future<String?> _getWebSession(AuthService authService) async {
    final username = await authService.getStoredUsername();
    final password = authService.currentPassword;

    if (username == null || password == null) {
      print('⚠️ [DeviceDataService] No stored credentials for web login');
      return null;
    }

    try {
      print('🔐 [DeviceDataService] Web login for $username ...');

      final client = HttpClient();
      client.autoUncompress = true;

      // Step 1: GET the login page to obtain CSRF token and initial cookie
      final getReq = await client.getUrl(Uri.parse(_baseUrl));
      getReq.followRedirects = false;
      final getResp = await getReq.close().timeout(const Duration(seconds: 15));

      // Read the login page HTML
      final loginHtml = await getResp.transform(utf8.decoder).join();

      // Extract CSRF token from: <input type="hidden" name="token" value="..."/>
      final csrfMatch = RegExp(r'name="token"\s+value="([^"]+)"').firstMatch(loginHtml);
      if (csrfMatch == null) {
        print('⚠️ [DeviceDataService] Could not find CSRF token in login page');
        client.close(force: true);
        return null;
      }
      final csrfToken = csrfMatch.group(1)!;
      print('   🔑 Got CSRF token: ${csrfToken.substring(0, 10)}...');

      // Extract initial PHPSESSID
      String? initialSession;
      for (final cookie in getResp.cookies) {
        if (cookie.name == 'PHPSESSID') {
          initialSession = cookie.value;
        }
      }
      // Also check raw headers
      if (initialSession == null) {
        final rawCookies = getResp.headers['set-cookie'];
        if (rawCookies != null) {
          for (final line in rawCookies) {
            final m = RegExp(r'PHPSESSID=([^;]+)').firstMatch(line);
            if (m != null) { initialSession = m.group(1); break; }
          }
        }
      }

      // Step 2: POST login with correct field names
      final postReq = await client.postUrl(Uri.parse(_baseUrl));
      postReq.headers.contentType =
          ContentType('application', 'x-www-form-urlencoded');
      postReq.followRedirects = false;
      // Send the initial session cookie if we got one
      if (initialSession != null) {
        postReq.headers.add('Cookie', 'PHPSESSID=$initialSession');
      }
      postReq.write(
        'username=${Uri.encodeQueryComponent(username)}'
        '&password=${Uri.encodeQueryComponent(password)}'
        '&token=${Uri.encodeQueryComponent(csrfToken)}',
      );

      final postResp = await postReq.close().timeout(const Duration(seconds: 15));

      // DEBUG: log POST response details
      print('   📬 POST status: ${postResp.statusCode}');
      print('   📬 POST redirect: ${postResp.headers.value("location")}');
      final postBody = await postResp.transform(utf8.decoder).join();
      print('   📬 POST body length: ${postBody.length}');
      if (postBody.length < 1000) {
        print('   📬 POST body: $postBody');
      } else {
        print('   📬 POST body (first 500): ${postBody.substring(0, 500)}');
      }

      // Extract PHPSESSID from response
      String? sessionId;
      for (final cookie in postResp.cookies) {
        print('   🍪 Cookie: ${cookie.name}=${cookie.value.substring(0, (cookie.value.length > 20 ? 20 : cookie.value.length))}...');
        if (cookie.name == 'PHPSESSID') {
          sessionId = cookie.value;
        }
      }
      if (sessionId == null) {
        final rawCookies = postResp.headers['set-cookie'];
        if (rawCookies != null) {
          for (final line in rawCookies) {
            print('   🍪 Raw Set-Cookie: ${line.substring(0, (line.length > 80 ? 80 : line.length))}...');
            final m = RegExp(r'PHPSESSID=([^;]+)').firstMatch(line);
            if (m != null) { sessionId = m.group(1); break; }
          }
        }
      }
      // If no new cookie, the initial one might be valid (login succeeded in-place)
      sessionId ??= initialSession;
      print('   🍪 Final session ID: ${sessionId != null ? sessionId.substring(0, sessionId.length > 20 ? 20 : sessionId.length) : "null"}...');

      client.close(force: true);

      if (sessionId != null) {
        // Verify: try fetching /user/home with this session
        final verified = await _verifySession(sessionId);
        if (verified) {
          print('✅ [DeviceDataService] Web login succeeded, session verified');
          return sessionId;
        } else {
          print('⚠️ [DeviceDataService] Got session but /user/home redirects (bad credentials?)');
          return null;
        }
      }

      print('❌ [DeviceDataService] No PHPSESSID obtained from login');
      return null;
    } catch (e) {
      print('⚠️ [DeviceDataService] Web login failed: $e');
      return null;
    }
  }

  /// Verify a session cookie by checking if /user/home returns 200 (not redirect).
  Future<bool> _verifySession(String sessionId) async {
    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/user/home'),
        headers: {
          'Cookie': 'PHPSESSID=$sessionId',
          'Accept': 'text/html',
        },
      ).timeout(const Duration(seconds: 10));
      print('   🔍 Verify: status=${response.statusCode}, body length=${response.body.length}');
      print('   🔍 Verify: has DEVICES=${response.body.contains('DEVICES')}');
      if (!response.body.contains('DEVICES')) {
        // Show what we got instead
        final snippet = response.body.length > 500
            ? response.body.substring(0, 500)
            : response.body;
        print('   🔍 Verify HTML snippet: $snippet');
      }
      return response.statusCode == 200 && response.body.contains('DEVICES');
    } catch (e) {
      print('   ❌ Verify error: $e');
      return false;
    }
  }

  // ── Fetch methods ───────────────────────────────────────────────────────

  Future<String> _fetchWithSession(String sessionId) async {
    final response = await http.get(
      Uri.parse('$_baseUrl/user/home'),
      headers: {
        'Cookie': 'PHPSESSID=$sessionId',
        'Accept': 'text/html,application/xhtml+xml',
      },
    ).timeout(const Duration(seconds: 30));

    if (response.statusCode != 200) {
      print('❌ [DeviceDataService] HTTP ${response.statusCode} with session');
    }
    return response.body;
  }

  Future<String> _fetchWithToken(AuthService authService) async {
    final headers = await authService.getAuthHeaders();
    headers['Accept'] = 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8';

    final response = await http.get(
      Uri.parse('$_baseUrl/user/home'),
      headers: headers,
    ).timeout(const Duration(seconds: 30));

    print('🔍 [DeviceDataService] Token auth: status=${response.statusCode}, length=${response.body.length}');
    if (response.body.length < 1000) {
      print('🔍 [DeviceDataService] Token HTML: ${response.body}');
    } else {
      print('🔍 [DeviceDataService] Token HTML (first 500): ${response.body.substring(0, 500)}');
    }
    if (response.statusCode != 200) {
      print('❌ [DeviceDataService] HTTP ${response.statusCode} with token');
    }
    return response.body;
  }

  // ── HTML parsing ────────────────────────────────────────────────────────

  void _parseHtml(String html) {
    // Log a snippet of the page for debugging
    print('🔍 [DeviceDataService] HTML length: ${html.length} chars');
    if (html.length < 500) {
      print('🔍 [DeviceDataService] Full HTML: $html');
    } else {
      // Check if it looks like a login page
      if (html.contains('login') && html.contains('_username')) {
        print('⚠️ [DeviceDataService] Response appears to be a LOGIN page (auth failed)');
      }
    }

    // Try multiple regex patterns for DEVICES variable
    final patterns = [
      RegExp(r'let\s+DEVICES\s*=\s*(\[[\s\S]*?\]);'),
      RegExp(r'var\s+DEVICES\s*=\s*(\[[\s\S]*?\]);'),
      RegExp(r'const\s+DEVICES\s*=\s*(\[[\s\S]*?\]);'),
      RegExp(r'DEVICES\s*=\s*(\[[\s\S]*?\]);'),
    ];

    for (final pattern in patterns) {
      final devicesMatch = pattern.firstMatch(html);
      if (devicesMatch != null) {
        try {
          final jsonStr = devicesMatch.group(1)!;
          final List<dynamic> deviceList = jsonDecode(jsonStr);
          _devices = deviceList
              .whereType<Map<String, dynamic>>()
              .map((json) => TraknovaDevice.fromJson(json))
              .where((d) => d.imei.isNotEmpty)
              .toList();
          print('✅ [DeviceDataService] Parsed ${_devices.length} devices with pattern: ${pattern.pattern.substring(0, 20)}...');
          break;
        } catch (e) {
          print('⚠️ [DeviceDataService] Error parsing DEVICES with pattern: $e');
        }
      }
    }

    if (_devices.isEmpty && !html.contains('DEVICES')) {
      print('⚠️ [DeviceDataService] DEVICES variable not found in HTML');
    }

    // Extract SENSORS = {...};
    final sensorsMatch = RegExp(r'(?:let|var|const)\s+SENSORS\s*=\s*(\{[\s\S]*?\});').firstMatch(html);
    if (sensorsMatch != null) {
      try {
        _sensors = jsonDecode(sensorsMatch.group(1)!) as Map<String, dynamic>;
      } catch (e) {
        print('⚠️ [DeviceDataService] Error parsing SENSORS: $e');
      }
    }

    // Extract LEVELS = {...};
    final levelsMatch = RegExp(r'(?:let|var|const)\s+LEVELS\s*=\s*(\{[\s\S]*?\});').firstMatch(html);
    if (levelsMatch != null) {
      try {
        _levels = jsonDecode(levelsMatch.group(1)!) as Map<String, dynamic>;
      } catch (e) {
        print('⚠️ [DeviceDataService] Error parsing LEVELS: $e');
      }
    }

    // Extract E_CODE = '...';
    final eCodeMatch = RegExp(r"(?:let|var|const)\s+E_CODE\s*=\s*'([^']+)';").firstMatch(html);
    if (eCodeMatch != null) {
      _entityCode = eCodeMatch.group(1)!;
      print('📋 [DeviceDataService] Entity code: $_entityCode');
    }
  }

  // ── Device MQTT updates ─────────────────────────────────────────────────

  /// Find a device by IMEI.
  TraknovaDevice? findByImei(String imei) {
    try {
      return _devices.firstWhere((d) => d.imei == imei);
    } catch (_) {
      return null;
    }
  }

  /// Update a device with MQTT live data.
  void updateDeviceFromMqtt(String imei, Map<String, dynamic> data) {
    final device = findByImei(imei);
    if (device != null) {
      device.updateFromMqtt(data);
    }
  }

  /// Called for every MQTT message. If the IMEI is unknown, creates a new
  /// placeholder device so it appears in the UI immediately — no web login needed.
  /// Returns true if a NEW device was created.
  bool autoDiscoverFromMqtt(String imei, Map<String, dynamic> data) {
    if (imei.isEmpty) return false;

    final existing = findByImei(imei);
    if (existing != null) {
      existing.updateFromMqtt(data);
      return false;
    }

    // Create a minimal placeholder using whatever data the MQTT message contains
    final vehicleNo = data['vehicleNo']?.toString() ??
        data['vehicle_no']?.toString() ??
        data['plate']?.toString() ??
        imei;
    final deviceName = data['deviceName']?.toString() ??
        data['device_name']?.toString() ??
        'Device $imei';

    final device = TraknovaDevice(
      imei: imei,
      deviceCode: data['deviceCode']?.toString() ?? imei,
      deviceName: deviceName,
      vehicleNo: vehicleNo,
      geoDiff: 5,
      speedLimit: 70,
      engineMode: true,
      initState: 'OFFLINE',
    );
    device.updateFromMqtt(data);
    _devices.add(device);
    _isLoaded = true;
    print('🛣️ [DeviceDataService] Auto-discovered device: $vehicleNo ($imei)');
    return true;
  }

  /// Get online devices.
  List<TraknovaDevice> get onlineDevices =>
      _devices.where((d) => d.isOnline).toList();

  /// Get offline devices.
  List<TraknovaDevice> get offlineDevices =>
      _devices.where((d) => !d.isOnline).toList();
}
