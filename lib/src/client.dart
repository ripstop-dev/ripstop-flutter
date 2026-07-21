/// The client: fetch, verify, cache, decide.
///
/// Every rule in here exists to protect the host app from us. A config service
/// that can hang your launch, crash on a malformed response, or lock users out
/// because a CDN had a bad minute is worse than no config service — so the
/// fetch is bounded, every failure path resolves to a decision, and the cache
/// is re-verified rather than trusted.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;
import 'dart:math' show Random;

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'config.dart';
import 'decision.dart';
import 'evaluate.dart';
import 'storage.dart';
import 'verify.dart';

/// Which environment's config to read. One per app today (ADR-042); the
/// parameter stays so adding a staging environment is not a breaking change.
enum RsEnv { production }

const String _defaultEndpoint = 'https://cfg.ripstop.dev/v1/config';

/// The result of a check, plus where the config behind it came from.
class RsResult {
  const RsResult({required this.decision, required this.source});

  final RsDecision decision;

  /// `fresh` from the network, `cached` from the last signed payload, or
  /// `none` when there is neither — in which case [decision] is [RsNone].
  final ConfigSource source;
}

class Ripstop {
  Ripstop._({
    required this.apiKey,
    required this.appVersion,
    required this.platform,
    required this.locale,
    required this.minFetchInterval,
    required this.timeout,
    required ConfigStore store,
    required SignatureVerifier verifier,
    required String endpoint,
    required http.Client httpClient,
  })  : _store = store,
        _verifier = verifier,
        _endpoint = endpoint,
        _http = httpClient;

  final String apiKey;
  final String appVersion;
  final String platform;
  final String locale;

  /// How long a fresh payload is considered fresh enough to skip the network.
  final Duration minFetchInterval;
  final Duration timeout;

  final ConfigStore _store;
  final SignatureVerifier _verifier;
  final String _endpoint;
  final http.Client _http;

  RipstopConfig? _config;
  ConfigSource _source = ConfigSource.none;
  late final String _installId;
  String? _userId;

  /// The id this install is known by in the panel's Users view. Random,
  /// minted on first launch, persisted alongside the cache.
  String get installId => _installId;

  /// Your own id for this user, if you have one — shown in the panel next to
  /// ours so a support thread can find the right install. Persisted, and sent
  /// from the next check onwards; set it to null to stop sending it.
  String? get userId => _userId;

  set userId(String? id) {
    _userId = id;
    // Fire-and-forget: identity is advisory metadata, and a failed write only
    // costs the label until the next launch — never a decision.
    unawaited(_store.writeUserId(id));
  }

  /// Everything the panel published under `values`, from the payload currently
  /// driving decisions. Empty until the first successful check.
  Map<String, dynamic> get values =>
      _config?.values ?? const <String, dynamic>{};

  /// The rule in force for this platform, if there is one.
  ///
  /// Exposed so a wall can show the user where they actually stand — the
  /// version they are on, the one that unblocks them, the newest one. That
  /// turns "you are too old" into something they can check themselves
  /// against, rather than a refusal they have to take on faith.
  UpdateEntry? get rule => _config?.update[platform];

  ConfigSource get source => _source;

  /// Starts the SDK and performs the first check.
  ///
  /// This never throws. A missing network, a wrong key, a mangled response —
  /// all of them resolve to a working instance whose decision is [RsNone].
  static Future<Ripstop> init({
    required String apiKey,
    required String appVersion,
    String? platform,
    String locale = 'en',
    RsEnv environment = RsEnv.production,
    Duration minFetchInterval = const Duration(hours: 6),
    Duration timeout = const Duration(seconds: 5),
    Map<String, String>? signingKeys,
    RipstopStorage? storage,
    String endpoint = _defaultEndpoint,
    http.Client? httpClient,
  }) async {
    final resolvedPlatform = platform ?? _detectPlatform();
    final instance = Ripstop._(
      apiKey: apiKey,
      appVersion: appVersion,
      platform: resolvedPlatform,
      locale: locale,
      minFetchInterval: minFetchInterval,
      timeout: timeout,
      store: ConfigStore(storage ?? SharedPreferencesStorage(), apiKey),
      verifier: SignatureVerifier(signingKeys ?? productionKeys),
      endpoint: endpoint,
      httpClient: httpClient ?? http.Client(),
    );
    instance._installId = await instance._store.readOrMintInstallId(_mintId);
    instance._userId = await instance._store.readUserId();
    await instance.refresh();
    return instance;
  }

  /// 128 bits of `Random.secure()`, hex-encoded. Enough that two installs
  /// never collide, and carrying nothing that describes the device.
  static String _mintId() {
    final rng = Random.secure();
    final bytes = List<int>.generate(16, (_) => rng.nextInt(256));
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  static String _detectPlatform() {
    if (kIsWeb) return 'web';
    try {
      if (Platform.isIOS || Platform.isMacOS) return 'ios';
      if (Platform.isAndroid) return 'android';
    } catch (_) {
      // Platform is unavailable on some targets; 'web' is the safe answer
      // because it has no update rules and therefore fails open.
    }
    return 'web';
  }

  /// Fetches unless the cached payload is younger than [minFetchInterval],
  /// then re-evaluates. Returns the decision for this launch.
  Future<RsDecision> check({bool force = false}) async {
    if (force || _config == null) await refresh(force: force);
    return _decide();
  }

  /// Same as [check], but also reports where the config came from.
  Future<RsResult> checkDetailed({bool force = false}) async {
    if (force || _config == null) await refresh(force: force);
    return RsResult(decision: _decide(), source: _source);
  }

  /// Fetch, verify, cache. Safe to call as often as you like — it respects
  /// [minFetchInterval] unless forced.
  Future<void> refresh({bool force = false}) async {
    final cached = await _store.readConfig();

    if (!force && cached != null) {
      final age = DateTime.now().difference(cached.fetchedAt);
      if (age < minFetchInterval) {
        await _adopt(cached, ConfigSource.cached);
        return;
      }
    }

    final outcome = await _fetch(cached);
    if (outcome != FetchOutcome.ok) {
      // Fail open, with the last thing we know to be genuine.
      final fallback = cached ?? await _store.readConfig();
      final hasCache = fallback != null;
      _source = resolveConfigSource(outcome, hasCache: hasCache);
      if (hasCache) {
        await _adopt(fallback, ConfigSource.cached);
      } else {
        _config = null;
      }
    }
  }

  Future<FetchOutcome> _fetch(CachedConfig? cached) async {
    final uri = Uri.parse('$_endpoint?key=$apiKey');

    try {
      final response = await _http.get(
        uri,
        headers: <String, String>{
          if (cached?.etag != null) 'if-none-match': cached!.etag!,
          'x-ripstop-platform': platform,
          'x-ripstop-app-version': appVersion,
          // What the panel's Users view is built from. The install id is a
          // random mint (see _mintId); the user id is whatever the host app
          // chose to set, and absent otherwise.
          'x-ripstop-device': _installId,
          if (_userId != null && _userId!.isNotEmpty) 'x-ripstop-user': _userId!,
        },
      ).timeout(timeout);

      // 304: what we already hold is current. Re-stamp it so the interval
      // measures "last confirmed", not "last changed".
      if (response.statusCode == 304 && cached != null) {
        final restamped = CachedConfig(
          body: cached.body,
          signature: cached.signature,
          keyId: cached.keyId,
          etag: cached.etag,
          fetchedAt: DateTime.now(),
        );
        await _store.writeConfig(restamped);
        await _adopt(restamped, ConfigSource.fresh);
        return FetchOutcome.ok;
      }

      if (response.statusCode != 200) return FetchOutcome.httpError;

      final signature = response.headers['x-ripstop-sig'];
      final keyId = response.headers['x-ripstop-key-id'];
      if (signature == null || keyId == null) {
        return FetchOutcome.invalidSignature;
      }

      // The signature covers exactly these bytes. Decoding as UTF-8 rather
      // than using `response.body` avoids charset guessing changing them.
      final body = utf8.decode(response.bodyBytes);
      final genuine = await _verifier.verify(
        body: body,
        signature: signature,
        keyId: keyId,
      );
      if (!genuine) return FetchOutcome.invalidSignature;

      final fresh = CachedConfig(
        body: body,
        signature: signature,
        keyId: keyId,
        etag: response.headers['etag'],
        fetchedAt: DateTime.now(),
      );
      await _store.writeConfig(fresh);
      await _adopt(fresh, ConfigSource.fresh);
      return FetchOutcome.ok;
    } on TimeoutException {
      return FetchOutcome.timeout;
    } catch (_) {
      return FetchOutcome.httpError;
    }
  }

  /// Adopts a stored payload only if it still verifies. A cache is a file on a
  /// device someone else may control, so it gets the same scrutiny the network
  /// does — this is what stops "edit the cache, escape the kill switch".
  Future<void> _adopt(CachedConfig cached, ConfigSource source) async {
    final genuine = await _verifier.verify(
      body: cached.body,
      signature: cached.signature,
      keyId: cached.keyId,
    );
    if (!genuine) {
      _config = null;
      _source = ConfigSource.none;
      return;
    }

    try {
      _config = RipstopConfig.fromJson(
          jsonDecode(cached.body) as Map<String, dynamic>);
      _source = source;
    } catch (_) {
      _config = null;
      _source = ConfigSource.none;
    }
  }

  RsDecision _decide() {
    final config = _config;
    if (config == null) return const RsNone();
    return evaluate(
      config,
      EvaluateContext(
        platform: platform,
        appVersion: appVersion,
        locale: locale,
        snooze: _snoozeState,
      ),
    );
  }

  SnoozeState _snoozeState = const SnoozeState.none();

  /// Loads the snooze ledger for the current target version. Call before
  /// [check] if you drive the UI yourself; [RipstopShell] does it for you.
  Future<void> loadSnooze() async {
    final target = _config?.update[platform]?.target;
    if (target == null) {
      _snoozeState = const SnoozeState.none();
      return;
    }

    final record = await _store.readSnooze();
    // A new target is a new ask: the allowance resets rather than carrying a
    // grudge from the release before.
    if (record == null || record.version != target) {
      _snoozeState = const SnoozeState.none();
      return;
    }

    final last = record.lastAt;
    _snoozeState = SnoozeState(
      count: record.count,
      hoursSinceLast: last == null
          ? null
          : DateTime.now().difference(last).inMinutes / 60.0,
    );
  }

  /// Records a snooze of the current soft prompt and re-evaluates.
  Future<RsDecision> snooze() async {
    final target = _config?.update[platform]?.target;
    if (target == null) return _decide();

    final existing = await _store.readSnooze();
    final count = (existing != null && existing.version == target)
        ? existing.count + 1
        : 1;

    await _store.writeSnooze(
      SnoozeRecord(version: target, count: count, lastAt: DateTime.now()),
    );
    await loadSnooze();
    return _decide();
  }

  void dispose() => _http.close();
}
