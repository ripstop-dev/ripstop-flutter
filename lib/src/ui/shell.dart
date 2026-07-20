/// The prebuilt walls, and the widget that decides when to show them.
///
/// [RipstopShell] wraps your app and replaces it when — and only when — a
/// decision says it must. Two properties matter more than anything visual:
///
///  * It renders `child` while the first check is in flight. A config service
///    that adds a spinner to every cold start has made the app slower for
///    everyone in order to catch a rare case; the wall can arrive a moment
///    late.
///  * A soft update never blocks. It is a sheet over a running app, because
///    the user asked to use their app and we are asking for a favour.
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../client.dart';
import '../decision.dart';
import 'theme.dart';

typedef RsLauncher = Future<void> Function(String url);

class RipstopShell extends StatefulWidget {
  const RipstopShell({
    super.key,
    required this.gate,
    required this.child,
    this.theme,
    this.onOpenUrl,
    this.recheckOnResume = true,
  });

  final Ripstop gate;
  final Widget child;

  /// Defaults to following the surrounding [Theme].
  final RsTheme? theme;

  /// How to open the store. Supply `url_launcher` here — the SDK does not
  /// depend on it, so apps that never show a store link don't carry it.
  final RsLauncher? onOpenUrl;

  /// Re-check when the app returns to the foreground. A kill switch flipped
  /// while someone had the app backgrounded should reach them on return, not
  /// on next cold start.
  final bool recheckOnResume;

  @override
  State<RipstopShell> createState() => _RipstopShellState();
}

class _RipstopShellState extends State<RipstopShell>
    with WidgetsBindingObserver {
  RsDecision _decision = const RsNone();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_evaluate());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (widget.recheckOnResume && state == AppLifecycleState.resumed) {
      unawaited(_evaluate());
    }
  }

  Future<void> _evaluate() async {
    await widget.gate.loadSnooze();
    final decision = await widget.gate.check();
    if (mounted) setState(() => _decision = decision);
  }

  Future<void> _snooze() async {
    final decision = await widget.gate.snooze();
    if (mounted) setState(() => _decision = decision);
  }

  Future<void> _open(String url) async {
    final launcher = widget.onOpenUrl;
    if (launcher != null) await launcher(url);
  }

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme ?? RsTheme.of(context);

    return switch (_decision) {
      RsKilled(:final message) => _Wall(
          theme: theme,
          title:
              message.isEmpty ? 'This version is no longer available' : message,
          body: '',
        ),
      RsMaintenance(
        :final title,
        :final message,
        :final endsAt,
        :final showEta,
        :final buttonLabel,
        :final buttonUrl,
      ) =>
        _Wall(
          theme: theme,
          title: title.isEmpty ? 'Back shortly' : title,
          body: message,
          footnote: showEta ? _eta(endsAt) : null,
          actionLabel:
              buttonUrl == null || buttonLabel.isEmpty ? null : buttonLabel,
          onAction: buttonUrl == null ? null : () => _open(buttonUrl),
        ),
      RsForceUpdate(:final title, :final body, :final storeUrl) => _Wall(
          theme: theme,
          title: title.isEmpty ? 'Update required' : title,
          body: body,
          actionLabel: 'Update now',
          onAction: storeUrl.isEmpty ? null : () => _open(storeUrl),
        ),
      // Soft never replaces the app — it sits over it.
      RsSoftUpdate(
        :final title,
        :final body,
        :final storeUrl,
        :final canSnooze
      ) =>
        Stack(
          children: <Widget>[
            widget.child,
            _SoftSheet(
              theme: theme,
              title: title.isEmpty ? 'Update available' : title,
              body: body,
              canSnooze: canSnooze,
              onUpdate: storeUrl.isEmpty ? null : () => _open(storeUrl),
              onSnooze: _snooze,
            ),
          ],
        ),
      RsNone() => widget.child,
    };
  }

  /// The server sends an instant; we show a date, never a countdown, because
  /// a countdown against a device clock is a promise we cannot keep.
  static String? _eta(String? endsAt) {
    if (endsAt == null) return null;
    final parsed = DateTime.tryParse(endsAt);
    if (parsed == null) return null;
    final local = parsed.toLocal();
    final hh = local.hour.toString().padLeft(2, '0');
    final mm = local.minute.toString().padLeft(2, '0');
    return 'Expected back around $hh:$mm';
  }
}

class _Wall extends StatelessWidget {
  const _Wall({
    required this.theme,
    required this.title,
    required this.body,
    this.footnote,
    this.actionLabel,
    this.onAction,
  });

  final RsTheme theme;
  final String title;
  final String body;
  final String? footnote;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: Directionality.maybeOf(context) ?? TextDirection.ltr,
      child: Material(
        color: theme.background,
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 32),
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: theme.maxContentWidth),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    if (theme.logo != null) ...<Widget>[
                      theme.logo!,
                      const SizedBox(height: 24),
                    ],
                    Text(
                      title,
                      textAlign: TextAlign.center,
                      style: theme.titleStyle ??
                          TextStyle(
                            fontSize: 20,
                            height: 1.25,
                            fontWeight: FontWeight.w600,
                            color: theme.foreground,
                          ),
                    ),
                    if (body.isNotEmpty) ...<Widget>[
                      const SizedBox(height: 12),
                      Text(
                        body,
                        textAlign: TextAlign.center,
                        style: theme.bodyStyle ??
                            TextStyle(
                                fontSize: 15, height: 1.5, color: theme.muted),
                      ),
                    ],
                    if (footnote != null) ...<Widget>[
                      const SizedBox(height: 16),
                      Text(
                        footnote!,
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 13, color: theme.muted),
                      ),
                    ],
                    if (actionLabel != null && onAction != null) ...<Widget>[
                      const SizedBox(height: 28),
                      _Action(
                          theme: theme,
                          label: actionLabel!,
                          onPressed: onAction!),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SoftSheet extends StatelessWidget {
  const _SoftSheet({
    required this.theme,
    required this.title,
    required this.body,
    required this.canSnooze,
    required this.onSnooze,
    this.onUpdate,
  });

  final RsTheme theme;
  final String title;
  final String body;
  final bool canSnooze;
  final Future<void> Function() onSnooze;
  final VoidCallback? onUpdate;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.bottomCenter,
      child: Material(
        color: Colors.transparent,
        child: Container(
          width: double.infinity,
          decoration: BoxDecoration(
            color: theme.background,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
            boxShadow: <BoxShadow>[
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.35),
                blurRadius: 32,
                offset: const Offset(0, -8),
              ),
            ],
          ),
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Center(
                    child: Container(
                      width: 36,
                      height: 4,
                      decoration: BoxDecoration(
                        color: theme.muted.withValues(alpha: 0.35),
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  Text(
                    title,
                    style: theme.titleStyle ??
                        TextStyle(
                          fontSize: 17,
                          height: 1.25,
                          fontWeight: FontWeight.w600,
                          color: theme.foreground,
                        ),
                  ),
                  if (body.isNotEmpty) ...<Widget>[
                    const SizedBox(height: 8),
                    Text(
                      body,
                      style: theme.bodyStyle ??
                          TextStyle(
                              fontSize: 14, height: 1.45, color: theme.muted),
                    ),
                  ],
                  const SizedBox(height: 18),
                  if (onUpdate != null)
                    _Action(
                        theme: theme, label: 'Update', onPressed: onUpdate!),
                  if (canSnooze) ...<Widget>[
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: () => onSnooze(),
                      child:
                          Text('Later', style: TextStyle(color: theme.muted)),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Action extends StatelessWidget {
  const _Action(
      {required this.theme, required this.label, required this.onPressed});

  final RsTheme theme;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 48,
      child: FilledButton(
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: theme.accent,
          foregroundColor: theme.onAccent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(theme.buttonRadius),
          ),
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }
}
