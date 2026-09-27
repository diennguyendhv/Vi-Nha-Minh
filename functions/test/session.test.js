'use strict';
const {test} = require('node:test');
const assert = require('node:assert/strict');
const {randomUUID, randomBytes, createCipheriv} = require('node:crypto');
const {initializeApp} = require('firebase-admin/app');
const {getFirestore, Timestamp} = require('firebase-admin/firestore');
const project = 'demo-homewallet-p7';
if (!process.env.FIRESTORE_EMULATOR_HOST || !process.env.FIREBASE_AUTH_EMULATOR_HOST) {
  throw new Error('Emulators required; never run against live Firebase');
}
initializeApp({projectId: project});
const db = getFirestore();
async function account() {
  const response = await fetch('http://127.0.0.1:9099/identitytoolkit.googleapis.com/v1/accounts:signUp?key=fake', {
    method: 'POST', headers: {'Content-Type': 'application/json'},
    body: JSON.stringify({returnSecureToken: true}),
  });
  assert.equal(response.status, 200);
  return response.json();
}
/** Same UID/token, but sign-in happened long ago (e.g. a stolen, still signed-in phone). */
function staleSignIn(user) {
  const [header, payload] = user.idToken.split('.');
  const claims = JSON.parse(Buffer.from(payload, 'base64url').toString());
  claims.auth_time -= 24 * 3600;
  const forged = Buffer.from(JSON.stringify(claims)).toString('base64url');
  return {...user, idToken: `${header}.${forged}.`};
}
async function call(name, user, data) {
  const response = await fetch(`http://127.0.0.1:5001/${project}/us-central1/${name}`, {
    method: 'POST', headers: {'Content-Type': 'application/json',
      ...(user ? {Authorization: `Bearer ${user.idToken}`} : {})},
    body: JSON.stringify({data: data && typeof data === 'object' && !Array.isArray(data)
      ? {clientEnv: 'dev', ...data} : data}),
  });
  return response.json();
}
const denied = response => assert.equal(response.error?.status, 'PERMISSION_DENIED', JSON.stringify(response));
const reason = (response, expected) =>
  assert.equal(response.error?.details?.reason, expected, JSON.stringify(response));
const allowed = async (user, credential) =>
  (await call('protectedPing', user, credential)).result?.allowed === true;
async function activate(user, installationId = randomUUID(), credential = {}) {
  const response = await call('activateSession', user,
    {...credential, accountId: user.localId, installationId, confirm: true});
  assert.ok(response.result?.secret, JSON.stringify(response));
  return {accountId: user.localId, installationId, ...response.result};
}
const sessionDoc = user => db.doc(`accounts/${user.localId}/session/current`);
const b = n => randomBytes(n).toString('base64');
const token = () => randomBytes(32).toString('base64url');
function keyring(credential, walletId, proofs) {
  return {...credential, walletId, mode: 'create', cryptoVersion: 1,
    password: {salt: b(16), kdf: {alg: 'argon2id', v: 19, m: 65536, t: 3, p: 4, norm: 'NFC'}, nonce: b(12), wrapped: b(48)},
    recovery: {salt: b(32), kdf: {alg: 'hkdf-sha256'}, nonce: b(12), wrapped: b(48)},
    passwordProof: proofs.password, recoveryProof: proofs.recovery};
}
async function takeover(user, a, bInstallation = randomUUID()) {
  const request = (await call('requestTakeover', user,
    {accountId: user.localId, installationId: bInstallation})).result;
  assert.match(request.code, /^[0-9]{6}$/);
  assert.equal((await call('approveTakeover', user, {...a, requestId: request.requestId})).result.approved, true);
  const response = await call('completeTakeover', user, {accountId: user.localId,
    installationId: bInstallation, requestId: request.requestId, requestSecret: request.requestSecret});
  return {accountId: user.localId, installationId: bInstallation, ...response.result};
}

test('P7 boundary: auth, isolation, refresh, logout, rotation, malformed state', async () => {
  const user = await account();
  const other = await account();
  assert.equal((await call('activateSession', null, {})).error.status, 'UNAUTHENTICATED');
  denied(await call('activateSession', user, {accountId: other.localId}));
  denied(await call('protectedPing', user, {accountId: user.localId}));
  const a = await activate(user);
  assert.equal(a.epoch, 1);
  assert.equal(await allowed(user, a), true);
  const stored = (await sessionDoc(user).get()).data();
  assert.equal(stored.secret, undefined);
  assert.notEqual(stored.sessionSecretHash, a.secret);
  denied(await call('protectedPing', user, {...a, secret: 'x'.repeat(43)}));
  denied(await call('protectedPing', user, {...a, secret: undefined}));
  denied(await call('protectedPing', user, {...a, epoch: 2}));
  denied(await call('protectedPing', other, a));
  denied(await call('protectedPing', other, {...a, accountId: other.localId}));
  // Same installation may rotate ONLY with its current credential.
  reason(await call('activateSession', user,
    {accountId: user.localId, installationId: a.installationId, confirm: true}), 'TAKEOVER_REQUIRED');
  const a2 = await activate(user, a.installationId, a);
  assert.equal(a2.generation, a.generation + 1);
  assert.equal(await allowed(user, a), false);
  const refreshed = await (await fetch('http://127.0.0.1:9099/securetoken.googleapis.com/v1/token?key=fake', {
    method: 'POST', headers: {'Content-Type': 'application/x-www-form-urlencoded'},
    body: new URLSearchParams({grant_type: 'refresh_token', refresh_token: user.refreshToken}),
  })).json();
  const reopened = {...user, idToken: refreshed.id_token};
  assert.equal(await allowed(reopened, a2), true);
  assert.equal((await call('deactivateSession', reopened, a2)).result.deactivated, true);
  assert.equal(await allowed(reopened, a2), false);
  // No active session: recent sign-in activates; an old sign-in alone does not.
  reason(await call('activateSession', staleSignIn(user),
    {accountId: user.localId, installationId: randomUUID(), confirm: true}), 'RECENT_LOGIN_REQUIRED');
  const a3 = await activate(reopened);
  assert.ok(a3.generation > a2.generation);
  await sessionDoc(user).update({generation: 'bad'});
  denied(await call('protectedPing', user, a3));
  assert.equal((await call('activateSession', user, {...a3, confirm: true})).error.status,
    'FAILED_PRECONDITION');
});

test('P7.1 approved takeover: B cannot silently replace A; grant is single-use', async () => {
  const user = await account();
  const a = await activate(user);
  const bId = randomUUID();
  // Firebase Auth alone (fresh or stale) never replaces an active installation.
  reason(await call('activateSession', user, {accountId: user.localId, installationId: bId, confirm: true}),
    'TAKEOVER_REQUIRED');
  assert.equal(await allowed(user, a), true);
  reason(await call('requestTakeover', staleSignIn(user), {accountId: user.localId, installationId: bId}),
    'RECENT_LOGIN_REQUIRED');
  reason(await call('requestTakeover', user, {accountId: user.localId, installationId: a.installationId}),
    'ALREADY_ACTIVE');
  const request = (await call('requestTakeover', user, {accountId: user.localId, installationId: bId})).result;
  assert.equal(request.requestSecret.length, 43);
  const stored = (await sessionDoc(user).get()).data().takeover;
  assert.equal(stored.requestSecret, undefined);
  assert.notEqual(stored.requestSecretHash, request.requestSecret);
  const ping = (await call('protectedPing', user, a)).result;
  assert.deepEqual([ping.pendingTakeover.requestId, ping.pendingTakeover.code], [request.requestId, request.code]);
  const complete = extra => call('completeTakeover', user, {accountId: user.localId, installationId: bId,
    requestId: request.requestId, requestSecret: request.requestSecret, ...extra});
  // The 6-digit code is display-only: it can never stand in for the grant.
  denied(await complete({requestSecret: request.code}));
  assert.equal((await call('approveTakeover', user, {...a, requestId: request.code})).error?.details?.reason,
    'NO_PENDING_TAKEOVER');
  // Client cannot self-assert approval.
  reason(await complete({approved: true}), 'TAKEOVER_PENDING');
  denied(await call('approveTakeover', user, {accountId: user.localId, installationId: bId,
    requestId: request.requestId, generation: a.generation, epoch: 1, secret: request.requestSecret}));
  reason(await call('approveTakeover', staleSignIn(user), {...a, requestId: request.requestId}), 'RECENT_LOGIN_REQUIRED');
  assert.equal((await call('approveTakeover', user, {...a, requestId: request.requestId})).result.approved, true);
  denied(await complete({requestSecret: token()}));
  denied(await complete({installationId: randomUUID()}));
  const other = await account();
  denied(await call('completeTakeover', other, {accountId: other.localId, installationId: bId,
    requestId: request.requestId, requestSecret: request.requestSecret}));
  reason(await call('completeTakeover', staleSignIn(user), {accountId: user.localId, installationId: bId,
    requestId: request.requestId, requestSecret: request.requestSecret}), 'RECENT_LOGIN_REQUIRED');
  const bSession = {accountId: user.localId, installationId: bId, ...(await complete({})).result};
  assert.equal(await allowed(user, bSession), true);
  assert.equal(bSession.epoch, 1);
  // Old A: stale everywhere, same valid Firebase token.
  assert.equal(await allowed(user, a), false);
  denied(await call('deactivateSession', user, a));
  reason(await call('activateSession', user, {...a, confirm: true}), 'TAKEOVER_REQUIRED');
  denied(await complete({}));
  assert.equal(await allowed(user, bSession), true);
  // Expired approval is denied.
  const cId = randomUUID();
  const late = (await call('requestTakeover', user, {accountId: user.localId, installationId: cId})).result;
  await call('approveTakeover', user, {...bSession, requestId: late.requestId});
  await sessionDoc(user).update({'takeover.expiresAt': Timestamp.fromMillis(Date.now() - 1000)});
  denied(await call('completeTakeover', user, {accountId: user.localId, installationId: cId,
    requestId: late.requestId, requestSecret: late.requestSecret}));
  // Rejected request cannot be completed.
  const rejected = (await call('requestTakeover', user, {accountId: user.localId, installationId: cId})).result;
  assert.equal((await call('rejectTakeover', user, {...bSession, requestId: rejected.requestId})).result.approved, false);
  // Denied (or already rate-limited after the earlier failed completions).
  const afterReject = await call('completeTakeover', user, {accountId: user.localId, installationId: cId,
    requestId: rejected.requestId, requestSecret: rejected.requestSecret});
  assert.equal(afterReject.result, undefined);
  assert.ok(['PERMISSION_DENIED', 'RESOURCE_EXHAUSTED'].includes(afterReject.error.status));
  assert.equal(await allowed(user, bSession), true);
});

test('P7.1 lost device: recovery proof moves session, bumps epoch, old A cannot reclaim', async () => {
  const user = await account();
  const a = await activate(user);
  const walletId = 'fixture-' + randomBytes(8).toString('hex');
  const proofs = {password: token(), recovery: token()};
  assert.equal((await call('putBackupKeyring', user, keyring(a, walletId, proofs))).result.rev, 1);
  const stored = JSON.stringify((await db.doc(`accounts/${user.localId}/backupKeyrings/${walletId}`).get()).data());
  assert.ok(!stored.includes(proofs.password) && !stored.includes(proofs.recovery));
  const bId = randomUUID();
  const recover = (who, extra) => call('recoverSession', who, {accountId: user.localId,
    installationId: bId, walletId, proofKind: 'recovery', proof: proofs.recovery, ...extra});
  denied(await recover(user, {proof: token()}));
  denied(await recover(user, {proofKind: 'password'}));
  reason(await recover(staleSignIn(user), {}), 'RECENT_LOGIN_REQUIRED');
  assert.equal(await allowed(user, a), true);
  const bSession = {accountId: user.localId, installationId: bId, ...(await recover(user, {})).result};
  assert.equal(bSession.epoch, 2);
  assert.equal(await allowed(user, bSession), true);
  // Old A learns it is revoked (so it can wipe its credential + BMK locally).
  reason(await call('protectedPing', user, a), 'DEVICE_REVOKED');
  reason(await call('deactivateSession', user, a), 'DEVICE_REVOKED');
  for (const who of [user, staleSignIn(user)]) {
    reason(await call('activateSession', who, {...a, confirm: true}), 'RECOVERY_REQUIRED');
  }
  reason(await call('requestTakeover', user, {accountId: user.localId, installationId: a.installationId}),
    'RECOVERY_REQUIRED');
  reason(await call('requestTakeover', staleSignIn(user),
    {accountId: user.localId, installationId: a.installationId}), 'RECENT_LOGIN_REQUIRED');
  denied(await call('approveTakeover', user, {...a, requestId: token()}));
  // Even after B logs out, A's installation still needs recovery; a new
  // installation needs a RECENT sign-in (old stolen token is not enough).
  await call('deactivateSession', user, bSession);
  reason(await call('activateSession', user, {...a, confirm: true}), 'RECOVERY_REQUIRED');
  reason(await call('activateSession', staleSignIn(user),
    {accountId: user.localId, installationId: randomUUID(), confirm: true}), 'RECENT_LOGIN_REQUIRED');
  // Password proof also works; epoch keeps increasing.
  const c = await call('recoverSession', user, {accountId: user.localId, installationId: randomUUID(),
    walletId, proofKind: 'password', proof: proofs.password});
  assert.equal(c.result.epoch, 3);
});

test('P7.1 concurrent takeover and recovery attempts leave exactly one active session', async () => {
  const user = await account();
  const a = await activate(user);
  const ids = [randomUUID(), randomUUID(), randomUUID()];
  const requests = await Promise.all(ids.map(id =>
    call('requestTakeover', user, {accountId: user.localId, installationId: id})));
  const pending = (await call('protectedPing', user, a)).result.pendingTakeover;
  await call('approveTakeover', user, {...a, requestId: pending.requestId});
  const completions = await Promise.all(requests.map((r, i) => call('completeTakeover', user,
    {accountId: user.localId, installationId: ids[i], requestId: r.result.requestId,
      requestSecret: r.result.requestSecret})));
  assert.equal(completions.filter(r => r.result).length, 1);
  // Replaying the winning grant concurrently: still single-use.
  const winner = completions.findIndex(r => r.result);
  const replays = await Promise.all([1, 2].map(() => call('completeTakeover', user, {accountId: user.localId,
    installationId: ids[winner], requestId: requests[winner].result.requestId,
    requestSecret: requests[winner].result.requestSecret})));
  assert.equal(replays.filter(r => r.result).length, 0);
  const walletId = 'fixture-' + randomBytes(8).toString('hex');
  const proofs = {password: token(), recovery: token()};
  const current = {accountId: user.localId, installationId: ids[winner], ...completions[winner].result};
  await call('putBackupKeyring', user, keyring(current, walletId, proofs));
  const recovered = await Promise.all([0, 1, 2].map(() => recoverFresh(user, walletId, proofs)));
  const all = [a, current, ...recovered];
  const results = await Promise.all(all.map(c => allowed(user, c)));
  assert.equal(results.filter(Boolean).length, 1);
});
async function recoverFresh(user, walletId, proofs) {
  const installationId = randomUUID();
  const response = await call('recoverSession', user, {accountId: user.localId, installationId,
    walletId, proofKind: 'recovery', proof: proofs.recovery});
  return {accountId: user.localId, installationId, ...response.result};
}

test('backup keyring: password rewrap keeps recovery slot; hashes never returned', async () => {
  const user = await account();
  const a = await activate(user);
  const walletId = 'fixture-' + randomBytes(8).toString('hex');
  const proofs = {password: token(), recovery: token()};
  const created = keyring(a, walletId, proofs);
  denied(await call('putBackupKeyring', user, {...created, secret: token()}));
  await call('putBackupKeyring', user, created);
  reason(await call('putBackupKeyring', user, created), 'KEYRING_EXISTS');
  const {norm, ...noNorm} = created.password.kdf;
  assert.equal(norm, 'NFC');
  assert.equal((await call('putBackupKeyring', user, {...created, walletId: walletId + 'x',
    password: {...created.password, kdf: noNorm}})).error.status, 'INVALID_ARGUMENT');
  assert.equal((await call('putBackupKeyring', user, {...created, password: {...created.password,
    kdf: {alg: 'argon2id', v: 19, m: 1024, t: 1, p: 1, norm: 'NFC'}}})).error.status, 'INVALID_ARGUMENT');
  const newSlot = {salt: b(16), kdf: {alg: 'argon2id', v: 19, m: 65536, t: 3, p: 4, norm: 'NFC'}, nonce: b(12), wrapped: b(48)};
  const rewrap = extra => call('putBackupKeyring', user, {...a, walletId, mode: 'rewrapPassword',
    expectedRev: 1, password: newSlot, passwordProof: token(), ...extra});
  reason(await call('putBackupKeyring', staleSignIn(user), {...a, walletId, mode: 'rewrapPassword',
    expectedRev: 1, password: newSlot, passwordProof: token()}), 'RECENT_LOGIN_REQUIRED');
  denied(await rewrap({oldPasswordProof: token()}));
  assert.equal((await rewrap({oldPasswordProof: proofs.password})).result.rev, 2);
  reason(await rewrap({}), 'KEYRING_CHANGED');
  const fetched = (await call('getBackupKeyring', user, {...a, walletId})).result;
  assert.deepEqual(fetched.password, newSlot);
  assert.deepEqual(fetched.recovery, created.recovery);
  assert.equal(JSON.stringify(fetched).includes('ProofHash'), false);
  reason(await call('getBackupKeyring', staleSignIn(user), {accountId: user.localId, walletId}),
    'RECENT_LOGIN_REQUIRED');
  assert.ok((await call('getBackupKeyring', user, {accountId: user.localId, walletId})).result);
  assert.deepEqual((await call('listBackupWallets', user, {accountId: user.localId})).result.walletIds, [walletId]);
  reason(await call('listBackupWallets', staleSignIn(user), {accountId: user.localId}), 'RECENT_LOGIN_REQUIRED');
});

test('encrypted batches: ciphertext only, CAS, idempotency, ownership, no plaintext at rest', async () => {
  const user = await account();
  const a = await activate(user);
  const walletId = 'fixture-' + randomBytes(8).toString('hex');
  await call('putBackupKeyring', user, keyring(a, walletId, {password: token(), recovery: token()}));
  const key = randomBytes(32);
  const plaintexts = [{amount: 1234567, note: 'Tiền chợ bí mật', category: 'Ăn uống XYZ'},
    {name: 'Quỹ du lịch bí mật', balance: 9876543}];
  const envelope = (value, id = token(), rev = 1, kind = 'transaction') => {
    const n = randomBytes(12);
    const cipher = createCipheriv('aes-256-gcm', key, n);
    cipher.setAAD(Buffer.from(`vinhaminh-env|v1|s1|${walletId}|${id}`));
    const inner = JSON.stringify({kind, localId: 'local-' + id.slice(0, 4), rev, body: value});
    const c = Buffer.concat([cipher.update(inner), cipher.final(), cipher.getAuthTag()]);
    return {v: 1, id, rev, n: n.toString('base64'), c: c.toString('base64'), aad: 1};
  };
  const e1 = envelope(plaintexts[0]);
  const e2 = envelope(plaintexts[1], token(), 1, 'fund');
  const batch = extra => call('putEncryptedBatch', user,
    {...a, walletId, batchId: token(), baseHeadRev: 0, fixture: true, envelopes: [e1, e2], ...extra});
  reason(await batch({fixture: undefined}), 'FIXTURE_ONLY');
  assert.equal((await batch({envelopes: [{...e1, amount: 1}]})).error.status, 'INVALID_ARGUMENT');
  assert.equal((await batch({envelopes: [{...e1, k: 'transaction'}]})).error.status, 'INVALID_ARGUMENT');
  denied(await batch({secret: token()}));
  const batchId = token();
  assert.equal((await batch({batchId})).result.headRev, 1);
  assert.equal((await batch({batchId})).result.duplicate, true);
  reason(await batch({}), 'HEAD_MOVED');
  reason(await batch({baseHeadRev: 1}), 'STALE_REV');
  assert.equal((await batch({baseHeadRev: 1, envelopes: [envelope({amount: 5}, e1.id, 2)]})).result.headRev, 2);
  const other = await account();
  const o = await activate(other);
  denied(await call('getEncryptedChanges', other, {...o, walletId, sinceRev: 0}));
  await call('putBackupKeyring', other, keyring(o, walletId, {password: token(), recovery: token()}));
  denied(await call('putEncryptedBatch', other, {...o, walletId, batchId: token(), baseHeadRev: 2,
    fixture: true, envelopes: [envelope({x: 1})]}));
  const changes = (await call('getEncryptedChanges', user, {...a, walletId, sinceRev: 1})).result;
  assert.equal(changes.headRev, 2);
  assert.deepEqual(changes.envelopes.map(e => [e.id, e.rev]), [[e1.id, 2]]);
  // Everything the server holds for this wallet: no known plaintext value.
  const dump = [];
  for (const path of [`wallets/${walletId}`]) dump.push((await db.doc(path).get()).data());
  for (const col of ['entities', 'batches']) {
    (await db.collection(`wallets/${walletId}/${col}`).get()).docs.forEach(d => dump.push(d.data()));
  }
  (await db.collection(`accounts/${user.localId}/backupKeyrings`).get()).docs.forEach(d => dump.push(d.data()));
  const text = JSON.stringify(dump);
  for (const secret of ['1234567', 'Tiền chợ', 'bí mật', 'Ăn uống', 'Quỹ du lịch', '9876543', 'amount',
    'note', 'transaction', 'fund', 'local-']) {
    assert.equal(text.includes(secret), false, secret);
  }
  const entity = (await db.collection(`wallets/${walletId}/entities`).limit(1).get()).docs[0].data();
  assert.deepEqual(Object.keys(entity).sort(), ['aad', 'c', 'id', 'n', 'rev', 'serverRev', 'v']);
});

test('rate limits: repeated wrong recovery proofs / grant secrets lock the action', async () => {
  const user = await account();
  const a = await activate(user);
  const walletId = 'fixture-' + randomBytes(8).toString('hex');
  const proofs = {password: token(), recovery: token()};
  await call('putBackupKeyring', user, keyring(a, walletId, proofs));
  const recover = proof => call('recoverSession', user, {accountId: user.localId,
    installationId: randomUUID(), walletId, proofKind: 'recovery', proof});
  for (let i = 0; i < 5; i++) denied(await recover(token()));
  // Locked: even the right proof is refused, with no hint about closeness.
  reason(await recover(proofs.recovery), 'RATE_LIMITED');
  assert.equal(await allowed(user, a), true);
  const bId = randomUUID();
  const request = (await call('requestTakeover', user, {accountId: user.localId, installationId: bId})).result;
  for (let i = 0; i < 5; i++) {
    denied(await call('completeTakeover', user, {accountId: user.localId, installationId: bId,
      requestId: request.requestId, requestSecret: token()}));
  }
  reason(await call('completeTakeover', user, {accountId: user.localId, installationId: bId,
    requestId: request.requestId, requestSecret: request.requestSecret}), 'RATE_LIMITED');
  for (let i = 0; i < 4; i++) {
    await call('requestTakeover', user, {accountId: user.localId, installationId: randomUUID()});
  }
  reason(await call('requestTakeover', user, {accountId: user.localId, installationId: randomUUID()}),
    'RATE_LIMITED');
});

test('Firestore REST Rules deny self promotion, reads and alternate cloud writes', async () => {
  const user = await account();
  await activate(user);
  for (const path of [`accounts/${user.localId}/session/current`, `accounts/${user.localId}/backupKeyrings/x`,
    `accounts/${user.localId}/session/limits`,
    'wallets/test', 'wallets/test/entities/test', 'wallets/test/transactions/test']) {
    for (const method of ['GET', 'PATCH']) {
      const response = await fetch(`http://127.0.0.1:8080/v1/projects/${project}/databases/(default)/documents/${path}`, {
        method, headers: {Authorization: `Bearer ${user.idToken}`, 'Content-Type': 'application/json'},
        ...(method === 'PATCH' ? {body: JSON.stringify({fields: {generation: {integerValue: '999'}}})} : {}),
      });
      assert.equal(response.status, 403);
    }
  }
});
