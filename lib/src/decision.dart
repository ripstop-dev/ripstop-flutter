/// What the SDK concluded about this launch.
///
/// A sealed hierarchy so `switch` over it is exhaustive: adding a case to the
/// protocol becomes a compile error in your app rather than a silent fallthrough
/// that shows nobody anything.
library;

sealed class RsDecision {
  const RsDecision();
}

/// This build is dead. Not dismissible, no way past it.
class RsKilled extends RsDecision {
  const RsKilled({required this.message});

  final String message;
}

/// The service is down on purpose.
class RsMaintenance extends RsDecision {
  const RsMaintenance({
    required this.title,
    required this.message,
    required this.endsAt,
    required this.showEta,
    required this.buttonLabel,
    required this.buttonUrl,
  });

  final String title;
  final String message;

  /// Display only — never compared against the device clock.
  final String? endsAt;
  final bool showEta;
  final String buttonLabel;
  final String? buttonUrl;
}

/// Older than the oldest supported version: blocked.
class RsForceUpdate extends RsDecision {
  const RsForceUpdate({
    required this.title,
    required this.body,
    required this.storeUrl,
  });

  final String title;
  final String body;
  final String storeUrl;
}

/// Between the two versions: nudged, and dismissible while [canSnooze].
class RsSoftUpdate extends RsDecision {
  const RsSoftUpdate({
    required this.title,
    required this.body,
    required this.storeUrl,
    required this.canSnooze,
  });

  final String title;
  final String body;
  final String storeUrl;

  /// False once the snooze allowance is spent: the prompt keeps returning
  /// after each cooldown but can no longer be pushed away.
  final bool canSnooze;
}

/// Carry on. Also what every failure resolves to when there is no cache.
class RsNone extends RsDecision {
  const RsNone();
}
