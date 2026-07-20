# ripstop

**Force update, kill switch, maintenance mode and remote config for Flutter.**
Decided at the edge, signed, verified on device, and safe when everything is on fire.

[![pub package](https://img.shields.io/pub/v/ripstop.svg)](https://pub.dev/packages/ripstop)
[![CI](https://github.com/ripstop-dev/ripstop-flutter/actions/workflows/ci.yaml/badge.svg)](https://github.com/ripstop-dev/ripstop-flutter/actions/workflows/ci.yaml)
[![license](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

Six months after you ship, a backend change breaks every install older than 3.3.0.
You open the panel, set the oldest version you still support, and within seconds
those installs show a wall telling them to update. That moment is the product.

## Install

```yaml
dependencies:
  ripstop: ^0.1.0
```

## Quickstart

```dart
import 'package:ripstop/ripstop.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final ripstop = await Ripstop.init(
    apiKey: 'rs_pub_your_key',
    appVersion: '4.1.0', // from package_info_plus, or your build config
  );

  runApp(RipstopShell(gate: ripstop, child: const MyApp()));
}
```

That's the whole integration. `RipstopShell` shows your app until a decision says
otherwise, then renders the right wall.

## Or drive it yourself

```dart
switch (await ripstop.check()) {
  case RsForceUpdate(:final title, :final body, :final storeUrl):
    // Blocked. Not dismissible.
  case RsSoftUpdate(:final title, :final canSnooze):
    // A nudge. `ripstop.snooze()` records it and re-evaluates.
  case RsKilled(:final message):
    // This build is dead.
  case RsMaintenance(:final message, :final endsAt):
    // You are down on purpose.
  case RsNone():
    // Carry on.
}
```

The switch is exhaustive: if the protocol ever grows a decision, your app stops
compiling instead of silently showing nobody anything.

## Remote config

Values ride in the same signed payload as the rules, so reading one costs no
extra request:

```dart
final enabled = ripstop.values['checkout_enabled'] as bool? ?? true;
```

## What it does when things break

This is the part worth reading, because a config service that can lock users out
of their own app is worse than no config service.

| Situation | What happens |
| --- | --- |
| No network | The last **signed** payload drives the decision |
| No network, no cache | `RsNone` — your app runs, unrestricted |
| Server returns 500 | Cache, then `RsNone` |
| Signature doesn't verify | Treated as a failure. A forged payload can never kill your app |
| Cache file edited on device | Re-verified on read, so it grants nothing |
| Kill switch on, then network lost | The kill **stays**, until a fresh signed payload clears it |

Two consequences of that table are deliberate. Turning off aeroplane mode is not
a way out of a kill switch. And a compromised CDN cannot show your users
anything, because it does not have the signing key.

## Everything else

| | |
| --- | --- |
| `minFetchInterval` | How long a payload is fresh enough to skip the network. Default 6 hours |
| `timeout` | Fetch budget. Default 5 seconds — after that, cache |
| `storage` | Swap `SharedPreferencesStorage` for your own, or `InMemoryStorage` |
| `locale` | Which language the wall copy resolves to; falls back to `en` per key |
| `signingKeys` | Override the pinned keys, for self-hosted deployments |
| `onOpenUrl` | How to open the store. Wire `url_launcher` here; the SDK doesn't depend on it |

## Conformance

Every Ripstop SDK runs the same `vectors.json` — version ordering, evaluation
order, snooze accounting, the fail-open state machine. `flutter test` runs it
here. If this package and the TypeScript reference implementation ever disagree
about a single comparison, CI goes red.

Full docs: **[ripstop.dev/docs/flutter](https://ripstop.dev/docs/flutter)**

## License

MIT
