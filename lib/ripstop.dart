/// Ripstop — force update, kill switch, maintenance mode and remote config.
///
/// Two ways to use it. Hand the gate to [RipstopShell] and it renders the
/// walls for you:
///
/// ```dart
/// final ripstop = await Ripstop.init(apiKey: 'rs_pub_…', appVersion: '4.1.0');
/// runApp(RipstopShell(gate: ripstop, child: MyApp()));
/// ```
///
/// Or take the decision and do your own thing with it:
///
/// ```dart
/// switch (await ripstop.check()) {
///   case RsForceUpdate(:final storeUrl): …
///   case RsSoftUpdate(:final canSnooze):  …
///   case RsKilled(:final message):        …
///   case RsMaintenance(:final endsAt):    …
///   case RsNone():                        // carry on
/// }
/// ```
library;

export 'src/client.dart' show Ripstop, RsEnv, RsResult;
export 'src/config.dart'
    show
        RipstopConfig,
        UpdateEntry,
        SoftPolicy,
        KillSwitch,
        Maintenance,
        VersionRange;
export 'src/decision.dart'
    show
        RsDecision,
        RsForceUpdate,
        RsSoftUpdate,
        RsKilled,
        RsMaintenance,
        RsNone;
export 'src/evaluate.dart'
    show
        ConfigSource,
        EvaluateContext,
        FetchOutcome,
        SnoozeState,
        evaluate,
        resolveConfigSource;
export 'src/storage.dart'
    show RipstopStorage, InMemoryStorage, SharedPreferencesStorage;
export 'src/ui/shell.dart' show RipstopShell;
export 'src/ui/theme.dart' show RsTheme;
export 'src/version.dart' show compareVersions, parseVersion;
