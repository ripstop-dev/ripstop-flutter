/// Version ordering, exactly as `docs/protocol.md` defines it.
///
/// The grammar is `[0-9]+(\.[0-9]+){0,3}` with an optional `-prerelease` and
/// an optional `+build`. Four segments because Android `versionName` is
/// routinely `4.11.0.2`; missing segments are zero, so `1.2` and `1.2.0` are
/// the same version. Build metadata is ignored entirely.
///
/// A string outside the grammar is not an error — it parses to `null`, and the
/// evaluator treats an unparseable version as "no opinion" and lets the app
/// run. Failing open is the whole safety story: a typo in a version must never
/// lock a user out of their app.
library;

final RegExp _grammar = RegExp(
  r'^(\d+(?:\.\d+){0,3})(?:-([0-9A-Za-z.-]+))?(?:\+[0-9A-Za-z.-]+)?$',
);

/// A version that satisfied the grammar. Compare with [compareParsed].
class ParsedVersion {
  const ParsedVersion(this.segments, this.prerelease);

  final List<int> segments;
  final List<String> prerelease;

  @override
  String toString() {
    final core = segments.join('.');
    return prerelease.isEmpty ? core : '$core-${prerelease.join('.')}';
  }
}

/// Parses [input], or returns null when it is not a version at all.
ParsedVersion? parseVersion(String input) {
  final match = _grammar.firstMatch(input.trim());
  if (match == null) return null;

  final core = match.group(1)!;
  final pre = match.group(2);
  return ParsedVersion(
    core.split('.').map(int.parse).toList(growable: false),
    pre == null ? const <String>[] : pre.split('.'),
  );
}

int _comparePrerelease(List<String> a, List<String> b) {
  // A version carrying a pre-release precedes the same version without one:
  // 3.0.0-rc.1 < 3.0.0.
  if (a.isEmpty && b.isEmpty) return 0;
  if (a.isEmpty) return 1;
  if (b.isEmpty) return -1;

  final length = a.length > b.length ? a.length : b.length;
  for (var i = 0; i < length; i++) {
    // A shorter prefix sorts first: 1.0.0-alpha < 1.0.0-alpha.1.
    if (i >= a.length) return -1;
    if (i >= b.length) return 1;

    final x = a[i];
    final y = b[i];
    final xNumeric = _isNumeric(x);
    final yNumeric = _isNumeric(y);

    if (xNumeric && yNumeric) {
      final nx = int.parse(x);
      final ny = int.parse(y);
      if (nx != ny) return nx < ny ? -1 : 1;
      continue;
    }
    // Numeric identifiers always sort before alphanumeric ones.
    if (xNumeric != yNumeric) return xNumeric ? -1 : 1;
    if (x != y) return x.compareTo(y) < 0 ? -1 : 1;
  }
  return 0;
}

bool _isNumeric(String s) => s.isNotEmpty && int.tryParse(s) != null;

/// -1, 0 or 1 for two already-parsed versions.
int compareParsed(ParsedVersion a, ParsedVersion b) {
  for (var i = 0; i < 4; i++) {
    final x = i < a.segments.length ? a.segments[i] : 0;
    final y = i < b.segments.length ? b.segments[i] : 0;
    if (x != y) return x < y ? -1 : 1;
  }
  return _comparePrerelease(a.prerelease, b.prerelease);
}

/// -1, 0 or 1. Throws [FormatException] when either side is not a version;
/// callers inside the SDK parse first and fail open instead.
int compareVersions(String a, String b) {
  final left = parseVersion(a);
  final right = parseVersion(b);
  if (left == null) throw FormatException('not a version', a);
  if (right == null) throw FormatException('not a version', b);
  return compareParsed(left, right);
}
