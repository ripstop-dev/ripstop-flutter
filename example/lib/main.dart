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

import 'demo_app.dart';

/// Try: 'none', 'soft', 'force', 'kill', 'maintenance', 'offline'.
const String scenario = String.fromEnvironment(
  'SCENARIO',
  defaultValue: 'soft',
);

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
    appVersion: scenario == 'force' ? '3.9.1' : '4.1.0',
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
        // A wall with nothing on it reads as a crash. The mark is small and
        // quiet — enough to say "this screen is on purpose".
        theme: RsTheme.dark().copyWith(logo: const _Mark()),
        child: const DemoApp(),
      ),
    ),
  );
}

// ── a signed stub server, so the example needs no account ────────────────────

/// Northwind's mark: a compass needle, north filled.
///
/// The customer's logo, not ours — but a wall carrying a letter in a rounded
/// grey square looks like a missing asset, and these screenshots are the
/// product's face. Drawn rather than shipped as an image so it stays sharp.
class _Mark extends StatelessWidget {
  const _Mark();

  @override
  Widget build(BuildContext context) => const SizedBox(
    width: 34,
    height: 34,
    child: CustomPaint(painter: _NorthwindPainter()),
  );
}

class _NorthwindPainter extends CustomPainter {
  const _NorthwindPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final centre = Offset(size.width / 2, size.height / 2);
    final r = size.width / 2;

    canvas.drawCircle(
      centre,
      r - 1,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4
        ..color = Colors.white.withValues(alpha: 0.22),
    );

    // The needle: north solid, south hollow — the shape every compass uses to
    // say which way it is pointing.
    final north = Path()
      ..moveTo(centre.dx, centre.dy - r * 0.62)
      ..lineTo(centre.dx + r * 0.26, centre.dy)
      ..lineTo(centre.dx - r * 0.26, centre.dy)
      ..close();
    canvas.drawPath(
      north,
      Paint()..color = Colors.white.withValues(alpha: 0.92),
    );

    final south = Path()
      ..moveTo(centre.dx, centre.dy + r * 0.62)
      ..lineTo(centre.dx + r * 0.26, centre.dy)
      ..lineTo(centre.dx - r * 0.26, centre.dy)
      ..close();
    canvas.drawPath(
      south,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.3
        ..color = Colors.white.withValues(alpha: 0.4),
    );
  }

  @override
  bool shouldRepaint(_NorthwindPainter old) => false;
}

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
      // One honest rule for every scenario: the running version is what
      // changes. 3.9.1 is below the minimum, 4.1.0 sits between the two.
      'min': '4.0.0',
      'target': scenario == 'none' ? '4.0.0' : '4.2.0',
      'store_url': 'https://apps.apple.com/app/id000000',
      'soft': <String, dynamic>{'max_snoozes': 3, 'cooldown_hours': 24},
    },
  },
  'values': <String, dynamic>{'checkout_enabled': true},
  'messages': <String, dynamic>{
    'en': <String, dynamic>{
      'force_title': 'This version can’t reach us any more',
      'force_body':
          'We changed something on our side that 3.9 can’t speak to. '
          'The update takes a few seconds.',
      'soft_title': 'A faster version is ready',
      'soft_body':
          'Fixes the sync bug you hit last week, and starts about twice as '
          'fast.',
      'kill_default': 'We’ve pulled this version',
      'maint_title': 'We’re moving some things around',
      'maint_default':
          'Back shortly. Nothing you’ve saved is affected — this is planned, '
          'and short.',
      'maint_button': 'Check status',
    },
  },
};
