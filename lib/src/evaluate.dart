/// The decision engine. A direct port of the reference evaluator in
/// `@ripstop/protocol`, and it must stay one — `test/vectors_test.dart` runs
/// the same golden file the TypeScript implementation does, so any drift is a
/// red test rather than a support ticket.
///
/// Order is law: kill → maintenance → force → soft → none, first match wins.
/// Nothing here compares the device's wall clock to a server timestamp;
/// scheduled maintenance is decided on the server (`active` is authoritative)
/// and snooze cooldowns are measured against the device's own snooze stamp.
library;

import 'config.dart';
import 'decision.dart';
import 'version.dart';

const String _fallbackLocale = 'en';

/// How many times this prompt has been snoozed, and how long ago.
class SnoozeState {
  const SnoozeState({required this.count, required this.hoursSinceLast});

  const SnoozeState.none()
      : count = 0,
        hoursSinceLast = null;

  final int count;

  /// Null when never snoozed, or when the stamp is unreadable.
  final double? hoursSinceLast;
}

class EvaluateContext {
  const EvaluateContext({
    required this.platform,
    required this.appVersion,
    this.locale = _fallbackLocale,
    this.snooze = const SnoozeState.none(),
  });

  final String platform;
  final String appVersion;
  final String locale;
  final SnoozeState snooze;
}

String _message(RipstopConfig config, String locale, String key) =>
    config.messages[locale]?[key] ??
    config.messages[_fallbackLocale]?[key] ??
    '';

RsDecision evaluate(RipstopConfig config, EvaluateContext ctx) {
  final locale = ctx.locale;
  final version = parseVersion(ctx.appVersion);

  // 1. Kill.
  final kill = config.kill;
  if (kill.active) {
    final platformMatch =
        kill.platforms.isEmpty || kill.platforms.contains(ctx.platform);

    var rangeMatch = kill.versionRanges.isEmpty;
    if (!rangeMatch && version != null) {
      rangeMatch = kill.versionRanges.any((range) {
        final from = range.from == null ? null : parseVersion(range.from!);
        final to = range.to == null ? null : parseVersion(range.to!);
        if (from != null && compareParsed(version, from) < 0) return false;
        if (to != null && compareParsed(version, to) > 0) return false;
        return true;
      });
    }

    if (platformMatch && rangeMatch) {
      return RsKilled(message: _message(config, locale, kill.messageKey));
    }
  }

  // 2. Maintenance.
  final maintenance = config.maintenance;
  if (maintenance.active) {
    return RsMaintenance(
      title: _message(config, locale, 'maint_title'),
      message: _message(config, locale, maintenance.messageKey),
      endsAt: maintenance.endsAt,
      showEta: maintenance.showEta,
      buttonLabel: _message(config, locale, 'maint_button'),
      buttonUrl: maintenance.buttonUrl,
    );
  }

  // 3–4. Force and soft both need a rule for this platform and a version we
  // can read. Missing either is not an error — it is "no opinion".
  final entry = config.update[ctx.platform];
  if (entry == null || version == null) return const RsNone();

  final min = parseVersion(entry.min);
  final target = parseVersion(entry.target);
  if (min == null || target == null) return const RsNone();

  if (compareParsed(version, min) < 0) {
    return RsForceUpdate(
      title: _message(config, locale, 'force_title'),
      body: _message(config, locale, 'force_body'),
      storeUrl: entry.storeUrl,
    );
  }

  if (compareParsed(version, target) < 0) {
    final snooze = ctx.snooze;
    final suppressed = snooze.count > 0 &&
        snooze.hoursSinceLast != null &&
        snooze.hoursSinceLast! < entry.soft.cooldownHours;
    if (suppressed) return const RsNone();

    return RsSoftUpdate(
      title: _message(config, locale, 'soft_title'),
      body: _message(config, locale, 'soft_body'),
      storeUrl: entry.storeUrl,
      canSnooze: snooze.count < entry.soft.maxSnoozes,
    );
  }

  return const RsNone();
}

/// What a fetch attempt produced.
enum FetchOutcome { ok, httpError, timeout, invalidSignature }

/// Which config may drive a decision afterwards.
enum ConfigSource { fresh, cached, none }

/// The fail-open state machine. Any failure falls back to the last cached
/// *signed* config; with no cache, behave as if there were no rules at all.
///
/// Kill stickiness follows from this and is deliberate: a cached kill stays in
/// force until a fresh, signed config clears it, so turning off the network is
/// not a way out of a kill switch.
ConfigSource resolveConfigSource(FetchOutcome outcome,
    {required bool hasCache}) {
  if (outcome == FetchOutcome.ok) return ConfigSource.fresh;
  return hasCache ? ConfigSource.cached : ConfigSource.none;
}
