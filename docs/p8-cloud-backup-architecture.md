# P8 — Zero-knowledge Cloud Backup Architecture (approved 2026-09-26)

Status: **crypto + envelope + backend interface implemented, deployed to DEV and
Pixel-accepted with DEV fixture data (2026-09-26)**.
Full backup/restore engine, Wallet claim and real-data upload: **NOT started**.
Replaces the earlier (chat-only) P8 audit model of per-entity docs with a
plaintext `d:{…}` body. Source of truth for P8 cloud data shape.

## 1. Principles (locked)
- UI reads local SQLite only. Cloud = backup/sync transport. No Summary/Day/Month
  Firestore queries. Incremental, revision/cursor based; one change ≠ whole Wallet.
- Financial content is encrypted on the client. Firebase/Admin/Functions never
  hold a key that decrypts it (not in env vars, Firestore, config, service
  account, repo). Functions validate structure/authorization only.
- Firestore Rules stay deny-all; all transport goes through callable Functions
  behind the P7/P7.1 session gate (same transaction as the write).
- **SQLCipher gate:** until local DB encryption passes, only synthetic DEV
  fixture wallets may be uploaded (`BackupGate`, server `fixture:true` + DEV-only
  project guard). There is no code path that uploads the real local Wallet.
  E2EE backup is NOT a substitute for local DB encryption.

## 2. Key hierarchy (cryptoVersion 1)
| Key | Source | Only used for |
|---|---|---|
| BMK (256-bit) | CSPRNG | root only; never encrypts directly |
| DEK | HKDF-SHA256(BMK, `vinhaminh-wallet-data-v1`) | AES-256-GCM of envelopes |
| IDK | HKDF-SHA256(BMK, `vinhaminh-wallet-id-v1`) | HMAC opaque entity ids |
| Password root | Argon2id(UTF-8(NFC(password)), 16B salt, m=64 MiB, t=3, p=4, v=0x13) | input to HKDF only |
| Password KEK | HKDF(root, `vinhaminh-backup-password-kek-v1`) | wrap/unwrap BMK |
| Password takeover credential | HKDF(root, `vinhaminh-device-takeover-password-v1`) | P7.1 lost-device proof |
| Recovery KEK | HKDF(RecoverySecret, 32B salt, `vinhaminh-backup-recovery-v1`) | wrap/unwrap BMK |
| Recovery takeover credential | HKDF(RecoverySecret, salt, `vinhaminh-device-takeover-v1`) | P7.1 lost-device proof |

- Wrap = AES-256-GCM, fresh nonce, AAD `vinhaminh-bmk-wrap|v1|walletId|slot`.
- KDF params are stored per slot and versioned; the client refuses downgraded
  params (< 19 MiB, t < 2) served by a malicious backend. Host timing: ~0.3 s.
- Server stores per wallet `accounts/{uid}/backupKeyrings/{walletId}`:
  `cryptoVersion, rev, password{salt,kdf,nonce,wrapped}, recovery{…},
  passwordProofHash, recoveryProofHash` (SHA-256 of the takeover credentials).
  Never: password, Recovery Key, BMK, KEKs, DEK/IDK, plaintext.
- A takeover verifier cannot yield the Recovery Secret, a KEK, BMK or DEK
  (HKDF one-way + label separation; the Recovery Key is 256-bit).

## 3. Backup Password / Recovery Key UX
- Backup Password ≠ Google auth ≠ App Lock PIN ≠ phone PIN; ≥ 10 characters; never
  sent to the server; not asked on app open.
- Enable: password → BMK → Recovery Key → wrap BMK twice → upload keyring →
  store BMK locally under Android Keystore → show Recovery Key ONCE with a
  mandatory "I saved it" checkbox (dialog cannot be dismissed before).
- Recovery Key: 256 random bits, `HW1-` + 13 groups Crockford base32 + 1 group
  20-bit SHA-256 checksum (typos detected before any unwrap). Never logged,
  stored or uploaded.
- Change password: old password (optional on a trusted device holding the BMK)
  → re-wrap the SAME BMK → `putBackupKeyring(mode: rewrapPassword, expectedRev)`.
  Recovery slot and every envelope untouched (tested: only keyring calls).
- Forgot password: (A) trusted device with BMK → set new password after step-up;
  (B) no trusted device → Recovery Key unwraps BMK; (C) no trusted device + no
  password + no Recovery Key → **backup is unrecoverable. No admin reset exists.**
- Password pre-processing = Unicode **NFC only** (no trim, no case folding, no
  NFKC), versioned as `kdf.norm: 'NFC'` (server requires it; client refuses a
  slot without it). Composed/decomposed Vietnamese input derives the same key;
  case and whitespace stay significant (tests). The UI never trims passwords.
- The password takeover credential is ONLY HKDF(Argon2id root) — never a fast
  hash of the raw password. The Recovery Key uses HKDF directly (256-bit random).

## 4. BMK at rest on device
`BackupKeyBridge.kt`: non-exportable Keystore AES-256-GCM key
`homewallet_backup_bmk_v1` (separate from App Lock and P7 session keys), AAD
`uid|walletId`, ciphertext in native prefs `backup_key_secure` (excluded from
Android backup by the P3 rules). No user-auth requirement on the key so
incremental backup can run unattended; App Lock is the interactive gate. The
BMK is in Dart memory while used (no guaranteed zeroization in Dart).
DEVICE_REVOKED / RECOVERY_REQUIRED from the server ⇒ client wipes the P7
credential and this BMK copy.

## 5. Encrypted envelope (generic object, payload schema 1)
Visible: `{v:1, id, rev, n, c, aad:1}` + server `serverRev`.
- `id` = base64url(HMAC-SHA256(IDK, kind‖0x00‖localId)) — kind and local ids
  (e.g. legacy `vo`/`chong`, category slugs) are not visible.
- `c` = AES-256-GCM(DEK, nonce `n` fresh random 96-bit generated INSIDE `seal`
  — the API has no nonce parameter) of `{kind, localId, rev, body}` + 16B tag.
- AAD = `vinhaminh-env|v1|s1|walletId|id` — stable context only. Moving
  ciphertext to another wallet/entity fails authentication. `rev` is allocated
  by the client, sealed inside the plaintext and compared with the envelope on
  open (detects replay of an older revision under a new rev).
- Tombstones: expressed inside the ciphertext (no visible `deleted` flag yet);
  a visible flag is added only if compaction genuinely needs it.

## 6. Backend interface (Functions, DEV only)
| Callable | Gate | Does |
|---|---|---|
| `putBackupKeyring` create | session | create keyring once (KEYRING_EXISTS) |
| `putBackupKeyring` rewrapPassword | session + recent sign-in (+ old proof if given) | CAS on `rev` |
| `getBackupKeyring` | session OR recent sign-in | wrapped slots only (no hashes) |
| `listBackupWallets` | session OR recent sign-in | opaque wallet ids |
| `putEncryptedBatch` | session + owner + keyring | ≤100 envelopes, shape/size checks, CAS `baseHeadRev` (HEAD_MOVED), per-entity rev (STALE_REV), idempotent `batchId` receipt; first write requires `fixture:true` |
| `getEncryptedChanges` | session + owner | envelopes with `serverRev > sinceRev` (≤200) |

Firestore: `wallets/{walletId}` {ownerAccountId, cryptoVersion, fixture, headRev,
updatedAt}; `wallets/{walletId}/entities/{id}` envelope + serverRev;
`wallets/{walletId}/batches/{batchId}` {headRev, count, at}.

## 7. What Firebase Admin can / cannot see
Can: account ↔ wallet relationship, keyring existence + KDF params + wrapped
blobs, number of encrypted objects, ciphertext sizes, revisions, batch counts,
timestamps, request timing, session/takeover metadata (installation UUIDs,
generation, epoch, revoked list, takeover codes), auth identity (uid, email via
Firebase Auth). Offline brute force of a weak Backup Password against the
wrapped slot/verifier is possible for someone holding the keyring (Argon2id
64 MiB cost is the defence).
Cannot: amounts, notes, category/fund/savings/member/counterparty names,
entity kinds, local ids, Backup Password, Recovery Key, BMK/KEKs/DEK.

## 8. Limitations (honest)
- Metadata above remains visible; auth/session metadata is not E2EE.
- The client app is inside the trust boundary: a malicious app update could
  exfiltrate keys. No admin recovery if password + Recovery Key + all trusted
  devices are lost.
- Remote takeover cannot erase data on a stolen device that stays offline;
  local data protection = App Lock + Android security + SQLCipher (required
  before any real-data cloud rollout).
- Server cannot enforce financial invariants on ciphertext (e.g. non-negative
  pools); the client engine remains authoritative. Family (two writers) needs a
  separate design before P10.

## 8b. DEV deployment + Pixel acceptance (2026-09-26)
Deployed `functions:p7-session,firestore:rules` to `vi-nha-minh-55c60` only.
Pixel DEV (`.dev`, owner present for step-up/typing): Backup Password with
Vietnamese characters; Recovery Key shown once (owner-confirmed, not captured);
fixture encrypt → upload → download/decrypt 3/3; force-stop/reopen: P7
credential + BMK survive via Keystore, decrypt 3/3 again. Firestore read back
(owner admin token, read-only): wallet/entities/batches/keyring contain only
`{v,id,rev,n,c,aad,serverRev}` + wrapped slots (`norm:'NFC'`); none of the
fixture amounts, notes, names, local ids or entity kinds present. Password
change: keyring rev 1→2, recovery slot identical, all 3 entity `updateTime`
unchanged (no re-encryption). Lost-device recovery restored the BMK on the new
installation from the Backup Password and decrypted 3/3.
Found + fixed on device: secret dialogs disposed their TextEditingController
while the route was still animating out (red debug screen); dialogs now own
their controllers (regression tests `test/auth/secret_dialog_lifecycle_test.dart`).

## 8c. P8.1 — local sync foundation (schema v10, 2026-09-26)
Local only; nothing uploaded, PROD not claimed, BackupGate still closed.
- `cloud_binding` (singleton, absent = NONE; NONE → CLAIMING → ACTIVE only via
  `CloudBindingStore`, explicit `selfMemberId`, walletId from `wallet_meta`).
- `sync_outbox` filled by SQLite triggers on every Wallet-data table
  (`syncCapturedTables`: transaction, category, status, fund, savingsAssetType,
  counterparty, obligation, financialMember, walletSetting). Only while ACTIVE
  and not inside `withoutSyncCapture`. Rows = `(seq, kind, localId,
  upsert|delete)`; no content. Coalesced per entity, delete = tombstone intent,
  ack by exact `seq`. Excluded: `wallet_meta`, `cloud_binding`, `sync_outbox`,
  `sync_state` (coverage test).
- `sync_state` (singleton: suppression flag, server head rev, push/pull times).
- `wallet_settings` (key/value Wallet data): `primary_fund_id` moved here from
  SharedPreferences (old key = read fallback + one-time migration).
- `SeedProfile.none`: absolutely empty (no wallet_meta/members/categories/funds/
  savings) and SQLCipher-encrypted from creation — target for restore.

## 9. Remaining before full P8
~~SQLCipher phase~~ ✅ → ~~local outbox/binding (P8.1)~~ ✅ → Wallet claim flow
(P8.2) + baseline enqueue + per-entity rev tracking → incremental upload of
real entity kinds → restore into a fresh Wallet (no seed) + reconciliation →
tombstone/idempotency review → Recovery Key regeneration + disable backup +
trusted-device removal endpoints (each with step-up) → PILOT only after owner
approval.
