# Local DB Encryption — SQLCipher (PASS 2026-09-26)

Every Wallet SQLite file is encrypted at rest with SQLCipher; its key is
protected by Android Keystore. Local encryption only — no cloud change.

## Threat model
Protects extracted app files, copied DB files, adb/file-system extraction that
bypasses OS protection, offline inspection of DB copies. Encrypted: every page
(transactions, notes, categories, funds, savings, obligations, members, future
cloud binding/outbox). Does NOT protect a running, unlocked, compromised app
(the key is in process memory while the DB is open).

**Local encryption ≠ App Lock ≠ cloud E2EE.** App Lock is a UX/access layer; the
Backup Password/BMK protect cloud copies; the P7 session secret authorises cloud
calls. None of them is, or derives, the DB key.

## Library
`package:sqlite3` 3.5.2 build hook with `hooks.user_defines.sqlite3.source:
sqlcipher` → SQLCipher **4.18.0 community** (SQLite 3.53.4), prebuilt binaries
verified against sha256 values shipped in the pinned package (SLSA-attested
GitHub releases). Same library on Android and on the host for tests.
`sqlite3_flutter_libs` (plain SQLite in the APK) removed. `applySqlcipherKey`
refuses to open anything if `PRAGMA cipher_version` is empty (never silently
plaintext). Raw 256-bit key via `PRAGMA key = "x'…'"` (no passphrase KDF).

## Key model
- Per Wallet file: random 256-bit DEK-DB from `SecureRandom` (native).
- Wrapped by a dedicated non-exportable Keystore AES-256-GCM key
  `homewallet_db_wrap_v1` (separate from App Lock / P7 / BMK aliases), entry
  `{v:1, c:iv‖ct}` in native prefs `db_key_secure` (excluded from Android
  backup). AAD `vinhaminh-db-key|v1|<dbFileName>`; the wrapped body also holds
  the walletId (authenticated; bound on first open for new Wallets, set from
  `wallet_meta` for migrated ones; checked on every open).
- Never derived from PIN, Google account, device PIN, Backup Password, walletId.
  Not user-auth bound (the DB must open before App Lock UI).
- Never logged/persisted in plaintext; not in registry, prefs, Firebase.
  The bridge never overwrites (`db_key_exists`) or deletes an entry.
- One key per file ⇒ one Wallet's key cannot open another (tested).

## Plaintext v9 → SQLCipher migration (`WalletDbEncryption.prepare`)
Runs in `main` before anything opens the Wallet (and again, idempotently, in
the Drift `LazyDatabase`):
1. Source opened **read-only**; snapshot = sqlite_master SQL, user_version,
   per-table row count + SHA-256 over every row/column in deterministic order,
   walletId, integrity_check, foreign_key_check. Unhealthy source ⇒ abort.
2. Key: reuse an existing entry (earlier failed attempt) or create one.
3. New temp file `…sqlcipher-migrating`, keyed; `ATTACH 'file:src?mode=ro'` +
   `sqlcipher_export('main','plain')` + user_version copied.
4. Verify temp: not a plaintext header, unreadable without key, keyed snapshot
   identical + healthy.
5. Atomic rename: original → `….pre-sqlcipher`, temp → original name;
   re-verify; delete `.pre-sqlcipher`.
Any failure ⇒ original restored byte-identical and opened as plaintext for this
session (`plaintextMigrationPending`, retried next start). A crash between swap
and cleanup is recovered at next start (finish only if the encrypted file fully
matches the rollback copy, otherwise restore the plaintext original). Tests
inject failures at every stage.

## Key loss / Keystore failure
Encrypted file + missing/unwrappable/wrong key ⇒ `DbRecoveryRequired`:
`DbRecoveryRequiredApp` is shown instead of the app, the file is preserved and
**no new key is generated**. The future recovery path is the P8 encrypted
cloud restore into a new Wallet (not built yet). Without a cloud backup, a lost
Keystore key means the local data is unrecoverable — stated honestly.

## Backups
No app code copies/exports/VACUUMs the DB. Android backup stays disabled. The
only plaintext copies are (a) the transient `.pre-sqlcipher` during migration
(deleted after verification) and (b) the developer-controlled host backup taken
before the PROD migration — exceptional, never app behaviour. Flash storage may
retain deleted plaintext blocks until reused (FBE still applies).

## Limits
- A stolen phone kept offline cannot be remotely erased; its data is protected
  by SQLCipher + Android FBE + App Lock, not by cloud revocation.
- Rooted/compromised device with the app unlocked can read memory.
- Debug-only tools (`Đo hiệu năng DB (debug)`, integrity report) join the debug
  importer on the pre-Play removal list.

## Verification (2026-09-26)
Host: `test/security/sqlcipher_wallet_test.dart` (SQLCipher linked, fresh
encrypted Wallet, lossless migration, 7 injected-failure stages, interrupted
swap recovery, key missing/unavailable/wrong, two-Wallet isolation, App Lock
independence, recovery screen, bridge hygiene). Full suite 1,104 pass / 3 skip.

Pixel DEV: first launch migrated; integrity report (on device, keyed) equals
the host report of the pre-migration plaintext copy table-for-table; pulled
file has no SQLite header/schema text and stock sqlite3 says "file is not a
database". App Lock enable/biometric/change PIN/disable left `db_key_secure`
and the DB byte-identical. Benchmark (debug build, 2,000 tx, median of 5,
plain → SQLCipher): cold open 6 → 6–7 ms; load all tx 17–24 → 12–15 ms; month
page 1–2 → 1–2 ms; add+edit+delete 5–8 → 7–9 ms; `am start -W` ≈3.0 s →
2.2–2.9 s. No meaningful regression.

Pixel PROD: live baseline v9, integrity ok, FK 0, **1,849** transactions,
walletId `3cbd8878…`, SHA-256 `de748015…29e41` (two identical reads); verified
host backup `Documents/ViNhaMinh_backups/2026-09-26/sqlcipher_pre/`. Installed
with `install -r` (no uninstall). After migration: all 9 tables identical
(counts + row digests), 1,849 → 1,849, walletId/v9/integrity/FK unchanged, Home
screen region pixel-identical, pulled copy unreadable, identical after
force-stop/reopen, owner confirmed data after reboot.
