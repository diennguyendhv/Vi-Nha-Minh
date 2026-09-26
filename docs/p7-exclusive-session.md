# P7 — Exclusive Account Session Foundation

Status: implementation and emulator proof available; final device/deployment gates
pending. **Do not declare overall PASS yet. P8 has not started.**

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

Emulators ran with host Node 24 while deployment runtime is Node 22; live DEV
verification is still required. Lockfile pins backend/test dependencies.

Pending: Firebase CLI authentication and DEV-only deployment, DEV activation/check/sign-out,
Keystore persistence over force-stop/reopen, and second logical client replacement
against the same deployed DEV service. No need for two physical phones.

Use only `--project vi-nha-minh-55c60` for an eventual DEV deployment. Inspect DEV
Firestore setup first; do not deploy these deny-all Rules to another environment.
No private key/service account is required in Flutter or the repository.

## References

- [Firebase callable protocol](https://firebase.google.com/docs/functions/callable-reference)
- [Firebase token lifecycle](https://firebase.google.com/docs/auth/admin/manage-sessions)
- [Firebase custom claims](https://firebase.google.com/docs/auth/admin/custom-claims)
- [Android Keystore parameters](https://developer.android.com/reference/android/security/keystore/KeyGenParameterSpec)
