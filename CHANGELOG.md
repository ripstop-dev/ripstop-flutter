# Changelog

## 0.1.0

First release.

- Force update, soft update, kill switch and maintenance mode, decided by the
  protocol's evaluation order and verified against the golden vectors.
- Remote config values in the same signed payload — no extra request.
- Ed25519 verification of the exact response bytes, with pinned keys and
  `key_id` rotation.
- Signed cache: offline apps keep working, and a cached kill stays in force
  until a fresh signed payload clears it.
- `RipstopShell` prebuilt walls, themeable, or take the decision headless.
- Snooze accounting per target version, with cooldown.
