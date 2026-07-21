/// What the client promises when things go wrong, which is the only time
/// anybody finds out whether a config SDK was written carefully.
///
/// These use a real Ed25519 key pair and a stub HTTP client, so the signature
/// path is exercised for real rather than mocked away — a verifier that is
/// stubbed in tests is a verifier nobody has checked.
library;

import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:ripstop/ripstop.dart';

const String _key = 'rs_pub_test';
const String _keyId = 'k1';

/// Serves whatever the test tells it to, and counts calls.
class _StubClient extends http.BaseClient {
  _StubClient(this.respond);

  final Future<http.Response> Function(http.Request request) respond;
  int calls = 0;
  final List<Map<String, String>> seenHeaders = <Map<String, String>>[];

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    calls++;
    seenHeaders.add(Map<String, String>.from(request.headers));
    final response = await respond(request as http.Request);
    return http.StreamedResponse(
      Stream<List<int>>.value(response.bodyBytes),
      response.statusCode,
      headers: response.headers,
    );
  }
}

Map<String, dynamic> _config({
  bool killActive = false,
  String iosMin = '4.0.0',
  String iosTarget = '4.2.0',
}) =>
    <String, dynamic>{
      'v': 1,
      'app': 'app_test',
      'env': 'production',
      'published_at': '2026-01-01T00:00:00Z',
      'key_id': _keyId,
      'kill': <String, dynamic>{
        'active': killActive,
        'platforms': <String>[],
        'version_ranges': <dynamic>[],
        'message_key': 'kill_default',
      },
      'maintenance': <String, dynamic>{
        'active': false,
        'starts_at': null,
        'ends_at': null,
        'message_key': 'maint_default',
        'show_eta': true,
      },
      'update': <String, dynamic>{
        'ios': <String, dynamic>{
          'min': iosMin,
          'target': iosTarget,
          'store_url': 'https://store.example/ios',
          'soft': <String, dynamic>{'max_snoozes': 2, 'cooldown_hours': 24},
        },
      },
      'values': <String, dynamic>{'checkout_enabled': true},
      'messages': <String, dynamic>{
        'en': <String, dynamic>{
          'force_title': 'Update required',
          'force_body': 'Please update.',
          'soft_title': 'Update available',
          'soft_body': 'A new version is ready.',
          'kill_default': 'App unavailable',
        },
      },
    };

void main() {
  late SimpleKeyPair keyPair;
  late String publicKeyB64;

  setUp(() async {
    keyPair = await Ed25519().newKeyPair();
    final pub = await keyPair.extractPublicKey();
    publicKeyB64 = base64Encode(pub.bytes);
  });

  Future<http.Response> sign(Map<String, dynamic> config,
      {int status = 200}) async {
    final body = jsonEncode(config);
    final signature = await Ed25519().sign(utf8.encode(body), keyPair: keyPair);
    return http.Response(
      body,
      status,
      headers: <String, String>{
        'x-ripstop-sig': base64Encode(signature.bytes),
        'x-ripstop-key-id': _keyId,
        'etag': '"cfg_1"',
      },
    );
  }

  Future<Ripstop> boot(
    _StubClient client, {
    String appVersion = '3.0.0',
    RipstopStorage? storage,
    Map<String, String>? keys,
  }) =>
      Ripstop.init(
        apiKey: _key,
        appVersion: appVersion,
        platform: 'ios',
        signingKeys: keys ?? <String, String>{_keyId: publicKeyB64},
        storage: storage ?? InMemoryStorage(),
        httpClient: client,
      );

  test('a genuine payload drives the decision', () async {
    final client = _StubClient((_) => sign(_config()));
    final gate = await boot(client);

    expect(await gate.check(), isA<RsForceUpdate>());
    expect(gate.source, ConfigSource.fresh);
    expect(gate.values['checkout_enabled'], true);
  });

  test('a forged signature is refused and the app runs', () async {
    final client = _StubClient((_) async {
      final body = jsonEncode(_config(killActive: true));
      return http.Response(body, 200, headers: <String, String>{
        // Right shape, wrong key: exactly what a hostile CDN would return.
        'x-ripstop-sig': base64Encode(List<int>.filled(64, 7)),
        'x-ripstop-key-id': _keyId,
      });
    });

    final gate = await boot(client);
    expect(await gate.check(), isA<RsNone>(),
        reason: 'an unverified payload must never be able to kill an app');
    expect(gate.source, ConfigSource.none);
  });

  test('an unknown key id is refused', () async {
    final client = _StubClient((_) => sign(_config()));
    final gate =
        await boot(client, keys: <String, String>{'other': publicKeyB64});
    expect(await gate.check(), isA<RsNone>());
  });

  test('a network failure falls back to the cached payload', () async {
    final storage = InMemoryStorage();
    final good = _StubClient((_) => sign(_config(killActive: true)));
    final first = await boot(good, storage: storage);
    expect(await first.check(), isA<RsKilled>());

    // Same storage, a server that is now on fire.
    final broken = _StubClient((_) async => http.Response('nope', 500));
    final second = await boot(broken, storage: storage);

    expect(await second.check(), isA<RsKilled>(),
        reason: 'a kill must survive the network going away');
    expect(second.source, ConfigSource.cached);
  });

  test('with no cache, a network failure means no rules at all', () async {
    final client = _StubClient((_) async => http.Response('nope', 500));
    final gate = await boot(client);
    expect(await gate.check(), isA<RsNone>());
    expect(gate.source, ConfigSource.none);
  });

  test('a tampered cache is refused', () async {
    final storage = InMemoryStorage();
    final client = _StubClient((_) => sign(_config(killActive: true)));
    await boot(client, storage: storage);

    // Someone edits the file to lift the kill.
    final raw = await storage.read('ripstop.config.$_key');
    final entry = jsonDecode(raw!) as Map<String, dynamic>;
    entry['body'] = jsonEncode(_config());
    await storage.write('ripstop.config.$_key', jsonEncode(entry));

    final offline = _StubClient((_) async => http.Response('nope', 500));
    final gate = await boot(offline, storage: storage);
    expect(await gate.check(), isA<RsNone>(),
        reason: 'edited cache fails verification, so it grants nothing');
  });

  test('a fresh payload inside the interval is not refetched', () async {
    final storage = InMemoryStorage();
    final client = _StubClient((_) => sign(_config()));

    await boot(client, storage: storage);
    expect(client.calls, 1);

    await boot(client, storage: storage);
    expect(client.calls, 1, reason: 'still inside minFetchInterval');
  });

  test('the conditional request carries the stored etag', () async {
    final storage = InMemoryStorage();
    final client = _StubClient((_) => sign(_config()));
    final gate = await boot(client, storage: storage);

    await gate.refresh(force: true);
    expect(client.seenHeaders.last['if-none-match'], '"cfg_1"');
  });

  test('304 keeps the cached payload and counts as fresh', () async {
    final storage = InMemoryStorage();
    var first = true;
    final client = _StubClient((_) async {
      if (first) {
        first = false;
        return sign(_config(killActive: true));
      }
      return http.Response('', 304);
    });

    final gate = await boot(client, storage: storage);
    await gate.refresh(force: true);

    expect(await gate.check(), isA<RsKilled>());
    expect(gate.source, ConfigSource.fresh);
  });

  test('snoozing suppresses the prompt, and the allowance runs out', () async {
    final storage = InMemoryStorage();
    final client = _StubClient((_) => sign(_config()));
    final gate = await boot(client, storage: storage, appVersion: '4.1.0');

    await gate.loadSnooze();
    final soft = await gate.check();
    expect(soft, isA<RsSoftUpdate>());
    expect((soft as RsSoftUpdate).canSnooze, true);

    // Snoozing hides it until the cooldown elapses.
    expect(await gate.snooze(), isA<RsNone>());

    // A second snooze exhausts max_snoozes: the prompt returns after the
    // cooldown but can no longer be dismissed. Simulated by ageing the stamp.
    final raw = jsonDecode((await storage.read('ripstop.snooze.$_key'))!)
        as Map<String, dynamic>;
    raw['last_at'] =
        DateTime.now().subtract(const Duration(hours: 48)).toIso8601String();
    raw['count'] = 2;
    await storage.write('ripstop.snooze.$_key', jsonEncode(raw));

    await gate.loadSnooze();
    final again = await gate.check();
    expect(again, isA<RsSoftUpdate>());
    expect((again as RsSoftUpdate).canSnooze, false);
  });

  test('a new target version resets the snooze allowance', () async {
    final storage = InMemoryStorage();
    final client = _StubClient((_) => sign(_config()));
    final gate = await boot(client, storage: storage, appVersion: '4.1.0');
    await gate.snooze();

    // The panel publishes a newer target: a fresh release is a fresh ask.
    final next = _StubClient((_) => sign(_config(iosTarget: '4.5.0')));
    final after = await boot(next, storage: storage, appVersion: '4.1.0');
    await after.refresh(force: true);
    await after.loadSnooze();

    final decision = await after.check();
    expect(decision, isA<RsSoftUpdate>());
    expect((decision as RsSoftUpdate).canSnooze, true);
  });

  test('every check carries the install id, and it survives restarts', () async {
    final storage = InMemoryStorage();
    final client = _StubClient((_) => sign(_config()));
    final gate = await boot(client, storage: storage);

    final sent = client.seenHeaders.single['x-ripstop-device'];
    expect(sent, gate.installId);
    // 128 bits hex — long enough to never collide, nothing device-derived.
    expect(sent, hasLength(32));

    // A second boot on the same storage is the same install, not a new row.
    final again = await boot(_StubClient((_) => sign(_config())), storage: storage);
    expect(again.installId, gate.installId);

    // A different storage is a reinstall: new id by design.
    final fresh = await boot(_StubClient((_) => sign(_config())));
    expect(fresh.installId, isNot(gate.installId));
  });

  test('userId is absent until set, then sent and persisted', () async {
    final storage = InMemoryStorage();
    final first = _StubClient((_) => sign(_config()));
    final gate = await boot(first, storage: storage);
    expect(first.seenHeaders.single.containsKey('x-ripstop-user'), false);

    gate.userId = 'customer-42';
    await gate.refresh(force: true);
    expect(first.seenHeaders.last['x-ripstop-user'], 'customer-42');

    // Next launch reads it back without the host app setting it again. The
    // cache is still fresh so boot itself makes no request — force one to see
    // what a real check would carry.
    final second = _StubClient((_) => sign(_config()));
    final rebooted = await boot(second, storage: storage);
    expect(rebooted.userId, 'customer-42');
    await rebooted.refresh(force: true);
    expect(second.seenHeaders.last['x-ripstop-user'], 'customer-42');

    // Clearing it stops the header, not just the value.
    rebooted.userId = null;
    await rebooted.refresh(force: true);
    expect(second.seenHeaders.last.containsKey('x-ripstop-user'), false);
  });
}
