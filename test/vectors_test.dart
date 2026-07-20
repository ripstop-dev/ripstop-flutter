/// The conformance suite.
///
/// `test/vectors/vectors.json` is vendored verbatim from `@ripstop/protocol`
/// and is the same file the TypeScript reference implementation runs. It is
/// what makes "the SDKs agree" a fact rather than an intention: if this file
/// and the Dart port disagree about a single comparison, this test goes red.
///
/// Adding a vector is a feature. Changing one is an ADR.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ripstop/src/config.dart';
import 'package:ripstop/src/decision.dart';
import 'package:ripstop/src/evaluate.dart';
import 'package:ripstop/src/version.dart';

Map<String, dynamic> _loadVectors() {
  final file = File('test/vectors/vectors.json');
  return jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
}

/// The `evaluate` section patches the base config at the top level — a plain
/// replacement of whole keys, never a deep merge.
Map<String, dynamic> _applyPatch(
  Map<String, dynamic> base,
  Map<String, dynamic> patch,
) {
  final merged = Map<String, dynamic>.from(base);
  for (final entry in patch.entries) {
    merged[entry.key] = entry.value;
  }
  return merged;
}

void main() {
  final vectors = _loadVectors();

  test('vectors file is the version this SDK was built against', () {
    expect(vectors['version'], 1);
  });

  group('compare', () {
    final cases = vectors['compare'] as List<dynamic>;

    for (final raw in cases) {
      final c = raw as Map<String, dynamic>;
      final a = c['a'] as String;
      final b = c['b'] as String;
      final expected = (c['expect'] as num).toInt();

      test('$a vs $b -> $expected', () {
        expect(compareVersions(a, b), expected);
        // Ordering is antisymmetric; a vector that only passes one way round
        // would hide a sign error.
        expect(compareVersions(b, a), expected == 0 ? 0 : -expected);
      });
    }
  });

  group('evaluate', () {
    final base = vectors['base_config'] as Map<String, dynamic>;
    final cases = vectors['evaluate'] as List<dynamic>;

    for (final raw in cases) {
      final c = raw as Map<String, dynamic>;
      final name = c['name'] as String;
      final patch = c['patch'] as Map<String, dynamic>? ?? const {};
      final context = c['context'] as Map<String, dynamic>;
      final expect_ = c['expect'] as Map<String, dynamic>;

      test(name, () {
        final config = RipstopConfig.fromJson(_applyPatch(base, patch));

        final snoozeJson = context['snooze'] as Map<String, dynamic>?;
        final decision = evaluate(
          config,
          EvaluateContext(
            platform: context['platform'] as String,
            appVersion: context['appVersion'] as String,
            locale: context['locale'] as String? ?? 'en',
            snooze: snoozeJson == null
                ? const SnoozeState.none()
                : SnoozeState(
                    count: (snoozeJson['count'] as num).toInt(),
                    hoursSinceLast:
                        (snoozeJson['hoursSinceLast'] as num?)?.toDouble(),
                  ),
          ),
        );

        expect(_typeOf(decision), expect_['type'],
            reason: 'decision type for "$name"');

        // `expect` is a subset match: a vector asserts the fields it cares
        // about and stays silent about the rest.
        for (final field in expect_.entries) {
          if (field.key == 'type') continue;
          expect(_fieldOf(decision, field.key), field.value,
              reason: '"${field.key}" for "$name"');
        }
      });
    }
  });

  group('config_source', () {
    final cases = vectors['config_source'] as List<dynamic>;

    for (final raw in cases) {
      final c = raw as Map<String, dynamic>;
      final fetch = c['fetch'] as String;
      final hasCache = c['hasCache'] as bool;
      final expected = c['expect'] as String;

      test('$fetch + ${hasCache ? 'cache' : 'no cache'} -> $expected', () {
        final source = resolveConfigSource(
          _outcomeOf(fetch),
          hasCache: hasCache,
        );
        expect(source.name, expected);
      });
    }
  });
}

String _typeOf(RsDecision d) => switch (d) {
      RsKilled() => 'kill',
      RsMaintenance() => 'maintenance',
      RsForceUpdate() => 'force',
      RsSoftUpdate() => 'soft',
      RsNone() => 'none',
    };

Object? _fieldOf(RsDecision d, String field) => switch ((d, field)) {
      (final RsKilled x, 'message') => x.message,
      (final RsMaintenance x, 'title') => x.title,
      (final RsMaintenance x, 'message') => x.message,
      (final RsMaintenance x, 'endsAt') => x.endsAt,
      (final RsMaintenance x, 'showEta') => x.showEta,
      (final RsMaintenance x, 'buttonLabel') => x.buttonLabel,
      (final RsMaintenance x, 'buttonUrl') => x.buttonUrl,
      (final RsForceUpdate x, 'title') => x.title,
      (final RsForceUpdate x, 'body') => x.body,
      (final RsForceUpdate x, 'storeUrl') => x.storeUrl,
      (final RsSoftUpdate x, 'title') => x.title,
      (final RsSoftUpdate x, 'body') => x.body,
      (final RsSoftUpdate x, 'storeUrl') => x.storeUrl,
      (final RsSoftUpdate x, 'canSnooze') => x.canSnooze,
      _ => throw StateError('vector asserts "$field", which ${_typeOf(d)} '
          'decisions do not carry — the port and the protocol disagree'),
    };

FetchOutcome _outcomeOf(String name) => switch (name) {
      'ok' => FetchOutcome.ok,
      'http_error' => FetchOutcome.httpError,
      'timeout' => FetchOutcome.timeout,
      'invalid_signature' => FetchOutcome.invalidSignature,
      _ => throw ArgumentError('unknown fetch outcome "$name"'),
    };
