/// Where the SDK keeps the last signed payload and the snooze ledger.
///
/// The cache is what makes the product work offline and what makes a kill
/// switch stick: the payload is stored **with its signature** and re-verified
/// on read, so a cached config carries exactly as much authority as a fresh
/// one. Tampering with the stored file gets you a failed verification and an
/// app that behaves as if it had no rules — never one that obeys a forged kill.
library;

import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// A signed payload exactly as it arrived.
class CachedConfig {
  const CachedConfig({
    required this.body,
    required this.signature,
    required this.keyId,
    required this.etag,
    required this.fetchedAt,
  });

  /// The raw response body. Never re-serialized — the signature covers these
  /// bytes and only these bytes.
  final String body;
  final String signature;
  final String keyId;
  final String? etag;
  final DateTime fetchedAt;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'body': body,
        'sig': signature,
        'key_id': keyId,
        'etag': etag,
        'fetched_at': fetchedAt.toIso8601String(),
      };

  static CachedConfig? fromJson(Map<String, dynamic> json) {
    final body = json['body'] as String?;
    final sig = json['sig'] as String?;
    final keyId = json['key_id'] as String?;
    if (body == null || sig == null || keyId == null) return null;
    return CachedConfig(
      body: body,
      signature: sig,
      keyId: keyId,
      etag: json['etag'] as String?,
      fetchedAt: DateTime.tryParse(json['fetched_at'] as String? ?? '') ??
          DateTime.now(),
    );
  }
}

/// Snooze accounting for one target version.
class SnoozeRecord {
  const SnoozeRecord(
      {required this.version, required this.count, required this.lastAt});

  /// Which target this counts against; a new target resets the allowance,
  /// because a fresh release is a fresh ask.
  final String version;
  final int count;
  final DateTime? lastAt;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'version': version,
        'count': count,
        'last_at': lastAt?.toIso8601String(),
      };

  static SnoozeRecord? fromJson(Map<String, dynamic> json) {
    final version = json['version'] as String?;
    if (version == null) return null;
    return SnoozeRecord(
      version: version,
      count: (json['count'] as num?)?.toInt() ?? 0,
      lastAt: DateTime.tryParse(json['last_at'] as String? ?? ''),
    );
  }
}

/// Swap this out to store elsewhere — secure storage, your own database, or
/// nothing at all in tests.
abstract class RipstopStorage {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

/// The default: `shared_preferences`, which is already in most Flutter apps.
class SharedPreferencesStorage implements RipstopStorage {
  @override
  Future<String?> read(String key) async =>
      (await SharedPreferences.getInstance()).getString(key);

  @override
  Future<void> write(String key, String value) async =>
      (await SharedPreferences.getInstance()).setString(key, value);

  @override
  Future<void> delete(String key) async =>
      (await SharedPreferences.getInstance()).remove(key);
}

/// For tests and for apps that would rather keep nothing on disk. Losing the
/// cache is safe by design — it costs offline support, not correctness.
class InMemoryStorage implements RipstopStorage {
  final Map<String, String> _values = <String, String>{};

  @override
  Future<String?> read(String key) async => _values[key];

  @override
  Future<void> write(String key, String value) async => _values[key] = value;

  @override
  Future<void> delete(String key) async => _values.remove(key);
}

/// Typed access over whichever [RipstopStorage] is in use.
class ConfigStore {
  ConfigStore(this.storage, this.apiKey);

  final RipstopStorage storage;

  /// Namespaced by key so two Ripstop-powered apps, or two environments of
  /// one app, never read each other's cache.
  final String apiKey;

  String get _configKey => 'ripstop.config.$apiKey';
  String get _snoozeKey => 'ripstop.snooze.$apiKey';
  String get _installKey => 'ripstop.install.$apiKey';
  String get _userKey => 'ripstop.user.$apiKey';

  /// The id this install is known by in the panel's Users view.
  ///
  /// Minted once, here, and never derived from the device: a random value
  /// names *an install of this app* and nothing else. Reinstalling mints a new
  /// one, which is the honest behaviour — a fresh install is a fresh row.
  Future<String> readOrMintInstallId(String Function() mint) async {
    final existing = await storage.read(_installKey);
    if (existing != null && existing.isNotEmpty) return existing;
    final minted = mint();
    await storage.write(_installKey, minted);
    return minted;
  }

  Future<String?> readUserId() => storage.read(_userKey);

  Future<void> writeUserId(String? id) =>
      id == null ? storage.delete(_userKey) : storage.write(_userKey, id);

  Future<CachedConfig?> readConfig() async {
    final raw = await storage.read(_configKey);
    if (raw == null) return null;
    try {
      return CachedConfig.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  Future<void> writeConfig(CachedConfig config) =>
      storage.write(_configKey, jsonEncode(config.toJson()));

  Future<SnoozeRecord?> readSnooze() async {
    final raw = await storage.read(_snoozeKey);
    if (raw == null) return null;
    try {
      return SnoozeRecord.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  Future<void> writeSnooze(SnoozeRecord record) =>
      storage.write(_snoozeKey, jsonEncode(record.toJson()));
}
