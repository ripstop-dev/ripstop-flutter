/// The payload the edge serves, as Dart objects.
///
/// Parsing is deliberately forgiving in one direction only: a field we do not
/// recognise is ignored (so a newer control plane can add one without breaking
/// old apps), but a field we do recognise and cannot read makes the whole
/// payload invalid, and an invalid payload is never allowed to drive a
/// decision. Between "guess" and "fail open", the SDK always fails open.
library;

class VersionRange {
  const VersionRange({this.from, this.to});

  /// Inclusive lower bound; null means unbounded.
  final String? from;

  /// Inclusive upper bound; null means unbounded.
  final String? to;

  static VersionRange fromJson(Map<String, dynamic> json) => VersionRange(
        from: json['from'] as String?,
        to: json['to'] as String?,
      );
}

class KillSwitch {
  const KillSwitch({
    required this.active,
    required this.platforms,
    required this.versionRanges,
    required this.messageKey,
  });

  final bool active;

  /// Empty means every platform.
  final List<String> platforms;

  /// Empty means every version.
  final List<VersionRange> versionRanges;
  final String messageKey;

  static KillSwitch fromJson(Map<String, dynamic>? json) {
    if (json == null) {
      return const KillSwitch(
        active: false,
        platforms: <String>[],
        versionRanges: <VersionRange>[],
        messageKey: 'kill_default',
      );
    }
    return KillSwitch(
      active: json['active'] as bool? ?? false,
      platforms: (json['platforms'] as List<dynamic>? ?? const <dynamic>[])
          .map((dynamic e) => e as String)
          .toList(growable: false),
      versionRanges: (json['version_ranges'] as List<dynamic>? ??
              const <dynamic>[])
          .map((dynamic e) => VersionRange.fromJson(e as Map<String, dynamic>))
          .toList(growable: false),
      messageKey: json['message_key'] as String? ?? 'kill_default',
    );
  }
}

class Maintenance {
  const Maintenance({
    required this.active,
    required this.startsAt,
    required this.endsAt,
    required this.messageKey,
    required this.showEta,
    required this.buttonUrl,
  });

  /// Server-evaluated at fetch time. The device never compares its own clock
  /// to [startsAt] / [endsAt] — those exist only to be displayed.
  final bool active;
  final String? startsAt;
  final String? endsAt;
  final String messageKey;
  final bool showEta;
  final String? buttonUrl;

  static Maintenance fromJson(Map<String, dynamic>? json) {
    if (json == null) {
      return const Maintenance(
        active: false,
        startsAt: null,
        endsAt: null,
        messageKey: 'maint_default',
        showEta: true,
        buttonUrl: null,
      );
    }
    return Maintenance(
      active: json['active'] as bool? ?? false,
      startsAt: json['starts_at'] as String?,
      endsAt: json['ends_at'] as String?,
      messageKey: json['message_key'] as String? ?? 'maint_default',
      showEta: json['show_eta'] as bool? ?? true,
      buttonUrl: json['button_url'] as String?,
    );
  }
}

class SoftPolicy {
  const SoftPolicy({required this.maxSnoozes, required this.cooldownHours});

  final int maxSnoozes;
  final int cooldownHours;

  static SoftPolicy fromJson(Map<String, dynamic>? json) => SoftPolicy(
        maxSnoozes: (json?['max_snoozes'] as num?)?.toInt() ?? 3,
        cooldownHours: (json?['cooldown_hours'] as num?)?.toInt() ?? 24,
      );
}

class UpdateEntry {
  const UpdateEntry({
    required this.min,
    required this.target,
    required this.storeUrl,
    required this.soft,
    required this.usePlayInAppUpdates,
  });

  /// Below this: blocked, with a wall that cannot be dismissed.
  final String min;

  /// Between [min] and this: nudged, dismissible under [soft].
  final String target;
  final String storeUrl;
  final SoftPolicy soft;
  final bool usePlayInAppUpdates;

  static UpdateEntry? fromJson(Map<String, dynamic>? json) {
    if (json == null) return null;
    final min = json['min'] as String?;
    final target = json['target'] as String?;
    if (min == null || target == null) return null;
    return UpdateEntry(
      min: min,
      target: target,
      storeUrl: json['store_url'] as String? ?? '',
      soft: SoftPolicy.fromJson(json['soft'] as Map<String, dynamic>?),
      usePlayInAppUpdates: json['use_play_in_app_updates'] as bool? ?? false,
    );
  }
}

/// One published, signed configuration.
class RipstopConfig {
  const RipstopConfig({
    required this.v,
    required this.app,
    required this.env,
    required this.publishedAt,
    required this.keyId,
    required this.kill,
    required this.maintenance,
    required this.update,
    required this.values,
    required this.messages,
  });

  final int v;
  final String app;
  final String env;
  final String publishedAt;
  final String keyId;
  final KillSwitch kill;
  final Maintenance maintenance;

  /// Keyed by platform: `ios`, `android`, `web`.
  final Map<String, UpdateEntry> update;

  /// Your own remote-config keys, riding in the same signed payload.
  final Map<String, dynamic> values;

  /// `messages[locale][key]`.
  final Map<String, Map<String, String>> messages;

  static RipstopConfig fromJson(Map<String, dynamic> json) {
    final update = <String, UpdateEntry>{};
    final rawUpdate = json['update'] as Map<String, dynamic>? ?? const {};
    for (final entry in rawUpdate.entries) {
      final parsed = UpdateEntry.fromJson(entry.value as Map<String, dynamic>?);
      if (parsed != null) update[entry.key] = parsed;
    }

    final messages = <String, Map<String, String>>{};
    final rawMessages = json['messages'] as Map<String, dynamic>? ?? const {};
    for (final locale in rawMessages.entries) {
      final strings = locale.value as Map<String, dynamic>? ?? const {};
      messages[locale.key] = <String, String>{
        for (final s in strings.entries)
          if (s.value is String) s.key: s.value as String,
      };
    }

    return RipstopConfig(
      v: (json['v'] as num?)?.toInt() ?? 1,
      app: json['app'] as String? ?? '',
      env: json['env'] as String? ?? 'production',
      publishedAt: json['published_at'] as String? ?? '',
      keyId: json['key_id'] as String? ?? '',
      kill: KillSwitch.fromJson(json['kill'] as Map<String, dynamic>?),
      maintenance:
          Maintenance.fromJson(json['maintenance'] as Map<String, dynamic>?),
      update: update,
      values: json['values'] as Map<String, dynamic>? ?? const {},
      messages: messages,
    );
  }
}
