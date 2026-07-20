/// The shell decides what a user sees at the worst moment of their week, so
/// the rules it follows are worth asserting rather than eyeballing:
/// a force wall replaces the app, a soft prompt does not.
library;

import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:ripstop/ripstop.dart';

class _SignedStub extends http.BaseClient {
  _SignedStub(this.body, this.signature);

  final String body;
  final String signature;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async =>
      http.StreamedResponse(
        Stream<List<int>>.value(utf8.encode(body)),
        200,
        headers: <String, String>{
          'x-ripstop-sig': signature,
          'x-ripstop-key-id': 'k1',
        },
      );
}

Map<String, dynamic> _config({required String min, required String target}) =>
    <String, dynamic>{
      'v': 1,
      'app': 'app_test',
      'env': 'production',
      'published_at': '2026-01-01T00:00:00Z',
      'key_id': 'k1',
      'kill': <String, dynamic>{
        'active': false,
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
          'min': min,
          'target': target,
          'store_url': 'https://store.example/ios',
          'soft': <String, dynamic>{'max_snoozes': 3, 'cooldown_hours': 24},
        },
      },
      'values': <String, dynamic>{},
      'messages': <String, dynamic>{
        'en': <String, dynamic>{
          'force_title': 'Update required',
          'force_body': 'Please update to keep using the app.',
          'soft_title': 'Update available',
          'soft_body': 'A new version is ready.',
        },
      },
    };

Future<Ripstop> _gate({required String min, required String target}) async {
  final keyPair = await Ed25519().newKeyPair();
  final publicKey = await keyPair.extractPublicKey();
  final body = jsonEncode(_config(min: min, target: target));
  final signature = await Ed25519().sign(utf8.encode(body), keyPair: keyPair);

  return Ripstop.init(
    apiKey: 'rs_pub_test',
    appVersion: '4.1.0',
    platform: 'ios',
    signingKeys: <String, String>{'k1': base64Encode(publicKey.bytes)},
    storage: InMemoryStorage(),
    httpClient: _SignedStub(body, base64Encode(signature.bytes)),
  );
}

Widget _app(Ripstop gate) => MaterialApp(
      home: RipstopShell(
        gate: gate,
        theme: RsTheme.dark(),
        child: const Scaffold(body: Center(child: Text('THE APP'))),
      ),
    );

void main() {
  testWidgets('a force decision replaces the app', (WidgetTester tester) async {
    final gate = await _gate(min: '5.0.0', target: '5.1.0');
    await tester.pumpWidget(_app(gate));
    await tester.pumpAndSettle();

    expect(find.text('Update required'), findsOneWidget);
    expect(find.text('THE APP'), findsNothing,
        reason: 'a blocked build must not be reachable behind the wall');
  });

  testWidgets('a soft decision sits over a running app',
      (WidgetTester tester) async {
    final gate = await _gate(min: '4.0.0', target: '4.5.0');
    await tester.pumpWidget(_app(gate));
    await tester.pumpAndSettle();

    expect(find.text('Update available'), findsOneWidget);
    expect(find.text('THE APP'), findsOneWidget,
        reason: 'a nudge is a favour we are asking, not a gate');
    expect(find.text('Later'), findsOneWidget);
  });

  testWidgets('snoozing dismisses the prompt and reveals the app',
      (WidgetTester tester) async {
    final gate = await _gate(min: '4.0.0', target: '4.5.0');
    await tester.pumpWidget(_app(gate));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Later'));
    await tester.pumpAndSettle();

    expect(find.text('Update available'), findsNothing);
    expect(find.text('THE APP'), findsOneWidget);
  });

  testWidgets('no rules means the app is untouched',
      (WidgetTester tester) async {
    final gate = await _gate(min: '1.0.0', target: '2.0.0');
    await tester.pumpWidget(_app(gate));
    await tester.pumpAndSettle();

    expect(find.text('THE APP'), findsOneWidget);
    expect(find.text('Update available'), findsNothing);
  });
}
