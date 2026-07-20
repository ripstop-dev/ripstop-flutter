/// A working example you can point at anything.
///
/// It boots against a signed local stub rather than the real service, so you
/// can see all four walls without owning an account — change [scenario] and
/// hot-restart. Swap `endpoint`, `apiKey` and drop `signingKeys`/`httpClient`
/// and the same code is a production integration.
library;

import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:ripstop/ripstop.dart';

/// Try: 'none', 'soft', 'force', 'kill', 'maintenance', 'offline'.
const String scenario = 'soft';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // ── the only lines that matter in a real app ───────────────────────────────
  //
  //   final ripstop = await Ripstop.init(
  //     apiKey: 'rs_pub_your_key',
  //     appVersion: '4.1.0',
  //   );
  //
  // Everything below fakes a signed server so the demo runs with no account.
  final stub = await _StubServer.create(scenario);

  final ripstop = await Ripstop.init(
    apiKey: 'rs_pub_demo',
    appVersion: '4.1.0',
    platform: 'ios',
    signingKeys: stub.keys,
    storage: InMemoryStorage(),
    httpClient: stub.client,
  );

  runApp(
    MaterialApp(
      title: 'Ripstop example',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(useMaterial3: true),
      home: RipstopShell(
        gate: ripstop,
        theme: RsTheme.dark(),
        child: DemoHome(gate: ripstop),
      ),
    ),
  );
}

class DemoHome extends StatelessWidget {
  const DemoHome({super.key, required this.gate});

  final Ripstop gate;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Your app')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const Text(
                'This is your app, running normally.',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 10),
              Text(
                'Scenario: $scenario · config source: ${gate.source.name}',
                style: const TextStyle(fontSize: 13, color: Colors.white60),
              ),
              const SizedBox(height: 24),
              // Remote config from the same signed payload — no second request.
              Text(
                'checkout_enabled = ${gate.values['checkout_enabled'] ?? '—'}',
                style: const TextStyle(fontSize: 13, color: Colors.white60),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── a signed stub server, so the example needs no account ────────────────────

class _StubServer {
  _StubServer(this.client, this.keys);

  final http.Client client;
  final Map<String, String> keys;

  static Future<_StubServer> create(String scenario) async {
    final keyPair = await Ed25519().newKeyPair();
    final publicKey = await keyPair.extractPublicKey();

    final body = jsonEncode(_configFor(scenario));
    final signature = await Ed25519().sign(utf8.encode(body), keyPair: keyPair);

    return _StubServer(
      _StubClient(
        body,
        base64Encode(signature.bytes),
        offline: scenario == 'offline',
      ),
      <String, String>{'k1': base64Encode(publicKey.bytes)},
    );
  }
}

class _StubClient extends http.BaseClient {
  _StubClient(this.body, this.signature, {required this.offline});

  final String body;
  final String signature;
  final bool offline;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    // 'offline' shows the fail-open path: with no cache this resolves to
    // RsNone and the app simply runs.
    if (offline) throw Exception('network unavailable');
    return http.StreamedResponse(
      Stream<List<int>>.value(utf8.encode(body)),
      200,
      headers: <String, String>{
        'x-ripstop-sig': signature,
        'x-ripstop-key-id': 'k1',
        'etag': '"cfg_demo"',
      },
    );
  }
}

Map<String, dynamic> _configFor(String scenario) => <String, dynamic>{
  'v': 1,
  'app': 'app_demo',
  'env': 'production',
  'published_at': '2026-01-01T00:00:00Z',
  'key_id': 'k1',
  'kill': <String, dynamic>{
    'active': scenario == 'kill',
    'platforms': <String>[],
    'version_ranges': <dynamic>[],
    'message_key': 'kill_default',
  },
  'maintenance': <String, dynamic>{
    'active': scenario == 'maintenance',
    'starts_at': null,
    'ends_at': '2026-01-01T12:00:00Z',
    'message_key': 'maint_default',
    'show_eta': true,
    'button_url': 'https://status.example.com',
  },
  'update': <String, dynamic>{
    'ios': <String, dynamic>{
      // 'force' puts the running 4.1.0 below min; 'soft' puts it between.
      'min': scenario == 'force' ? '5.0.0' : '4.0.0',
      'target': scenario == 'none' ? '4.0.0' : '4.2.0',
      'store_url': 'https://apps.apple.com/app/id000000',
      'soft': <String, dynamic>{'max_snoozes': 3, 'cooldown_hours': 24},
    },
  },
  'values': <String, dynamic>{'checkout_enabled': true},
  'messages': <String, dynamic>{
    'en': <String, dynamic>{
      'force_title': 'Update required',
      'force_body':
          'This version can no longer talk to our servers. '
          'Update to keep using the app.',
      'soft_title': 'A new version is ready',
      'soft_body': 'It is faster, and fixes the bug you hit last week.',
      'kill_default': 'This version has been withdrawn.',
      'maint_title': 'Back shortly',
      'maint_default': 'We are doing some maintenance. Nothing is lost.',
      'maint_button': 'Check status',
    },
  },
};
