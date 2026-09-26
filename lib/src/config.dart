import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api.dart';

/// The signed-in device. The device token lives in secure storage; everything else in
/// preferences. [SharedPreferencesAsync] doesn't cache, so background isolates always
/// read what the UI isolate wrote.
class Account {
  Account({required this.server, required this.deviceId, required this.deviceName, required this.token});

  final String server;
  final String deviceId;
  final String deviceName;
  final String token;

  ViaApi api() => ViaApi(server, token: token);

  static const _secure = FlutterSecureStorage();
  static final _prefs = SharedPreferencesAsync();

  static Future<Account?> load() async {
    final server = await _prefs.getString('server');
    final deviceId = await _prefs.getString('device_id');
    final deviceName = await _prefs.getString('device_name');
    String? token;
    try {
      token = await _secure.read(key: 'device_token');
    } catch (_) {
      token = null;
    }
    if (server == null || deviceId == null || token == null) return null;
    return Account(server: server, deviceId: deviceId, deviceName: deviceName ?? '', token: token);
  }

  Future<void> save() async {
    await _secure.write(key: 'device_token', value: token);
    await _prefs.setString('server', server);
    await _prefs.setString('device_id', deviceId);
    await _prefs.setString('device_name', deviceName);
  }

  Account withName(String name) =>
      Account(server: server, deviceId: deviceId, deviceName: name, token: token);

  static Future<void> clear() async {
    await _secure.delete(key: 'device_token');
    await _prefs.remove('device_id');
    await _prefs.remove('device_name');
    await _prefs.remove('push_registration');
    // Keep 'server' so signing in again is quicker.
  }

  static Future<String?> lastServer() => _prefs.getString('server');
}

/// Small persisted flags shared between isolates.
class Prefs {
  static final _prefs = SharedPreferencesAsync();

  static Future<String?> getString(String key) => _prefs.getString(key);
  static Future<void> setString(String key, String value) => _prefs.setString(key, value);
  static Future<bool> getBool(String key, {bool fallback = false}) async =>
      await _prefs.getBool(key) ?? fallback;
  static Future<void> setBool(String key, bool value) => _prefs.setBool(key, value);
}
