'use strict';
const {randomBytes, createHash, timingSafeEqual} = require('node:crypto');
const {initializeApp} = require('firebase-admin/app');
const {getFirestore, Timestamp} = require('firebase-admin/firestore');
const {onCall, HttpsError} = require('firebase-functions/v2/https');
initializeApp();
const db = getFirestore();
const hash = value => createHash('sha256').update(value).digest('hex');
const uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const token43 = /^[A-Za-z0-9_-]{43}$/;
const b64 = /^[A-Za-z0-9+/]*={0,2}$/;
const walletIdPattern = /^[A-Za-z0-9_-]{8,64}$/;
const RECENT_AUTH_SECONDS = 30 * 60;
const TAKEOVER_REQUEST_MS = 10 * 60 * 1000;
const TAKEOVER_GRANT_MS = 5 * 60 * 1000;
const MAX_REVOKED = 20;
// Per-account limits for sensitive secret checks / takeover attempts.
const LIMIT = {max: 5, windowMs: 15 * 60 * 1000, lockMs: 30 * 60 * 1000};
const MAX_CIPHERTEXT_B64 = 16384;
const MAX_BATCH = 100;

const reject = (code, reason, message = reason) =>
  new HttpsError(code, message, {reason});
const sameHash = (value, expectedHex) =>
  typeof expectedHex === 'string' && /^[0-9a-f]{64}$/.test(expectedHex) &&
  timingSafeEqual(Buffer.from(hash(value), 'hex'), Buffer.from(expectedHex, 'hex'));

function context(request) {
  // Deployment remains opt-in DEV; emulator uses a non-live demo project.
  const project = process.env.GCLOUD_PROJECT;
  if (!(project === 'demo-homewallet-p7' && process.env.FUNCTIONS_EMULATOR === 'true') &&
      project !== 'vi-nha-minh-55c60') {
    throw new HttpsError('failed-precondition', 'DEV session service disabled');
  }
  if (!request.auth) throw new HttpsError('unauthenticated', 'Authentication required');
  const data = request.data;
  if (!data || typeof data !== 'object' || Array.isArray(data)) {
    throw new HttpsError('invalid-argument', 'Invalid request');
  }
  if (data.accountId !== request.auth.uid) {
    throw new HttpsError('permission-denied', 'Account mismatch');
  }
  const uid = request.auth.uid;
  return {data, uid, ref: db.doc(`accounts/${uid}/session/current`)};
}
/** Firebase Auth alone is only trusted when the sign-in itself is recent. */
function requireRecentAuth(request) {
  const authTime = request.auth.token.auth_time;
  if (!Number.isSafeInteger(authTime) ||
      Date.now() / 1000 - authTime > RECENT_AUTH_SECONDS) {
    throw reject('unauthenticated', 'RECENT_LOGIN_REQUIRED');
  }
}
const epochOf = record => record.epoch ?? 1;
function validTakeover(t) {
  return t === null || t === undefined || (typeof t === 'object' &&
    typeof t.requestId === 'string' && token43.test(t.requestId) &&
    typeof t.targetInstallationId === 'string' && uuid.test(t.targetInstallationId) &&
    typeof t.requestSecretHash === 'string' && /^[0-9a-f]{64}$/.test(t.requestSecretHash) &&
    typeof t.code === 'string' && /^[0-9]{6}$/.test(t.code) &&
    t.expiresAt instanceof Timestamp && typeof t.approved === 'boolean');
}
function valid(record) {
  return record && Number.isSafeInteger(record.generation) && record.generation > 0 &&
    typeof record.installationId === 'string' && uuid.test(record.installationId) &&
    typeof record.sessionSecretHash === 'string' && /^[0-9a-f]{64}$/.test(record.sessionSecretHash) &&
    record.activatedAt instanceof Timestamp && typeof record.active === 'boolean' &&
    (record.epoch === undefined || (Number.isSafeInteger(record.epoch) && record.epoch > 0)) &&
    (record.revokedInstallations === undefined || (Array.isArray(record.revokedInstallations) &&
      record.revokedInstallations.every(id => typeof id === 'string' && uuid.test(id)))) &&
    validTakeover(record.takeover);
}
function readState(snapshot) {
  const record = snapshot.data();
  if (snapshot.exists && (!valid(record) || record.generation >= Number.MAX_SAFE_INTEGER ||
      epochOf(record) >= Number.MAX_SAFE_INTEGER)) {
    throw new HttpsError('failed-precondition', 'Invalid session state');
  }
  return snapshot.exists ? record : null;
}
function credentialMatches(record, data) {
  return valid(record) && record.active && data.generation === record.generation &&
    data.epoch === epochOf(record) && data.installationId === record.installationId &&
    typeof data.secret === 'string' && token43.test(data.secret) &&
    sameHash(data.secret, record.sessionSecretHash);
}
function authorize(record, data) {
  if (!credentialMatches(record, data)) {
    // Lost-device recovery revoked this installation: tell it to wipe its
    // local cloud credential/BMK. Otherwise a plain, uniform denial.
    if (valid(record) && (record.revokedInstallations ?? []).includes(data.installationId)) {
      throw reject('permission-denied', 'DEVICE_REVOKED');
    }
    throw new HttpsError('permission-denied', 'Session not current');
  }
}
const limitRef = uid => db.doc(`accounts/${uid}/session/limits`);
async function checkLimit(uid, action) {
  const entry = (await limitRef(uid).get()).data()?.[action];
  if (entry?.lockedUntil instanceof Timestamp && entry.lockedUntil.toMillis() > Date.now()) {
    throw reject('resource-exhausted', 'RATE_LIMITED');
  }
}
/** Counts one attempt; locks the action after LIMIT.max inside the window. */
async function recordAttempt(uid, action) {
  await db.runTransaction(async tx => {
    const ref = limitRef(uid);
    const entry = (await tx.get(ref)).data()?.[action];
    const now = Date.now();
    const fresh = !entry || now - entry.windowStart.toMillis() > LIMIT.windowMs;
    const count = (fresh ? 0 : entry.count) + 1;
    tx.set(ref, {[action]: count >= LIMIT.max
      ? {count: 0, windowStart: Timestamp.fromMillis(now), lockedUntil: Timestamp.fromMillis(now + LIMIT.lockMs)}
      : {count, windowStart: fresh ? Timestamp.fromMillis(now) : entry.windowStart, lockedUntil: null}},
    {merge: true});
  });
}
/** Secret-check failures are counted, then re-thrown unchanged (no near-miss hints). */
async function limited(uid, action, run) {
  await checkLimit(uid, action);
  try {
    return await run();
  } catch (error) {
    if (error.countsAsFailure) await recordAttempt(uid, action);
    throw error;
  }
}
const secretFailure = (code, message, reason) => Object.assign(
  reason ? reject(code, reason, message) : new HttpsError(code, message), {countsAsFailure: true});
/** Replaces the current session atomically; every older credential is stale. */
function activateIn(tx, ref, previous, installationId, {epoch, revoked}) {
  const secret = randomBytes(32).toString('base64url');
  const generation = previous ? previous.generation + 1 : 1;
  tx.set(ref, {generation, epoch, installationId, sessionSecretHash: hash(secret),
    activatedAt: Timestamp.now(), active: true, takeover: null,
    revokedInstallations: revoked});
  // No logging of credentials; returned only by this activation response.
  return {generation, epoch, secret};
}
const liveTakeover = record => record?.takeover &&
  record.takeover.expiresAt.toMillis() > Date.now() ? record.takeover : null;
const displayCode = requestId =>
  String(parseInt(hash(`hw-takeover-code:${requestId}`).slice(0, 8), 16) % 1000000)
    .padStart(6, '0');
const options = {region: 'us-central1', enforceAppCheck: false, maxInstances: 5};

/**
 * P7.1: no active session → recent sign-in activates; the active installation may
 * rotate with its own current credential; any other installation gets
 * TAKEOVER_REQUIRED (or RECOVERY_REQUIRED if revoked by lost-device recovery).
 */
exports.activateSession = onCall(options, async request => {
  const {data, ref} = context(request);
  if (!uuid.test(data.installationId) || data.confirm !== true) {
    throw new HttpsError('invalid-argument', 'Explicit activation required');
  }
  return db.runTransaction(async tx => {
    const previous = readState(await tx.get(ref));
    const revoked = previous?.revokedInstallations ?? [];
    if (revoked.includes(data.installationId)) throw reject('failed-precondition', 'RECOVERY_REQUIRED');
    if (previous?.active) {
      if (!credentialMatches(previous, data)) throw reject('failed-precondition', 'TAKEOVER_REQUIRED');
    } else {
      requireRecentAuth(request);
    }
    return activateIn(tx, ref, previous, data.installationId,
      {epoch: previous ? epochOf(previous) : 1, revoked});
  });
});
exports.protectedPing = onCall(options, async request => {
  const {data, ref} = context(request);
  return db.runTransaction(async tx => {
    const record = (await tx.get(ref)).data();
    authorize(record, data);
    // P8+ must perform protected mutations IN this transaction after the gate.
    const takeover = liveTakeover(record);
    return {allowed: true, pendingTakeover: takeover && !takeover.approved
      ? {requestId: takeover.requestId, code: takeover.code,
        expiresAt: takeover.expiresAt.toMillis()} : null};
  });
});
exports.deactivateSession = onCall(options, async request => {
  const {data, ref} = context(request);
  return db.runTransaction(async tx => {
    authorize((await tx.get(ref)).data(), data);
    tx.update(ref, {active: false, takeover: null});
    return {deactivated: true};
  });
});


/** B asks to replace active A. Only approval FROM A's current credential enables it. */
exports.requestTakeover = onCall(options, async request => {
  const {data, uid, ref} = context(request);
  if (!uuid.test(data.installationId)) throw new HttpsError('invalid-argument', 'Invalid request');
  requireRecentAuth(request);
  await checkLimit(uid, 'request');
  await recordAttempt(uid, 'request');
  return db.runTransaction(async tx => {
    const record = readState(await tx.get(ref));
    if (!record?.active) throw reject('failed-precondition', 'NO_ACTIVE_SESSION');
    if ((record.revokedInstallations ?? []).includes(data.installationId)) {
      throw reject('failed-precondition', 'RECOVERY_REQUIRED');
    }
    if (record.installationId === data.installationId) throw reject('failed-precondition', 'ALREADY_ACTIVE');
    const requestId = randomBytes(32).toString('base64url');
    const requestSecret = randomBytes(32).toString('base64url');
    const expiresAt = Timestamp.fromMillis(Date.now() + TAKEOVER_REQUEST_MS);
    const code = displayCode(requestId);
    // Latest request replaces any earlier pending one; only its secret can complete.
    tx.update(ref, {takeover: {requestId, targetInstallationId: data.installationId,
      requestSecretHash: hash(requestSecret), code, expiresAt, approved: false}});
    return {requestId, requestSecret, code, expiresAt: expiresAt.toMillis()};
  });
});
async function decideTakeover(request, approve) {
  const {data, uid, ref} = context(request);
  // Step-up: handing the account to another device needs a recent sign-in
  // (the client additionally asks for the device credential / App Lock).
  if (approve) requireRecentAuth(request);
  return limited(uid, 'approve', () => db.runTransaction(async tx => {
    const record = (await tx.get(ref)).data();
    authorize(record, data);
    const takeover = liveTakeover(record);
    if (!takeover || takeover.approved || takeover.requestId !== data.requestId) {
      throw secretFailure('failed-precondition', 'No pending takeover', 'NO_PENDING_TAKEOVER');
    }
    tx.update(ref, {takeover: approve ? {...takeover, approved: true,
      expiresAt: Timestamp.fromMillis(Math.min(takeover.expiresAt.toMillis(),
        Date.now() + TAKEOVER_GRANT_MS))} : null});
    return {approved: approve};
  }));
}
exports.approveTakeover = onCall(options, request => decideTakeover(request, true));
exports.rejectTakeover = onCall(options, request => decideTakeover(request, false));
/** Single-use: success consumes the grant; target installation + uid are bound. */
exports.completeTakeover = onCall(options, async request => {
  const {data, uid, ref} = context(request);
  if (!uuid.test(data.installationId)) throw new HttpsError('invalid-argument', 'Invalid request');
  requireRecentAuth(request);
  return limited(uid, 'complete', () => db.runTransaction(async tx => {
    const record = readState(await tx.get(ref));
    const takeover = liveTakeover(record);
    if (!record?.active || !takeover || takeover.requestId !== data.requestId ||
        takeover.targetInstallationId !== data.installationId ||
        typeof data.requestSecret !== 'string' || !token43.test(data.requestSecret) ||
        !sameHash(data.requestSecret, takeover.requestSecretHash)) {
      throw secretFailure('permission-denied', 'Takeover not authorized');
    }
    if (!takeover.approved) throw reject('failed-precondition', 'TAKEOVER_PENDING');
    return activateIn(tx, ref, record, data.installationId,
      {epoch: epochOf(record), revoked: record.revokedInstallations ?? []});
  }));
});

/**
 * "Thiết bị cũ đã mất": recent sign-in PLUS a device-takeover credential derived
 * client-side (domain-separated) from the Backup Password or Recovery Key. The
 * Recovery Key itself never reaches the server; only SHA-256 of the derived
 * credential is stored. Never the App Lock PIN, never installationId.
 * Epoch increments; the replaced installation is revoked.
 */
exports.recoverSession = onCall(options, async request => {
  const {data, uid, ref} = context(request);
  if (!uuid.test(data.installationId) || !walletIdPattern.test(data.walletId ?? '') ||
      !['password', 'recovery'].includes(data.proofKind) ||
      typeof data.proof !== 'string' || !token43.test(data.proof)) {
    throw new HttpsError('invalid-argument', 'Invalid request');
  }
  requireRecentAuth(request);
  const keyringRef = db.doc(`accounts/${uid}/backupKeyrings/${data.walletId}`);
  return limited(uid, 'recover', () => db.runTransaction(async tx => {
    const record = readState(await tx.get(ref));
    const keyring = (await tx.get(keyringRef)).data();
    const expected = keyring?.[data.proofKind === 'password' ? 'passwordProofHash' : 'recoveryProofHash'];
    if (!sameHash(data.proof, expected)) {
      // Same answer for unknown wallet, wrong kind or wrong proof.
      throw secretFailure('permission-denied', 'Recovery proof rejected');
    }
    let revoked = (record?.revokedInstallations ?? []).filter(id => id !== data.installationId);
    if (record && record.installationId !== data.installationId) {
      revoked = [...revoked.filter(id => id !== record.installationId), record.installationId]
        .slice(-MAX_REVOKED);
    }
    return activateIn(tx, ref, record, data.installationId,
      {epoch: record ? epochOf(record) + 1 : 1, revoked});
  }));
});


// ---------------------------------------------------------------------------
// P8 zero-knowledge backup: server stores wrapped keys and ciphertext only.
// No function here can decrypt; no decryption key exists server-side.
// ---------------------------------------------------------------------------
function b64Bytes(value, min, max) {
  if (typeof value !== 'string' || !b64.test(value) || value.length > 4 * Math.ceil(max / 3)) {
    return false;
  }
  const length = Buffer.from(value, 'base64').length;
  return length >= min && length <= max && Buffer.from(value, 'base64').toString('base64') === value;
}
const exactKeys = (object, keys) => object && typeof object === 'object' &&
  !Array.isArray(object) && Object.keys(object).sort().join() === [...keys].sort().join();
function validSlot(slot, kind) {
  if (!exactKeys(slot, ['salt', 'kdf', 'nonce', 'wrapped']) ||
      !b64Bytes(slot.salt, 16, 32) || !b64Bytes(slot.nonce, 12, 12) ||
      !b64Bytes(slot.wrapped, 48, 48)) {
    return false;
  }
  const kdf = slot.kdf;
  return kind === 'password'
    // `norm: 'NFC'` versions the client's password pre-processing.
    ? exactKeys(kdf, ['alg', 'v', 'm', 't', 'p', 'norm']) && kdf.alg === 'argon2id' && kdf.v === 19 &&
      kdf.norm === 'NFC' &&
      Number.isSafeInteger(kdf.m) && kdf.m >= 19456 && kdf.m <= 1048576 &&
      Number.isSafeInteger(kdf.t) && kdf.t >= 2 && kdf.t <= 10 &&
      Number.isSafeInteger(kdf.p) && kdf.p >= 1 && kdf.p <= 8
    : exactKeys(kdf, ['alg']) && kdf.alg === 'hkdf-sha256';
}
function keyringRefs(uid, walletId) {
  if (!walletIdPattern.test(walletId ?? '')) throw new HttpsError('invalid-argument', 'Invalid wallet');
  return db.doc(`accounts/${uid}/backupKeyrings/${walletId}`);
}
/**
 * create: first setup. rewrapPassword: same BMK re-wrapped under a new Backup
 * Password; recovery slot and every ciphertext stay untouched. Requires the
 * current session AND (old password proof OR recent sign-in).
 */
exports.putBackupKeyring = onCall(options, async request => {
  const {data, uid, ref} = context(request);
  const keyringRef = keyringRefs(uid, data.walletId);
  if (!validSlot(data.password, 'password') || typeof data.passwordProof !== 'string' ||
      !token43.test(data.passwordProof)) {
    throw new HttpsError('invalid-argument', 'Invalid keyring');
  }
  return db.runTransaction(async tx => {
    authorize((await tx.get(ref)).data(), data);
    const existing = (await tx.get(keyringRef)).data();
    if (data.mode === 'create') {
      if (existing) throw reject('already-exists', 'KEYRING_EXISTS');
      if (data.cryptoVersion !== 1 || !validSlot(data.recovery, 'recovery') ||
          typeof data.recoveryProof !== 'string' || !token43.test(data.recoveryProof)) {
        throw new HttpsError('invalid-argument', 'Invalid keyring');
      }
      tx.set(keyringRef, {cryptoVersion: 1, rev: 1, password: data.password,
        recovery: data.recovery, passwordProofHash: hash(data.passwordProof),
        recoveryProofHash: hash(data.recoveryProof), updatedAt: Timestamp.now()});
      return {rev: 1};
    }
    if (data.mode !== 'rewrapPassword' || !existing) throw reject('failed-precondition', 'NO_KEYRING');
    if (existing.rev !== data.expectedRev) throw reject('aborted', 'KEYRING_CHANGED');
    // Step-up always (recent sign-in; client adds device credential). An
    // old-password proof, when supplied, must also be right.
    requireRecentAuth(request);
    if (data.oldPasswordProof !== undefined && !(typeof data.oldPasswordProof === 'string' &&
        sameHash(data.oldPasswordProof, existing.passwordProofHash))) {
      throw new HttpsError('permission-denied', 'Old password proof rejected');
    }
    tx.update(keyringRef, {rev: existing.rev + 1, password: data.password,
      passwordProofHash: hash(data.passwordProof), updatedAt: Timestamp.now()});
    return {rev: existing.rev + 1};
  });
});
/** Wrapped material only (never proof hashes). Session credential OR recent sign-in. */
exports.getBackupKeyring = onCall(options, async request => {
  const {data, uid, ref} = context(request);
  const keyringRef = keyringRefs(uid, data.walletId);
  if (data.secret !== undefined) authorize((await ref.get()).data(), data);
  else requireRecentAuth(request);
  const keyring = (await keyringRef.get()).data();
  if (!keyring) throw reject('not-found', 'NO_KEYRING');
  return {cryptoVersion: keyring.cryptoVersion, rev: keyring.rev,
    password: keyring.password, recovery: keyring.recovery};
});
/** Wallet ids with a keyring (opaque ids only) — lets a new device pick one. */
exports.listBackupWallets = onCall(options, async request => {
  const {data, uid, ref} = context(request);
  if (data.secret !== undefined) authorize((await ref.get()).data(), data);
  else requireRecentAuth(request);
  const snapshot = await db.collection(`accounts/${uid}/backupKeyrings`).select().limit(20).get();
  return {walletIds: snapshot.docs.map(d => d.id)};
});
function validEnvelope(e) {
  // Generic encrypted object: entity kind, amounts, names and local ids are
  // all inside the ciphertext; only opaque id + rev + crypto framing are visible.
  return exactKeys(e, ['v', 'id', 'rev', 'n', 'c', 'aad']) && e.v === 1 && e.aad === 1 &&
    typeof e.id === 'string' && token43.test(e.id) &&
    Number.isSafeInteger(e.rev) && e.rev >= 1 && b64Bytes(e.n, 12, 12) &&
    typeof e.c === 'string' && e.c.length <= MAX_CIPHERTEXT_B64 && b64Bytes(e.c, 17, 12288);
}
/**
 * Session gate + ownership + envelope shape + CAS(headRev) + per-entity rev +
 * idempotent batch receipt, all in ONE transaction. Ciphertext is opaque here.
 * DEV fixture wallets only until the SQLCipher gate passes.
 */
exports.putEncryptedBatch = onCall(options, async request => {
  const {data, uid, ref} = context(request);
  const keyringRef = keyringRefs(uid, data.walletId);
  const envelopes = data.envelopes;
  if (typeof data.batchId !== 'string' || !token43.test(data.batchId) ||
      !Number.isSafeInteger(data.baseHeadRev) || data.baseHeadRev < 0 ||
      !Array.isArray(envelopes) || envelopes.length < 1 || envelopes.length > MAX_BATCH ||
      !envelopes.every(validEnvelope) || new Set(envelopes.map(e => e.id)).size !== envelopes.length) {
    throw new HttpsError('invalid-argument', 'Invalid batch');
  }
  const walletRef = db.doc(`wallets/${data.walletId}`);
  const receiptRef = walletRef.collection('batches').doc(data.batchId);
  const entityRefs = envelopes.map(e => walletRef.collection('entities').doc(e.id));
  return db.runTransaction(async tx => {
    authorize((await tx.get(ref)).data(), data);
    const keyring = (await tx.get(keyringRef)).data();
    const wallet = (await tx.get(walletRef)).data();
    const receipt = (await tx.get(receiptRef)).data();
    const current = await Promise.all(entityRefs.map(r => tx.get(r)));
    if (!keyring || keyring.cryptoVersion !== 1) throw reject('failed-precondition', 'NO_KEYRING');
    if (wallet && wallet.ownerAccountId !== uid) throw new HttpsError('permission-denied', 'Not owner');
    if (!wallet && data.fixture !== true) throw reject('failed-precondition', 'FIXTURE_ONLY');
    if (receipt) return {headRev: receipt.headRev, duplicate: true};
    const head = wallet?.headRev ?? 0;
    if (head !== data.baseHeadRev) throw reject('aborted', 'HEAD_MOVED');
    envelopes.forEach((e, i) => {
      const stored = current[i].data();
      if (stored && stored.rev >= e.rev) throw reject('aborted', 'STALE_REV');
    });
    const headRev = head + 1;
    const now = Timestamp.now();
    tx.set(walletRef, wallet ? {headRev, updatedAt: now}
      : {ownerAccountId: uid, cryptoVersion: 1, fixture: true, headRev, updatedAt: now},
    {merge: true});
    envelopes.forEach((e, i) => tx.set(entityRefs[i], {...e, serverRev: headRev}));
    tx.set(receiptRef, {headRev, count: envelopes.length, at: now});
    return {headRev, duplicate: false};
  });
});
exports.getEncryptedChanges = onCall(options, async request => {
  const {data, uid, ref} = context(request);
  if (!walletIdPattern.test(data.walletId ?? '') || !Number.isSafeInteger(data.sinceRev) ||
      data.sinceRev < 0) {
    throw new HttpsError('invalid-argument', 'Invalid request');
  }
  authorize((await ref.get()).data(), data);
  const walletRef = db.doc(`wallets/${data.walletId}`);
  const wallet = (await walletRef.get()).data();
  if (!wallet) return {headRev: 0, envelopes: []};
  if (wallet.ownerAccountId !== uid) throw new HttpsError('permission-denied', 'Not owner');
  const snapshot = await walletRef.collection('entities').where('serverRev', '>', data.sinceRev)
    .orderBy('serverRev').limit(200).get();
  return {headRev: wallet.headRev, envelopes: snapshot.docs.map(d => {
    const {v, id, rev, n, c, aad, serverRev} = d.data();
    return {v, id, rev, n, c, aad, serverRev};
  })};
});
