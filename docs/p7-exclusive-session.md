# P7 — Exclusive Account Session Foundation

Status: **P7 PASS (2026-09-26)** — deployed DEV backend rejects stale device credentials
and Pixel lifecycle acceptance passed. **P7.1 secure takeover: implemented + emulator
PASS; DEV deploy/Pixel acceptance pending** (see section P7.1 and
`docs/p8-cloud-backup-architecture.md`).

## Architecture and scope

Firebase Auth identifies the Account; a separate 256-bit random bearer secret
identifies its current cloud session. `activateSession` requires authenticated UID,
matching accountId, installation UUID v4 and explicit confirmation. It atomically
increments generation and replaces `accounts/{uid}/session/current`, storing only
SHA-256(secret), installationId, activatedAt and active. The raw secret is returned
only in that activation response, never readable from a server document.

`protectedPing` and `deactivateSession` verify the authenticated UID, account context,
well-formed active record, generation, installationId and constant-time hash match.
The gate runs inside a Firestore transaction. Concurrent activation order means
commit order, not tap/request-start order. A response can already be stale if another
activation committed afterward; the client checks with protectedPing after activation.

After B activation commits, the next protected request carrying A's old credential
is denied even when A's Firebase token remains valid. Already-authorized operations
are not retrospectively cancelled. P8+ mutations must check the session and mutate
within the same transaction. All alternate direct client paths must remain denied;
Firestore Rules currently deny all client reads/writes. Family membership checks are
additional future authorization, never replaced by this gate.

No custom device claims, refresh-token revocation, financial cloud operations,
Wallet claims, membership creation, financial-member binding or schema changes.
Client session bootstrap is DEV-only. Server handlers allow only DEV project
`vi-nha-minh-55c60` or `demo-homewallet-p7` inside Functions emulator.

## P7.1 — Secure device takeover (2026-09-26, supersedes "explicit activation replaces")

Threat fixed: under P7, any installation with a valid Firebase token could
activate and evict the other (A↔B ping-pong); a stolen, still-signed-in phone
could keep reclaiming. **Firebase Auth proves WHO; the P7 credential proves WHICH
installation. Auth alone never replaces an active installation.**

Record `accounts/{uid}/session/current` adds `epoch` (missing ⇒ 1),
`revokedInstallations` (≤ 20 UUIDs) and `takeover` {requestId,
targetInstallationId, requestSecretHash, code, expiresAt, approved} | null.
Credentials now carry `epoch`. Recent sign-in = `auth_time` ≤ 30 min.

| Call | Rule |
|---|---|
| `activateSession` | revoked installation ⇒ RECOVERY_REQUIRED; active session + matching own credential ⇒ rotate; active session otherwise ⇒ TAKEOVER_REQUIRED; no active session ⇒ recent sign-in required |
| `requestTakeover` (B) | recent sign-in, rate-limited; stores hash of a one-time 256-bit request secret, 6-digit display code, 10 min expiry; latest request replaces older |
| `protectedPing` (A) | returns `pendingTakeover {requestId, code}` |
| `approveTakeover` (A) | A's current credential + recent sign-in (+ client device credential); approval valid ≤ 5 min |
| `rejectTakeover` (A) | clears request |
| `completeTakeover` (B) | recent sign-in + approved + same uid/requestId/target installation + request secret; consumed atomically (single-use); else TAKEOVER_PENDING / denied |
| `recoverSession` (lost device) | recent sign-in + takeover credential derived from Backup Password or Recovery Key (server stores SHA-256 only); `epoch+1`, new credential, old installation added to `revokedInstallations` |

Old A after lost-device recovery: `protectedPing`/`deactivateSession` ⇒ 403
`DEVICE_REVOKED` (client then wipes its P7 credential + local BMK);
`activateSession` ⇒ RECOVERY_REQUIRED even after B logs out; a reinstall with a
new UUID still needs a recent Google sign-in. Not usable as recovery secret:
App Lock PIN, installationId. Rate limits (per account, 5 per 15 min ⇒ 30 min
lock): recovery proofs, grant completion, approval, takeover requests; the
error for a wrong/unknown proof is uniform. All decisions happen in Firestore
transactions; concurrent attempts leave exactly one current credential.

Client: TAKEOVER_REQUIRED dialog → "Xin thiết bị đang hoạt động" (shows code,
"Hoàn tất chuyển") or "Thiết bị cũ đã mất" (Backup Password / Recovery Key).
Step-up (device credential/biometric where available + Google
`reauthenticateWithCredential` without sign-out) before approving and before
lost-device recovery; RECENT_LOGIN_REQUIRED offers "Xác thực lại".
Limitations: a thief who also has the victim's Google credentials AND Backup
Password/Recovery Key can recover; the takeover code is compared by a human.

## Client behavior and storage

- Installation UUID v4 is native, persisted device-only, unchanged on logout.
- Credential JSON is AES-256-GCM encrypted with a non-exportable Android Keystore
  key, with UID as authenticated associated data. Native private preferences contain
  ciphertext, not the plaintext secret. This storage/key is separate from App Lock.
- Existing Android backup exclusions remain. Reinstall/key loss requires explicit
  activation; there is no plaintext fallback. Native errors contain no credentials.
- UI requires activation confirmation. Auth refresh, reopen and reconnect never
  activate automatically. Session status is explicitly the result of the last server
  check, not a promise that the device remains active. Offline/error is not success.
- Activation/check/logout are serialized so a pending activation cannot save a
  credential after completed logout. Different UIDs cannot read each other's saved
  credential. Account UI state resets when its account widget is removed/replaced.
- Logout tries current-session deactivation with a short timeout, then clears local
  credential and Firebase Auth even if offline/stale. An old A cannot deactivate B.
  Offline logout may leave a server record active until replacement; this is not
  represented as guaranteed remote revocation.
- Local unclaimed Wallet, registry, financial DB, IDs, PIN, biometrics and device
  preferences are not changed. Financial schema remains v8.

## Exact limitations

Possession of the active secret plus valid Firebase credentials for that UID grants
the session. This is not hardware attestation and does not defeat secret extraction
from a compromised running device. UUID alone grants nothing. App Check is currently
not enforced in DEV; it is defense in depth, not session authority.

Firebase ID and refresh tokens are not revoked by P7. A refreshed Firebase token
does not update the saved session secret. A stale authenticated user can explicitly
activate again; a server cannot infer human intent from a modified client sending
the activation API. P7 deliberately uses the approved explicit-activation model.

There is no P7 financial offline queue or direct Firestore client. A later queued
operation must be checked when the backend processes it, never on enqueue alone.
Local cached data cannot be erased remotely. A lost activation response cannot
recover its secret from the server; explicit activation rotates again.

## Verification

`functions/test/session.test.js` runs over real HTTP against Auth, Functions and
Firestore emulators, not mocked request.auth or an in-memory authorization stub.
It covers unauthenticated/cross-account denial, A accepted, B replacement, old A
denied with the **same still-valid Firebase token**, token refresh, wrong/missing
secret, stale generation, stale logout, explicit A reactivation, current logout,
malformed server state, concurrent activations, and direct Rules bypass denial.
Three emulator tests passed during initial implementation (2026-09-25), and again
on 2026-09-26 after malformed-state and DEV project guard hardening.

Flutter focused tests cover channel delegation, credential/account isolation,
logical reopen, activation/logout race, offline logout, native encryption structure,
confirmation/cancellation, stale/offline UI, and existing Auth/Wallet boundaries.
52 focused tests passed on 2026-09-26. Native Keystore behavior across actual
force-stop/reopen remains a **device acceptance requirement**, not proven by mocks.

DEV APK built successfully on 2026-09-25 and rebuilt from final source on
2026-09-26, installed with `adb install -r` to `com.vinhamimh.vi_nha_minh.dev`.
DEV process starts; Pixel was dozing/lockscreen foreground, so no visual acceptance
or Keystore lifecycle claim is made. No PROD build/install/data mutation.
Final full suite ran once on 2026-09-26: **1,036 passed, 3 skipped**.
`flutter analyze`: **0 errors/warnings, 17 existing info diagnostics** outside P7
(15 deprecated usages and 2 brace-style infos in existing transaction exploration).
Analyzer exits 1 for these infos; do not describe it as an entirely clean exit.

Read-only Pixel PROD health (2026-09-26): no live WAL/journal in app_flutter;
two consecutive byte-identical reads, inspected in memory only. Schema **v8**,
integrity **ok**, FK violations **0**, transactions **1,847**, wallet_meta **1**,
financial members **2**. SHA-256:
`37825f4eda345add2416610dac37289d8a923cee27cc304ad153f844cf04b46e`.
No force-stop, backup file, DB write, PROD installation or Firebase PROD access.

## Reproduce and finish

From repository root, with Node and Java available:

```powershell
cd functions
npm ci
cd ..
.\functions\node_modules\.bin\firebase.cmd emulators:exec --project demo-homewallet-p7 --only auth,firestore,functions "node --test functions/test/session.test.js"
flutter test test/auth test/wallet
flutter test --concurrency=1
flutter analyze
flutter build apk --debug --flavor dev --dart-define-from-file=env/dev.json
```

Emulators ran with host Node 24; the deployed DEV runtime is Node 22 (verified below).
Lockfile pins backend/test dependencies.

Deploy (DEV only; no `.firebaserc`, project always explicit):

```powershell
.unctions
ode_modules\.binirebase.cmd deploy --only functions:p7-session,firestore:rules --project vi-nha-minh-55c60
```

Never deploy these deny-all Rules to another environment. No private key/service
account is required in Flutter or the repository. `firebase.json` excludes
`node_modules`, `.npm-cache`, `test`, `.env*` from the Functions upload (~100 KB).

## DEV deployment and live acceptance (2026-09-26)

- Project `vi-nha-minh-55c60` on Blaze. `functions:list`: `activateSession`,
  `protectedPing`, `deactivateSession` — v2 callable, us-central1, **nodejs22**.
  Artifact cleanup policy 1 day. Released ruleset read back = deny-all file above.
- Before acceptance DEV Firestore had no collections; afterwards only
  `accounts/<uid>/session/current` with fields `activatedAt, active, generation,
  installationId, sessionSecretHash` (64-hex). No secret field, no financial data.
- Pixel 7a, `com.vinhamimh.vi_nha_minh.dev`, Google sign-in. The second logical
  device was simulated on the same Pixel (owner-approved): the app's own AES-GCM
  ciphertext file was copied/restored inside its sandbox between activations (never
  decrypted or exported; copies deleted afterwards). Server verdicts come from Cloud
  Run request logs of the deployed functions (403 = PERMISSION_DENIED with a valid
  Firebase token):
  1. Signed in, no credential: status "unchecked"; server had no session (no auto activation).
  2. Explicit confirm → gen 1, `protectedPing` 200. Force-stop/reopen → status
     "unchecked" (no auto call); Check → 200 (Keystore credential survived).
  3. Re-activate → gen 2 (B). Restored gen 1 (A) → `protectedPing` **403**; reopen
     again → still **403** (stale stays stale).
  4. Sign-out while holding stale A → `deactivateSession` **403**; server gen 2 still
     active; local credential/account removed, installation UUID kept.
  5. Sign in again → no credential, server unchanged (no auto activation). Restored
     gen 2 → 200 (B survived stale logout).
  6. Explicit Pixel reactivation → gen 3, 200. Old gen 2 → **403**. Gen 3 after
     force-stop/reopen → 200.
  7. Current sign-out → `deactivateSession` 200, server `active=false`, local
     credential cleared.
- App Lock setting unchanged (off on DEV; separate prefs/key). DEV Wallet DB and
  `wallet_registry.json` byte-identical before/after (SHA-256 `4be03e82…`,
  `0047c5e8…`); registry has no `boundAccountId` (not claimed).
- Not live-tested: direct client Firestore REST with a DEV ID token (emulator suite
  covers it; deployed ruleset verified deny-all); true offline logout (wireless adb).
- No source change after 76c162f except `firebase.json` upload ignore ⇒ Flutter
  suite not rerun (results above stand).

PROD read-only after acceptance (2026-09-26): two byte-identical reads, in memory
only, no WAL/journal. Schema **v8**, integrity **ok**, FK **0**, transactions
**1,849** (live data), wallet_meta 1, financial members 2, walletId `3cbd8878…`
unchanged. SHA-256 `0848c9effcc6792738f7a8a5b3e355848db67f1a812f0e60ad4e548f1d440ef5`.

## References

- [Firebase callable protocol](https://firebase.google.com/docs/functions/callable-reference)
- [Firebase token lifecycle](https://firebase.google.com/docs/auth/admin/manage-sessions)
- [Firebase custom claims](https://firebase.google.com/docs/auth/admin/custom-claims)
- [Android Keystore parameters](https://developer.android.com/reference/android/security/keystore/KeyGenParameterSpec)
