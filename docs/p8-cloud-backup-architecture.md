# P8 — Zero-knowledge Cloud Backup Architecture (approved 2026-09-26)

Status: **crypto + envelope + backend interface implemented, deployed to DEV and
Pixel-accepted with DEV fixture data (2026-09-26)**.
Wallet claim (P8.2, DEV): done — ownership metadata only (§8d). Backup/delta/restore engines (P8.3–P8.5): implemented + emulator-proven (§8e); real-data upload: **NOT done** (DEV only).
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
| `claimWallet` (P8.2) | session + recent sign-in for a NEW claim | ownership metadata only; idempotent replay; see §8d |
| `getWalletClaim` (P8.2) | session | `{claimed, ownedByYou, selfMemberId, headRev}` |
| `abandonClaim` (P8.2) | session + recent sign-in + exact claim | only while headRev 0 and no entities/batches |

Firestore: `wallets/{walletId}` {ownerAccountId, cryptoVersion, fixture, headRev,
updatedAt} (pre-claim DEV fixture) or, after P8.2 claim, {kind:'personal',
state:'CLAIMED', ownerAccountId, selfMemberId, memberIds, payloadSchema,
cryptoVersion, environment, claimRequestId, headRev:0, claimedAt};
`wallets/{walletId}/memberships/{uid}` {accountId, role:'OWNER', status:'ACTIVE',
memberId, createdAt}; `accounts/{uid}/walletIndex/personal` {walletId, createdAt}; `wallets/{walletId}/entities/{id}` envelope + serverRev;
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
  pools); the client engine remains authoritative. Family (two writers): see §8g —
  merged overdraws are detected client-side, not prevented server-side.

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
- PROD acceptance (2026-09-26): v9 → v10 in place, 1,849 → 1,849 tx, 9/9 old
  tables identical (count + digest), walletId unchanged, integrity ok, FK 0,
  still SQLCipher; cloud_binding/sync_outbox/sync_state empty (sqlite_sequence
  seq 0 = no outbox row ever written); primary fund migrated (`an_uong`); Home
  pixel-identical. Nothing uploaded.

## 8d. P8.2 — explicit Personal Wallet claim (2026-09-26)
Claim ONLY: no financial entity uploaded, outbox not pushed, no restore, DEV only
(backend allowlist + `WalletClaimService.allowedIn(dev)`; PILOT/PROD have no
cloud session at all). PROD not claimed.

**Locked product rule.** Claim binds CLOUD ownership to an Account. Local access
never depends on Firebase: after claim this installation keeps opening the
SQLCipher Wallet offline / signed out (`WalletRegistryEntry.canOpen`: a
`personal` Wallet is openable in local scope); sign-out stops cloud operations
only; a different signed-in Account gets no cloud authority (server owner
check) and cannot select the Wallet in the registry.

**UX.** Settings → Account card (DEV) → "Sao lưu ví này" (login never claims) →
P7.1 credential must exist (else "kích hoạt thiết bị" first, nothing written) →
"Bạn là ai trong ví này?" (no default; neutral summary = tx count + month range,
no amounts) → confirmation (Account becomes cloud Owner; chosen member is you;
other member unchanged/unlinked; NO financial data uploaded; sign-out does not
hide/delete) → step-up (device credential + Google reauth) → claim.

**Local state machine** (`CloudBindingStore`, DB authoritative):
NONE → CLAIMING (`claimRequestId` = UUID persisted BEFORE the network call) →
ACTIVE. `activate` re-checks in ONE DB transaction: server walletId ==
`wallet_meta`, server selfMemberId == chosen, member still exists; stores the
SERVER's canonical `claimRequestId`; `wallet_meta.kind` local → personal.
Then `wallet_registry.json` is reconciled FROM the DB (`reconcileRegistryFromDb`,
also at every app start) — the registry never binds by itself. Network/session
failure ⇒ stays CLAIMING and the card retries the SAME id on open
(`resume`). Terminal server answers (ALREADY_CLAIMED, ACCOUNT_HAS_WALLET,
SELF_MEMBER_MISMATCH, CLAIM_MISMATCH, WALLET_NOT_CLAIMABLE, ENVIRONMENT_MISMATCH)
prove the server holds nothing of ours ⇒ `release()` back to NONE. Calls are
serialized (double tap = one claim).

**Server `claimWallet`** (one Firestore transaction): P7.1 `authorize`
(stale ⇒ 403, revoked ⇒ DEVICE_REVOKED) → read wallet + account index →
existing wallet: other owner ⇒ ALREADY_CLAIMED; non-claim doc ⇒
WALLET_NOT_CLAIMABLE; different selfMember ⇒ SELF_MEMBER_MISMATCH; different
member set/env ⇒ CLAIM_MISMATCH; otherwise idempotent success returning the
ORIGINAL claim (no write; stale sign-in allowed because nothing new is granted)
→ absent wallet: account already has a Personal Wallet ⇒ ACCOUNT_HAS_WALLET;
recent sign-in required; `create` wallet + owner membership + index (create
fails on races ⇒ transaction retry sees the winner). Request keys are
whitelisted (credential + walletId, selfMemberId, `membersMinimalMetadata`
= `[{memberId}]` ≤ 2, payloadSchema, cryptoVersion 1, environment 'dev',
claimRequestId UUID); any other field ⇒ INVALID_ARGUMENT. `putEncryptedBatch`
refuses a CLAIMED wallet (BACKUP_NOT_ENABLED) until P8.3.

**Abandon.** Owner + current session + recent sign-in + exact
(walletId, selfMemberId, claimRequestId); refused (BACKUP_STARTED) once
headRev > 0 or any entity/batch exists; deletes wallet + membership + index
atomically; retry after commit = `alreadyAbsent`. Client: CLAIMING ⇒ ask
`getWalletClaim` first (ours ⇒ finish claim then abandon it; not ours ⇒ local
release only); success ⇒ `release()` (binding, outbox, sync_state cleared,
kind → local; no financial row touched) + registry reconcile.

**Tests.** Emulator `functions/test/claim.test.js` (6): metadata-only +
idempotency (same id, compatible new id, member order, stale sign-in replay),
conflicts, races (2 Accounts/1 wallet, 1 Account/2 wallets, 3 parallel taps ⇒
exactly one ownership set), P7.1 (non-recent, no session, other account, stale
after takeover, DEVICE_REVOKED after lost-device recovery), abandon rules, Rules
deny direct read/write. App: `test/cloud/wallet_claim_test.dart` (28),
`test/cloud/wallet_claim_controls_test.dart` (2), registry tests.

**DEV live acceptance (Pixel 7a, `vi-nha-minh-55c60`, 2026-09-26) — PASS.**
Deploy: `claimWallet`/`getWalletClaim`/`abandonClaim` created, 13 functions
updated, Rules unchanged. DEV fixture Wallet `dc268fde…` (4 tx, SQLCipher).
Server verdicts from Cloud Run request logs; Firestore read back read-only.
- Signed in, card shows "chưa gắn với tài khoản nào"; `cloud_binding` 0
  (on-device `[db-report]`); no claim docs in Firestore.
- Explicit claim (member Chồng, confirmation, step-up with Google reauth):
  `claimwallet 200` once; local `cloud_binding` 1, `wallet_meta` → personal,
  every financial table digest unchanged, outbox 0; registry
  `kind: personal, boundAccountId = uid`.
- Firestore: exactly `wallets/{id}` (kind, state, owner, selfMemberId,
  memberIds, payloadSchema 10, cryptoVersion 1, env dev, claimRequestId,
  headRev 0, claimedAt) + `memberships/{uid}` OWNER + `walletIndex/personal`;
  only subcollection `memberships`; no amount/note/label/category/fund/savings.
- Stale device (credential ciphertext replay after rotation): `getwalletclaim
  403`; claim from stale credential `claimwallet 403` ⇒ local stays CLAIMING,
  nothing written server-side. Firebase Auth alone (signed in again, no P7.1
  credential): blocked on device, no request sent.
- Retry: CLAIMING DB snapshot → valid session reopen ⇒ same id committed
  (`200`); restore the CLAIMING snapshot again (= crash after server commit) ⇒
  same id replayed `200`, wallet `updateTime == createTime` (no write), still 1
  membership + 1 index.
- Sign-out: `deactivatesession 200`, credential wiped, claim card gone; app
  network blocked (OEM_DENY_3) + force-stop ⇒ Wallet opens, `[db-report]`
  identical digests, binding + registry intact. Sign in again ⇒ cloud ops
  blocked until "Kích hoạt thiết bị này", then server confirms Owner.
- Wrong Account (another Google account on the phone): card says the Wallet
  belongs to another account, no claim/check/abandon actions, no request sent.
- abandonClaim (headRev 0, no entity/batch): `abandonclaim 200`, all 3 docs
  gone, registry back to `local`, DB digests identical to pre-claim.
- App Lock on (test PIN) ⇒ cold start locked, unlock ⇒ same Wallet/claim;
  turned off again. SQLCipher `encrypted`, integrity ok, FK 0 throughout.
- Deployed Rules re-read: deny-all (== repo). PROD package untouched.
- Found + fixed live: "Bạn là ai?" opened before the P7.1 credential check;
  the card now checks the credential first (widget test added).
- Not live (emulator only): DEVICE_REVOKED claim rejection (needs lost-device
  recovery with the DEV Backup Password), two-Account race.
Final DEV state: fixture Wallet claimed by the owner Account (headRev 0).

## 8e. P8.3–P8.5 — encrypted backup, delta sync, restore (2026-09-27, DEV/emulator)
Schema **v11** (additive): `sync_state.backup_state` (NULL/SEEDING/COMPLETE),
`sync_conflicts` (local-only review table, excluded from sync). PROD not migrated.
- **Enable (Owner, claimed wallet):** random BMK → Keystore FIRST → keyring
  (Password + Recovery slots) → `enableBackup` (server `backupState: SEEDING`) →
  one DB tx: `SEEDING` + outbox full snapshot. Crash after keyring creation ⇒ retry
  gets `KEYRING_EXISTS`, the SAME password unwraps the same BMK (no new Recovery Key
  is shown; regenerate-Recovery-Key is backlog). `EntityCodec` (inside ciphertext):
  `{s: schema, c: {column: raw SQLite value}}` / `{s, deleted: true}` + writer `w`;
  sorted keys, locale-free, exact restore; unknown/newer columns rejected.
- **Push:** outbox + current rows read in ONE DB tx; every envelope of a batch gets
  `rev = baseHeadRev + 1` (> any stored rev); `batchId = HMAC(IDK, head‖manifest‖seqs)`
  ⇒ retry after a lost response hits the receipt (no second write); ACK deletes the
  exact seqs only (a newer edit has a new seq and survives). The batch that drains
  the outbox carries an encrypted `manifest` (walletId, created_at, per-kind counts)
  and `checkpoint: true` ⇒ server `checkpointRev`, SEEDING → COMPLETE.
- **Pull:** all pages (server pages end on whole batches: `throughRev`/`more`),
  every envelope authenticated (serverRev == sealed rev), applied in ONE DB tx inside
  `withoutSyncCapture` with deferred FKs; FK violation ⇒ whole pull rolled back
  (`dependency-conflict`). Entity with a pending local change: same content ⇒ ack;
  own older echo ⇒ keep local; other writer ⇒ local copy saved verbatim in
  `sync_conflicts`, server version wins (no silent overwrite).
- **Worker (`SyncWorker`):** start/resume + Drift table updates → debounce →
  `syncNow` (push; pull ONLY on `requestPull()` or HEAD_MOVED ⇒ pull+retry).
  Empty outbox + no pull signal ⇒ **zero network calls** (fixed 2026-09-27:
  the first version pulled on every run, i.e. 1 read per app open). Network errors ⇒ exponential
  backoff (≤15 min); signed out / other Account / stale or revoked device / no BMK
  ⇒ stop quietly, outbox kept. No polling while idle; its own pull writes do not
  retrigger it. Not yet wired to app lifecycle/UI (DEV UI = backlog).
- **Restore (`RestoreEngine`):** P7.1 session → `getWalletClaim` (owned) → keyring →
  unwrap BMK locally (wrong secret fails before any file) → download + authenticate
  all → NEW file with its FINAL random name `wallet_<uuid>.sqlite` and its own new
  DEK-DB (no rename ⇒ Keystore/AAD file binding intact), `SeedProfile.none`,
  marker `.restoring` → one DB tx: wallet_meta, rows, FK check, binding ACTIVE +
  sync_state COMPLETE (written after data ⇒ no outbox) → verify: integrity_check,
  FK, every row re-read == decrypted body, per-kind counts == manifest (manifest
  must be at head unless `allowStaleCheckpoint`), all pools ≥ 0, unique clientTxId,
  outbox 0 → BMK into Keystore → registry register (= activation) → marker removed.
  Any failure ⇒ close + delete file/sidecars/marker; current Wallet never opened.
  Startup `cleanupInterruptedRestores` removes unregistered `wallet_*` leftovers.
  DB-key entries of discarded restore files are kept (the bridge intentionally has
  no key-deletion API); names are random, never reused.
- **Tests:** `test/sync/cloud_backup_test.dart` (11), `sync_worker_test.dart` (3),
  `restore_test.dart` (10, failure injected at download/create/apply/verify/activate
  ⇒ directory byte-identical), `restore_storage_test.dart` (3, real SQLCipher),
  `migration_v10_to_v11_test.dart`; emulator `functions/test/backup.test.js` (5) +
  `test/sync/emulator_e2e_test.dart` (real Functions/Firestore/Auth: backup 16
  envelopes in 1 call, delta 1 call, idle sync 1 read call, Firestore admin dump has
  no amount/note/label/local id/kind/password/Recovery Key, lost-device recovery →
  restore == source, old device DEVICE_REVOKED + BMK wiped).
- **Restore file/key handling (answers the SQLCipher rename question):** there is
  no `.restoring` DATABASE and no rename. The target is created directly under its
  final random name, so its Keystore-wrapped DEK-DB (AAD bound to that file name)
  never needs re-binding; `.restoring` is only an empty marker file. The DB is
  SQLCipher from its first page (`probeDbFile` = encrypted), its key is independent
  of the current Wallet's key, and it is bound to walletId on its first normal open.
  Failed restores delete the file + sidecars + marker; the orphan DB-key entry is
  kept on purpose (the bridge has no key-deletion API — a guarded invariant); a
  random name is never reused so it can open nothing.
- **Cost (emulator E2E fixture, fresh Wallet + 1 fixture tx):** initial backup 16
  entity envelopes + manifest in 1 `putEncryptedBatch` call, ~5.3 KB ciphertext
  stored; one edit = 1 call, 2 envelopes (entity + manifest); idle = 0 calls;
  restore = 8 calls (claim status, keyring, recovery session, 1 page). Firestore per
  batch of N envelopes ≈ reads: session + wallet + membership + keyring + receipt +
  N entities; writes: wallet + N entities + receipt. Nothing pathological.
- **Added gates (2026-09-27):** real-SQLCipher restore suite (failure at each stage ⇒
  current Wallet bytes + key untouched, no `wallet_*` left; wrong password ⇒ no file,
  no key; Recovery Key ⇒ independent key, integrity ok); server receiving a new batch
  mid-download ⇒ consistent restore at the new head; balances recomputed equal;
  emulator log + Firestore scan: 0 hits of any fixture plaintext/password/Recovery Key.
- **Honest limits:** server can replay an OLDER envelope of an entity (authentic,
  older rev) — per-entity rollback detection is backlog; the manifest detects
  dropped/added objects only at a checkpoint. Pull applies other-writer rows without
  re-running pool non-negativity for merged pending local rows (restore does check).

## 8f. P8.3–P8.5 LIVE DEV acceptance (Pixel 7a, 2026-09-27)
DEV fixture Wallet `dc268fde…` only (`com.vinhamimh.vi_nha_minh.dev`); PROD untouched, not migrated, not uploaded.
- **Deploy:** 26 callables + deny-all Rules to `vi-nha-minh-55c60` after emulator 23/23.
- **P8.3:** explicit enable (Backup Password, Recovery Key shown once with mandatory confirm) →
  3 calls (keyring, enableBackup, 1 batch) → COMPLETE, outbox 0, headRev 1, 19 entities, 1 batch.
  Firestore (Console, read-only): wallet doc = ownership metadata only; entities = `{v,id,rev,n,c,aad}`
  + `serverRev` (server enforces exact keys, `functions/index.js` `validEnvelope`); keyring = wrapped
  slots + KDF params + proof hashes only. BMK survived force-stop (next push succeeded).
- **P8.4:** create / edit / delete = 1 call + 1 batch each (count 2 = entity + manifest); delete =
  tombstone inside ciphertext (entity rev 4). Offline (app-only network off): outbox 1 kept across
  force-stop, retries with backoff never reached the server, upload resumed on reconnect. Idle 3 min +
  background/resume + cold start = 0 calls; Cloud Run request log 09:55–10:09 = exactly 4
  `putEncryptedBatch` (create, edit, delete, offline resume).
- **P8.5:** `pm clear` DEV → sign-in → TAKEOVER_REQUIRED → lost-device recovery (password) → restore
  into `wallet_<uuid>.sqlite` (first 16 bytes random = SQLCipher from page 1, own DB key), registry
  bound to the Account, same walletId, 5 tx / 10 categories / 2 members / 1 fund / 1 savings type,
  balances equal, integrity ok, FK 0, force-stop/reopen OK. Done twice (2nd after a deliberate wrong
  password: `BackupKeyException` locally, no `recoverSession`, no file/key/registry change).
  Restore #1 `transaction_rows` digest differed ONLY because the source DB (created at v8) had v9
  `actor_member_id` appended by `ALTER TABLE ADD COLUMN` while a restored DB uses declared order;
  recomputed in the source order the digest is identical (`f5526257…`). Restore #2 vs #1: every table,
  per-column and per-row digest identical. Test `test/sync/restore_row_fidelity_test.dart` pins per-cell
  (typeof + quote) fidelity through real SQLCipher.
- **Session:** sign-out keeps the file + BMK; signed in without P7.1 activation ⇒ Sync now blocked with
  0 network calls; after activation Sync now = 1 call.
- **Fixed during acceptance:** Transactions tab tie-break (createdAt, id) — restored Wallets insert in
  cloud order; stale "nothing uploaded" copy.
- **Recovery Key regeneration (7a6f378, approved 2026-09-27):** `putBackupKeyring` mode
  `rotateRecovery` = current P7.1 session + recent sign-in (+ client device step-up) + CAS
  `expectedRev`; atomically replaces `recovery` slot + `recoveryProofHash` (rev+1); idempotent
  receipt by `rotationId` (same id + same proof ⇒ `{rev}`; same id + other proof ⇒ KEYRING_CHANGED).
  Client first proves the held BMK opens live ciphertext, then wraps the SAME BMK under a new random
  256-bit Recovery Key (independent KEK), retries network errors only, shows the key once. No BMK
  change, no envelope rewrite, password slot untouched; old Recovery Key dead immediately (unwrap
  fails + `recoverSession` rejects its proof). Live: keyring rev 1→2, new nonce/salt/proof hash,
  password slot identical, headRev/batches unchanged, 3 calls. Then `pm clear` #3 → restore with the
  NEW Recovery Key → every table/column/row digest identical, balances equal, integrity ok, FK 0,
  SQLCipher from page 1.
- **F1 fixed (9f49678, rule locked 2026-09-27):** registry keeps a device-local MRU (`active`) of
  explicitly activated Wallets; restore registers + activates in ONE registry write; Firebase
  sign-in/out never changes it; selection = preferred > MRU openable > fallback (bound, bootstrap
  local); never by transaction count. Active non-legacy Wallet with missing file/key ⇒ recovery
  screen (`preflightRegisteredWallet`), never a new DB/key or a silent switch. Live: sign-out and cold
  start while signed out keep the restored Wallet active.
- **Tooling note:** `a7955ab` also carries `dart format` churn in 16 presentation files — verified
  format-only (formatting the parent reproduces them exactly); left as is.
- Failed-restore DB-key cleanup: accepted technical debt (orphan random alias, never reused, opens
  nothing); ordinary code still cannot delete Wallet DB keys.

## 8g. P10 — Family v1 app side + two-account sync (2026-09-27, DEV/emulator)
Family v1 = exactly 1 Owner + at most 1 Member Account; Owner transfer unsupported. Account ≠
FinancialMember: an invite binds an Account to an EXISTING `memberId` the Owner picks explicitly
(no default); Owner/Member are permissions, Vợ/Chồng are people. DEV backend only; PROD untouched.
- **Personal → Family (`promoteToFamily`, "Chia sẻ với gia đình"):** Owner of a CLAIMED Wallet with
  backup on; current P7.1 session + recent sign-in; idempotent. In place: same walletId, same SQLite
  file, same ids/clientTxIds/memberIds, same BMK/keyring/envelopes/headRev. Locally `wallet_meta.kind =
  family` (excluded from sync, no outbox) + registry reconciled from the DB (`kind: family`). The Owner
  membership stays OWNER with its `selfMemberId`.
- **Invite ("Chia sẻ với vợ/chồng"):** Owner picks the FinancialMember (local label, never sent) +
  target email + explicit confirm + step-up ⇒ `createFamilyInvite`: current Owner, P7.1 session, recent
  auth, Family only, member exists and ≠ Owner member, not already bound, ≤ 2 ACTIVE Accounts, not the
  Owner's own email; 256-bit random token returned ONCE (server stores SHA-256 only), 48 h, one pending
  per wallet (new supersedes), cancellable. The Owner hands the token to the invitee (email delivery
  by backend = pending). **Email alone is not authority:** accept needs the token + the invitee's
  VERIFIED email + P7.1 session + recent sign-in; wrong Account / expired / used / cancelled ⇒ the same
  `INVITE_INVALID`. Acceptance is one transaction (race ⇒ exactly one membership).
- **Key sharing (zero-knowledge, `lib/core/crypto/family_key_crypto.dart`):** the accepting
  installation generates an X25519 device key (32-byte seed wrapped by its own non-exportable Keystore
  AES-GCM alias `homewallet_family_device_v1`, AAD uid|installation, `FamilyKeyBridge.kt`) and sends
  only the public key; the server records it with `keyInstallationId` = the accepting P7.1
  installation. Owner wrap = ECIES/HPKE-style: ephemeral X25519 × member key → HKDF-SHA256 (salt epk‖pkR,
  info `vinhaminh-family-bmk-kek-v1|ctx`) → AES-256-GCM(BMK, AAD = ctx), ctx = version | walletId |
  ownerAccountId | recipient uid | recipient memberId | recipient installation | recipient public key.
  Server stores `{v, epk, n, c}` only. **Recipient binding:** the Owner wraps only after both screens
  show the same 12-digit fingerprint of ctx (the Member computes it from its OWN key); `putMemberKey`
  pins SHA-256(public key) + installation (`PUBLIC_KEY_CHANGED` if swapped); `getMemberKey` serves the
  package only to the ACTIVE Member on that exact installation (`KEY_DEVICE_MISMATCH`). A new Member
  installation (P7.1 takeover) registers a new key (`registerMemberDeviceKey`, recent auth) and needs a
  new Owner verification + wrap. **Key confirmation:** "Mã ví" = HKDF commitment of the BMK, shown on
  both devices; any BMK not from the Owner also fails to open the existing envelopes during restore.
  Low-order (all-zero) shared secrets are rejected; accept retries reuse the SAME device key (a
  rejected re-accept can never orphan the registered key — bug found by the emulator E2E, fixed).
- **Member join:** `getMyFamily` → `getMemberKey` → unwrap locally → `restoreAsFamilyMember` (P8.5 engine:
  new random-named SQLCipher file + own DB key, full verification, then registry register+activate in
  one write with `kind: family`, `familyMember: true`); `cloud_binding` = Member Account + the memberId
  the Owner assigned. BMK stored under the Member's own Keystore slot. No plaintext cloud payload, no
  direct Firestore access (Rules deny-all).
- **What Firebase admin can / cannot see (Family additions):** CAN: memberships (uid, role, status,
  opaque memberId, X25519 public key, installation id, FCM token), invite docs (walletId, memberId,
  invitee email, status, expiry — never the token), wrapped key package `{v,epk,n,c}`, per-batch writer
  uid, batch timing. CANNOT: BMK/DEK/IDK, member labels, amounts, notes, categories, entity kinds —
  no server-side key opens the package or any envelope.
- **Two writers:** batch receipts are per writer (`BATCH_ID_CONFLICT`) and the client batch id now
  includes the writer (both writers share the IDK and `seq` is a local counter — the old id could make
  B's batch look "already stored" = silent loss; fixed + regression test). CAS on headRev forces pull
  before push. Same entity edited on both ⇒ first commit wins; the other device keeps its attempted
  value verbatim in `sync_conflicts` (UI: "Xung đột cần xem lại: N"). Delete vs edit: whichever commits
  first wins, the other is a recorded conflict (a committed delete is never resurrected by a stale edit;
  a stale delete of an entity edited first is recorded, not applied). Delete vs delete ⇒ idempotent.
  No automatic semantic merge. Merged offline spends that drive a pool negative are DETECTED after pull
  (`overdrawnPools`, red warning) — the server cannot check ciphertext; nothing is auto-fixed.
- **Remote-change signal (FCM, no polling):** after a committed Family batch the server sends a
  data-only FCM `{t: 'head'}` (collapse key, no walletId/amount/text) to every OTHER active member device
  that registered a token (`registerSyncSignal`: P7.1 session + ACTIVE membership; token bound to the
  installation; dead tokens dropped; best effort, never fails the write; skipped in the emulator).
  Foreground ⇒ `requestPull()`; background/killed ⇒ the isolate only sets a persistent flag, consumed
  on resume. Token is re-registered only when token/installation/wallet/Account change ⇒ normal app
  opens and idle = 0 cloud calls.
- **Account semantics (§27 unchanged, now exercised):** Family Wallet opens only for its bound Account;
  sign-out / other Account X ⇒ hidden (no DB opened, file + DB key + BMK untouched, no claim/restore
  possible for X); A back ⇒ same file, same walletId. Same on the Member device (B→Y→B).
- **Revocation (`revokeFamilyMember`, Owner + step-up):** membership REVOKED, wrapped key + device key
  + FCM token cleared, account index removed ⇒ B's next cloud call gets `NOT_MEMBER` ⇒ the app marks the
  registry entry `accessRevoked` ⇒ Wallet hidden; local encrypted DB NOT erased. **Honest limit:** a
  revoked device that stays offline keeps the data it already had and the BMK in its Keystore (it can
  still decrypt ciphertext it downloaded before); SQLCipher + FBE + App Lock protect extraction. Forward
  secrecy after removal (BMK rotation + re-encryption) is NOT implemented — separate design.
- **Tests:** backend emulator 26/26 (family: invite/accept/guards/expiry/reuse/race/max 2/revoke/
  device-key binding/batch-id conflict/NOT_MEMBER/signal registration/Rules deny-all); Dart:
  `family_key_crypto_test` (roundtrip, wrong key, every ctx field, tamper, low-order, fingerprint,
  wallet code), `family_flow_test` (FakeCloud: promote, invite, fingerprint, share, join, A→B/B→A same
  ids + balances, batch-id regression, conflict, delete/edit, delete/delete, overdraw, revoke, A→X→A,
  B→Y→B, stale P7.1), `family_emulator_e2e_test` (REAL emulator backend, A/B/X, Firestore scan: no
  plaintext/BMK/token), `family_screen_test`, `remote_signal_test`, registry flags.
- **LIVE DEV (2026-09-27, Pixel 7a = A `diennguyendhv@…` Chồng/Owner; Android emulator
  `HW_Family_B` API 35 Google Play = B `diennguyenaz.com@…` Vợ/Member; X = `nguyenvangaara25@…`):**
  promote dc268fde in place (Mã ví `6547 0921 2441`) → invite Vợ → B preview (neutral: expiry only) →
  accept → both screens `2301 7547 8546` → A shares key → B "Đã tải và kiểm chứng", role Vợ, same Mã ví.
  A→B: TA (+123.000 Chồng) pushed 1 call → FCM → B pulled automatically. B→A: TB (+45.600 Vợ) → FCM →
  A home updated by itself. On-device integrity reports A vs B: same walletId, schema 11, SQLCipher,
  integrity ok, FK 0, 8 transactions with identical ids/clientTxIds and per-row/per-column digests,
  every financial table digest identical (only cloud_binding/sync_state/sqlite_sequence differ —
  device-local). Delete on B → tombstone → gone on A. Idle 90 s both devices: 0 sync runs/calls.
  A→X→A and B→Y→B: X/Y see only the install-time local wallet; X `getMyFamily` → not-member, reused
  token → INVITE_INVALID; back to A/B ⇒ same file/walletId/data, no restore. Revoke: A shows "Đã thu
  hồi"; B next sync → NOT_MEMBER → Wallet hidden, file kept, registry `accessRevoked: true`.
  **Found + fixed live:** (1) app transport allowlist lacked the Family callables (all Family calls
  denied locally) — added + static test `session_transport_allowlist_test`; (2) pulled rows are written
  with raw SQL so Drift streams were not notified (UI stale until restart) — engine now
  `notifyUpdates` after an applying pull (+ regression assert). An unplanned −10.000 đ "Chồng" expense
  (17:57:00) was created by a misfired scripted tap on B while adb dropped; it synced consistently and
  was then deleted from B (used as the live delete test). After sign-out/in the P7.1 session must be
  re-activated (signal-triggered pull was blocked with 0 calls until then — by design).
- **Pending / not done:** backend-sent invite email; forward secrecy after revoke; conflict review
  UI beyond the count. (Member-side claim "abandon" is now hidden — closure below.)
- **Family DEV final closure (2026-09-27):**
  - *Member wording fix:* the Settings card on a Member device could keep showing the install-time
    local Wallet's state ("chưa gắn với tài khoản nào") after the Member joined, because
    `WalletClaimControls` only loaded in `initState` (the joined Wallet is a new DB/service). It now
    reloads when the service changes, and for a Family Wallet shows the ROLE instead of the Personal
    claim text: title "Ví gia đình"; Member ⇒ "Bạn là Thành viên … Chủ ví quản lý thành viên và khoá
    sao lưu; bạn dùng và đồng bộ ví chung" (no register/check/abandon actions); Owner ⇒ "Bạn là Chủ
    ví …". The backup card on a Member reads "Đồng bộ mã hoá Ví gia đình" / "Máy này giữ khoá ví do
    Chủ ví chia sẻ". Display only (`activeWalletFamilyRoleProvider` from the registry); permissions are
    still enforced by the server.
  - *Key-sharing crypto audit:* primitives from package `cryptography` 2.9.0 (pure-Dart
    `DartX25519`, `DartHkdf(DartHmac.sha256)`, `DartAesGcm.with256bits`), composed as ECIES/HPKE-base
    style; no custom primitive. The context string (version `vinhaminh-family-bmk-share-v1` | walletId |
    ownerAccountId | recipient uid | recipient memberId | recipient installationId | recipient public
    key) is BOTH in the HKDF info and the AES-GCM AAD, so changing any field fails authentication. The
    12-digit code is SHA-256(label|context) truncated to 48 bits: computed only from public values, it is
    a human SAS against public-key substitution — never key material and never the sole authorization
    (putMemberKey also requires the current Owner, P7.1 session, ACTIVE membership, pinned
    SHA-256(public key) + installation; getMemberKey requires the ACTIVE Member on that installation).
    Server/admin holds only public keys, `{v,epk,n,c}`, invite metadata/token hash, the code-derivable
    public context: none of it yields the BMK (needs the Member device's X25519 private seed — in its
    Keystore-wrapped slot — or the Owner's discarded ephemeral key). "Mã ví" is a one-way HKDF
    commitment. *Hardening note (non-blocking):* a 48-bit SAS means an ACTIVE malicious server would
    need ~2^48 key-generation attempts inside the invite window to forge a matching code; acceptable for
    v1, a longer code or commit-then-reveal is future hardening.
- **Known Family v1 limitations (accepted, non-blocking; NOT to be "solved" with server plaintext):**
  1. Invitation delivery is manual (Owner copies the one-time code); no server email yet.
  2. Conflict review UI is minimal (count "Xung đột cần xem lại: N"); the losing value is kept in
     `sync_conflicts`, but there is no detailed compare/restore screen yet.
  3. A revoked device that stays offline keeps the encrypted local data and the BMK it already had
     until normal security boundaries apply (SQLCipher + FBE + App Lock; no remote wipe).
  4. No BMK rotation / forward secrecy after revocation (future hardening).
  5. Two devices offline can each spend from the same pool; after merge the aggregate can go negative
     — the app detects and warns after convergence (`overdrawnPools`), nothing is auto-fixed.
  6. The server cannot enforce financial balance semantics because payloads are zero-knowledge
     ciphertext; the client engine is authoritative.

## 9. Remaining before full P8
~~SQLCipher phase~~ ✅ → ~~local outbox/binding (P8.1)~~ ✅ → ~~Wallet claim flow
(P8.2)~~ ✅ → P8.3 encrypted initial backup: baseline enqueue + per-entity rev tracking → incremental upload of
real entity kinds → restore into a fresh Wallet (no seed) + reconciliation →
tombstone/idempotency review → Recovery Key regeneration + disable backup +
trusted-device removal endpoints (each with step-up) → PILOT only after owner
approval.
