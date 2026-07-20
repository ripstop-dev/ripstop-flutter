/// Ed25519 verification of the exact bytes the server signed.
///
/// The signature covers the **raw response body**, byte for byte, and never a
/// re-serialization of it (ADR-015). So this deliberately verifies before
/// anything is parsed: `jsonDecode` followed by `jsonEncode` would produce a
/// different byte string for the same document — different key order, different
/// number formatting — and the signature would fail for a payload that was
/// perfectly genuine. Verify the bytes, then parse them.
///
/// The public key is pinned in the app. `keyId` selects between pinned keys so
/// the server can rotate without every install having to update first.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

/// Ripstop's production signing keys, by `key_id`.
///
/// Pinned rather than fetched: a key you download is a key an attacker can
/// swap, and the entire point of signing is that a compromised CDN cannot tell
/// your users to install something.
const Map<String, String> productionKeys = <String, String>{
  // Populated per environment; `Ripstop.init(signingKeys: …)` overrides this
  // wholesale for self-hosted deployments and for the test suite.
};

class SignatureVerifier {
  SignatureVerifier(this.keys);

  /// base64 public key by `key_id`.
  final Map<String, String> keys;

  final Ed25519 _ed25519 = Ed25519();

  /// True when [signature] is a genuine signature over [body] by the key named
  /// in [keyId]. Every failure — unknown key, malformed base64, wrong length,
  /// bad signature — is a plain `false`. Callers then fall back to cache.
  Future<bool> verify({
    required String body,
    required String signature,
    required String keyId,
  }) async {
    final encoded = keys[keyId];
    if (encoded == null) return false;

    try {
      final publicKeyBytes = base64Decode(encoded);
      if (publicKeyBytes.length != 32) return false;

      final signatureBytes = base64Decode(signature);
      if (signatureBytes.length != 64) return false;

      return await _ed25519.verify(
        Uint8List.fromList(utf8.encode(body)),
        signature: Signature(
          signatureBytes,
          publicKey: SimplePublicKey(publicKeyBytes, type: KeyPairType.ed25519),
        ),
      );
    } catch (_) {
      // Malformed input is an invalid signature, not a crash. A config read
      // must never be able to take the host app down.
      return false;
    }
  }
}
