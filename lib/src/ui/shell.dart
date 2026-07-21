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

    final rule = widget.gate.rule;

    return switch (_decision) {
      RsKilled(:final message) => _Wall(
          theme: theme,
          eyebrow: 'Withdrawn',
          eyebrowColor: theme.dangerPip,
          title: message.isEmpty ? 'We’ve pulled this version' : message,
          body: '',
          // No button. There is nothing this user can do, and offering an
          // action that cannot help is worse than saying so plainly.
          footnote: 'Nothing on your device was lost.',
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
          eyebrow: 'Maintenance',
          eyebrowColor: const Color(0xFFF5A524),
          title: title.isEmpty ? 'We’re moving some things around' : title,
          body: message,
          ladder: showEta && _eta(endsAt) != null
              ? _EtaRow(theme: theme, value: _eta(endsAt)!)
              : null,
          actionLabel:
              buttonUrl == null || buttonLabel.isEmpty ? null : buttonLabel,
          onAction: buttonUrl == null ? null : () => _open(buttonUrl),
          outlinedAction: true,
          footnote: 'We’ll let you straight back in when it’s done.',
        ),
      RsForceUpdate(:final title, :final body, :final storeUrl) => _Wall(
          theme: theme,
          eyebrow: 'Update required',
          eyebrowColor: theme.dangerPip,
          title: title.isEmpty ? 'This version can’t reach us any more' : title,
          body: body,
          // The ladder only appears when we actually know the numbers; a
          // half-filled diagram would be worse than none.
          ladder: rule == null
              ? null
              : _VersionLadder(
                  theme: theme,
                  current: widget.gate.appVersion,
                  min: rule.min,
                  target: rule.target,
                ),
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
            // The app recedes rather than disappears: it must stay recognisable
            // (this is a nudge, not a block) while the sheet is clearly the
            // thing being asked. Without this the two competed.
            const Positioned.fill(
              child: IgnorePointer(child: ColoredBox(color: Color(0x8C05050A))),
            ),
            _SoftSheet(
              theme: theme,
              eyebrow:
                  rule == null ? 'Update available' : 'Version ${rule.target}',
              title: title.isEmpty ? 'A faster version is ready' : title,
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
    return '$hh:$mm';
  }
}

/// The weave — Ripstop's own texture, barely there. Drawn rather than shipped
/// as an asset so it stays crisp at every density and costs nothing.
class _Weave extends StatelessWidget {
  const _Weave({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) =>
      CustomPaint(painter: _WeavePainter(color));
}

class _WeavePainter extends CustomPainter {
  const _WeavePainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color.withValues(alpha: 0.03)
      ..strokeWidth = 1;
    const step = 22.0;
    for (double x = 0; x < size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (double y = 0; y < size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(_WeavePainter old) => old.color != color;
}

/// A small caps label with a coloured pip — the one place a wall says what
/// kind of wall it is, without shouting it in the headline.
class _Eyebrow extends StatelessWidget {
  const _Eyebrow(
      {required this.text, required this.color, required this.theme});

  final String text;
  final Color color;
  final RsTheme theme;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Container(
          width: 5,
          height: 5,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 7),
        Text(
          text.toUpperCase(),
          style: TextStyle(
            fontSize: 11,
            letterSpacing: 1.1,
            fontWeight: FontWeight.w500,
            color: theme.muted,
          ),
        ),
      ],
    );
  }
}

/// Where the user stands, as three rungs.
///
/// This is the part of the design worth keeping: a blocked user is being told
/// "no" by software, and the least it can do is show its working — the version
/// they have, the one that unblocks them, the newest one.
class _VersionLadder extends StatelessWidget {
  const _VersionLadder({
    required this.theme,
    required this.current,
    required this.min,
    required this.target,
  });

  final RsTheme theme;
  final String current;
  final String min;
  final String target;

  @override
  Widget build(BuildContext context) {
    final rows = <List<Object>>[
      <Object>[current, 'you', theme.accentPip, true],
      <Object>[min, 'minimum', theme.muted.withValues(alpha: 0.35), false],
      <Object>[target, 'latest', const Color(0xFF3ECF8E), false],
    ];

    return Container(
      margin: const EdgeInsets.only(top: 26),
      padding: const EdgeInsets.only(top: 14),
      decoration: BoxDecoration(
        border:
            Border(top: BorderSide(color: theme.muted.withValues(alpha: 0.14))),
      ),
      child: Column(
        children: rows.map((List<Object> row) {
          final label = row[0] as String;
          final tag = row[1] as String;
          final pip = row[2] as Color;
          final isYou = row[3] as bool;
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              children: <Widget>[
                Container(
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(
                    color: pip,
                    shape: BoxShape.circle,
                    boxShadow: isYou
                        ? <BoxShadow>[
                            BoxShadow(
                                color: pip.withValues(alpha: 0.18),
                                spreadRadius: 4),
                          ]
                        : null,
                  ),
                ),
                const SizedBox(width: 11),
                Text(
                  label,
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 13,
                    fontWeight: isYou ? FontWeight.w600 : FontWeight.w400,
                    color: isYou ? theme.foreground : theme.muted,
                  ),
                ),
                const Spacer(),
                Text(
                  tag,
                  style: TextStyle(
                    fontSize: 11.5,
                    color: isYou
                        ? theme.accentPip
                        : theme.muted.withValues(alpha: 0.7),
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }
}

/// One rung, for the maintenance screen: a label and a time. The same shape as
/// the version ladder, so the two screens feel like siblings.
class _EtaRow extends StatelessWidget {
  const _EtaRow({required this.theme, required this.value});

  final RsTheme theme;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 26),
      padding: const EdgeInsets.only(top: 14),
      decoration: BoxDecoration(
        border:
            Border(top: BorderSide(color: theme.muted.withValues(alpha: 0.14))),
      ),
      child: Row(
        children: <Widget>[
          Container(
            width: 7,
            height: 7,
            decoration: const BoxDecoration(
              color: Color(0xFFF5A524),
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 11),
          Text('Expected back',
              style: TextStyle(fontSize: 13, color: theme.muted)),
          const Spacer(),
          Text(
            value,
            style: TextStyle(
              fontFamily: 'monospace',
              fontSize: 13,
              color: theme.foreground,
            ),
          ),
        ],
      ),
    );
  }
}

class _Wall extends StatelessWidget {
  const _Wall({
    required this.theme,
    required this.eyebrow,
    required this.eyebrowColor,
    required this.title,
    required this.body,
    this.ladder,
    this.footnote,
    this.actionLabel,
    this.onAction,
    this.outlinedAction = false,
  });

  final RsTheme theme;
  final String eyebrow;
  final Color eyebrowColor;
  final String title;
  final String body;
  final Widget? ladder;
  final String? footnote;
  final String? actionLabel;
  final VoidCallback? onAction;
  final bool outlinedAction;

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: Directionality.maybeOf(context) ?? TextDirection.ltr,
      child: Material(
        color: theme.background,
        child: Stack(
          children: <Widget>[
            Positioned.fill(child: _Weave(color: theme.foreground)),
            // Colour arrives as light rather than as a fill: a wash at the top,
            // the way the sign-in panel does it, so the product feels like one
            // product from the outside as well as the inside.
            Positioned(
              top: -120,
              left: -80,
              right: -80,
              height: 460,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: const Alignment(-0.4, -0.6),
                    radius: 1.0,
                    colors: <Color>[
                      eyebrowColor.withValues(alpha: 0.32),
                      Colors.transparent
                    ],
                  ),
                ),
              ),
            ),
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(26, 8, 26, 30),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    const SizedBox(height: 48),
                    if (theme.logo != null)
                      Align(
                          alignment: Alignment.centerLeft, child: theme.logo!),
                    const SizedBox(height: 26),
                    _Eyebrow(text: eyebrow, color: eyebrowColor, theme: theme),
                    const SizedBox(height: 14),
                    Text(
                      title,
                      style: theme.titleStyle ??
                          TextStyle(
                            fontSize: 27,
                            height: 1.14,
                            letterSpacing: -0.6,
                            fontWeight: FontWeight.w600,
                            color: theme.foreground,
                          ),
                    ),
                    if (body.isNotEmpty) ...<Widget>[
                      const SizedBox(height: 12),
                      Text(
                        body,
                        style: theme.bodyStyle ??
                            TextStyle(
                                fontSize: 15, height: 1.55, color: theme.muted),
                      ),
                    ],
                    if (ladder != null) ladder!,
                    const Spacer(),
                    if (actionLabel != null && onAction != null)
                      _Action(
                        theme: theme,
                        label: actionLabel!,
                        onPressed: onAction!,
                        outlined: outlinedAction,
                      ),
                    if (footnote != null) ...<Widget>[
                      const SizedBox(height: 14),
                      Text(
                        footnote!,
                        textAlign: actionLabel == null
                            ? TextAlign.left
                            : TextAlign.center,
                        style: TextStyle(
                          fontSize: 12,
                          height: 1.6,
                          color: theme.muted.withValues(alpha: 0.7),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SoftSheet extends StatelessWidget {
  const _SoftSheet({
    required this.theme,
    required this.eyebrow,
    required this.title,
    required this.body,
    required this.canSnooze,
    required this.onSnooze,
    this.onUpdate,
  });

  final RsTheme theme;
  final String eyebrow;
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
            borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
            border: Border(
                top: BorderSide(color: theme.muted.withValues(alpha: 0.14))),
            boxShadow: <BoxShadow>[
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.55),
                blurRadius: 44,
                offset: const Offset(0, -14),
              ),
            ],
          ),
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(22, 12, 22, 22),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Center(
                    child: Container(
                      width: 34,
                      height: 4,
                      decoration: BoxDecoration(
                        color: theme.muted.withValues(alpha: 0.28),
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  _Eyebrow(
                      text: eyebrow,
                      color: const Color(0xFF3ECF8E),
                      theme: theme),
                  const SizedBox(height: 10),
                  Text(
                    title,
                    style: theme.titleStyle ??
                        TextStyle(
                          fontSize: 21,
                          height: 1.2,
                          letterSpacing: -0.4,
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
                              fontSize: 14, height: 1.5, color: theme.muted),
                    ),
                  ],
                  const SizedBox(height: 20),
                  if (onUpdate != null)
                    _Action(
                        theme: theme, label: 'Update', onPressed: onUpdate!),
                  if (canSnooze) ...<Widget>[
                    const SizedBox(height: 4),
                    TextButton(
                      onPressed: () => onSnooze(),
                      child: Text(
                        'Not now',
                        style: TextStyle(color: theme.muted, fontSize: 14),
                      ),
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
  const _Action({
    required this.theme,
    required this.label,
    required this.onPressed,
    this.outlined = false,
  });

  final RsTheme theme;
  final String label;
  final VoidCallback onPressed;
  final bool outlined;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 52,
      child: outlined
          ? OutlinedButton(
              onPressed: onPressed,
              style: OutlinedButton.styleFrom(
                foregroundColor: theme.foreground,
                side: BorderSide(color: theme.muted.withValues(alpha: 0.24)),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(theme.buttonRadius),
                ),
              ),
              child: Text(label,
                  style: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w600)),
            )
          : FilledButton(
              onPressed: onPressed,
              style: FilledButton.styleFrom(
                backgroundColor: theme.accent,
                foregroundColor: theme.onAccent,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(theme.buttonRadius),
                ),
              ),
              child: Text(label,
                  style: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w600)),
            ),
    );
  }
}
