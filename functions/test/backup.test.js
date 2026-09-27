'use strict';
// P8.3/P8.4 — encrypted backup of a CLAIMED wallet (emulator only).
const {test} = require('node:test');
const assert = require('node:assert/strict');
const {randomUUID, randomBytes} = require('node:crypto');
const {initializeApp} = require('firebase-admin/app');
const {getFirestore} = require('firebase-admin/firestore');
const project = 'demo-homewallet-p7';
if (!process.env.FIRESTORE_EMULATOR_HOST || !process.env.FIREBASE_AUTH_EMULATOR_HOST) {
  throw new Error('Emulators required; never run against live Firebase');
}
initializeApp({projectId: project}, 'backup-test');
const db = getFirestore(require('firebase-admin/app').getApp('backup-test'));
async function account() {
  const response = await fetch('http://127.0.0.1:9099/identitytoolkit.googleapis.com/v1/accounts:signUp?key=fake', {
    method: 'POST', headers: {'Content-Type': 'application/json'},
    body: JSON.stringify({returnSecureToken: true}),
  });
  assert.equal(response.status, 200);
  return response.json();
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
const denied = r => assert.equal(r.error?.status, 'PERMISSION_DENIED', JSON.stringify(r));
const reason = (r, expected) => assert.equal(r.error?.details?.reason, expected, JSON.stringify(r));
const invalid = r => assert.equal(r.error?.status, 'INVALID_ARGUMENT', JSON.stringify(r));
const ok = r => { assert.ok(r.result, JSON.stringify(r)); return r.result; };
async function activate(user, installationId = randomUUID()) {
  const r = ok(await call('activateSession', user, {accountId: user.localId, installationId, confirm: true}));
  return {accountId: user.localId, installationId, ...r};
}
const b = n => randomBytes(n).toString('base64');
const token = () => randomBytes(32).toString('base64url');
const env = (rev, extra = {}) => ({v: 1, id: token(), rev, n: b(12), c: b(200), aad: 1, ...extra});
async function claimed() {
  const user = await account();
  const cred = await activate(user);
  const walletId = randomUUID();
  ok(await call('claimWallet', user, {...cred, walletId, selfMemberId: 'm-a',
    membersMinimalMetadata: [{memberId: 'm-a'}, {memberId: 'm-b'}], payloadSchema: 11,
    cryptoVersion: 1, environment: 'dev', claimRequestId: randomUUID()}));
  const proofs = {password: token(), recovery: token()};
  return {user, cred, walletId, proofs};
}
const keyring = (cred, walletId, proofs) => ({...cred, walletId, mode: 'create', cryptoVersion: 1,
  password: {salt: b(16), kdf: {alg: 'argon2id', v: 19, m: 65536, t: 3, p: 4, norm: 'NFC'}, nonce: b(12), wrapped: b(48)},
  recovery: {salt: b(32), kdf: {alg: 'hkdf-sha256'}, nonce: b(12), wrapped: b(48)},
  passwordProof: proofs.password, recoveryProof: proofs.recovery});
const batch = (cred, walletId, baseHeadRev, envelopes, extra = {}) =>
  ({...cred, walletId, batchId: token(), baseHeadRev, envelopes, ...extra});

test('enableBackup: owner + session + keyring; idempotent; metadata only', async () => {
  const {user, cred, walletId, proofs} = await claimed();
  invalid(await call('enableBackup', user, {...cred, walletId, extra: 1}));
  reason(await call('enableBackup', user, {...cred, walletId}), 'NO_KEYRING');
  reason(await call('enableBackup', user, {...cred, walletId: randomUUID()}), 'NOT_CLAIMED');
  ok(await call('putBackupKeyring', user, keyring(cred, walletId, proofs)));
  // Before enabling, a claimed wallet still refuses ciphertext.
  reason(await call('putEncryptedBatch', user, batch(cred, walletId, 0, [env(1)])), 'BACKUP_NOT_ENABLED');
  denied(await call('enableBackup', user, {...cred, secret: token(), walletId}));
  const other = await account();
  const otherCred = await activate(other);
  denied(await call('enableBackup', other, {...otherCred, walletId}));
  assert.deepEqual(ok(await call('enableBackup', user, {...cred, walletId})), {backupState: 'SEEDING', headRev: 0});
  assert.deepEqual(ok(await call('enableBackup', user, {...cred, walletId})), {backupState: 'SEEDING', headRev: 0});
  const w = (await db.doc(`wallets/${walletId}`).get()).data();
  assert.equal(w.backupState, 'SEEDING');
});

test('batches: CAS, idempotent receipt, STALE_REV, checkpoint ⇒ COMPLETE, shape limits', async () => {
  const {user, cred, walletId, proofs} = await claimed();
  ok(await call('putBackupKeyring', user, keyring(cred, walletId, proofs)));
  ok(await call('enableBackup', user, {...cred, walletId}));
  const first = [env(1), env(1)];
  const req = batch(cred, walletId, 0, first);
  assert.deepEqual(ok(await call('putEncryptedBatch', user, req)), {headRev: 1, duplicate: false});
  // Timeout after commit ⇒ same batchId ⇒ receipt, no second write.
  assert.deepEqual(ok(await call('putEncryptedBatch', user, req)), {headRev: 1, duplicate: true});
  reason(await call('putEncryptedBatch', user, batch(cred, walletId, 0, [env(1)])), 'HEAD_MOVED');
  reason(await call('putEncryptedBatch', user, batch(cred, walletId, 1, [{...first[0], rev: 1}])), 'STALE_REV');
  // Malformed / oversized / leaking visible metadata ⇒ rejected before any write.
  for (const bad of [
    [env(2, {kind: 'transaction'})], [env(2, {n: b(16)})], [env(2, {c: b(12289)})],
    [env(2, {v: 2})], [env(2, {id: 'tx-1'})], [env(0)], [], Array.from({length: 101}, () => env(2)),
  ]) invalid(await call('putEncryptedBatch', user, batch(cred, walletId, 1, bad)));
  invalid(await call('putEncryptedBatch', user, batch(cred, walletId, 1, [env(2)], {checkpoint: 'yes'})));
  assert.equal((await db.doc(`wallets/${walletId}`).get()).data().headRev, 1);
  // Draining batch with manifest ⇒ checkpoint.
  assert.equal(ok(await call('putEncryptedBatch', user,
    batch(cred, walletId, 1, [env(2)], {checkpoint: true}))).headRev, 2);
  const w = (await db.doc(`wallets/${walletId}`).get()).data();
  assert.equal(w.backupState, 'COMPLETE');
  assert.equal(w.checkpointRev, 2);
  // Entities hold exactly the opaque envelope + serverRev.
  const docs = (await db.collection(`wallets/${walletId}/entities`).get()).docs.map(d => d.data());
  assert.equal(docs.length, 3);
  for (const d of docs) assert.deepEqual(Object.keys(d).sort(), ['aad', 'c', 'id', 'n', 'rev', 'serverRev', 'v']);
  const changes = ok(await call('getEncryptedChanges', user, {...cred, walletId, sinceRev: 0}));
  assert.equal(changes.headRev, 2);
  assert.equal(changes.throughRev, 2);
  assert.equal(changes.more, false);
  assert.equal(changes.checkpointRev, 2);
  assert.equal(changes.envelopes.length, 3);
  assert.equal(ok(await call('getEncryptedChanges', user, {...cred, walletId, sinceRev: 2})).envelopes.length, 0);
});

test('pages never split a batch (cursor cannot skip half a batch)', async () => {
  const {user, cred, walletId, proofs} = await claimed();
  ok(await call('putBackupKeyring', user, keyring(cred, walletId, proofs)));
  ok(await call('enableBackup', user, {...cred, walletId}));
  // 3 batches of 90 ⇒ 270 envelopes; a 200 page would cut batch 3.
  for (let head = 0; head < 3; head++) {
    ok(await call('putEncryptedBatch', user,
      batch(cred, walletId, head, Array.from({length: 90}, () => env(head + 1)))));
  }
  const p1 = ok(await call('getEncryptedChanges', user, {...cred, walletId, sinceRev: 0}));
  assert.equal(p1.more, true);
  assert.equal(p1.throughRev, 2);
  assert.equal(p1.envelopes.length, 180);
  const p2 = ok(await call('getEncryptedChanges', user, {...cred, walletId, sinceRev: p1.throughRev}));
  assert.equal(p2.more, false);
  assert.equal(p2.throughRev, 3);
  assert.equal(p2.envelopes.length, 90);
});

test('non-member, stale and revoked devices cannot read or write', async () => {
  const {user, cred, walletId, proofs} = await claimed();
  ok(await call('putBackupKeyring', user, keyring(cred, walletId, proofs)));
  ok(await call('enableBackup', user, {...cred, walletId}));
  ok(await call('putEncryptedBatch', user, batch(cred, walletId, 0, [env(1)])));
  const x = await account();
  const xCred = await activate(x);
  denied(await call('putEncryptedBatch', x, batch(xCred, walletId, 1, [env(2)])));
  denied(await call('getEncryptedChanges', x, {...xCred, walletId, sinceRev: 0}));
  // Uid/credential mismatch.
  denied(await call('getEncryptedChanges', x, {...cred, walletId, sinceRev: 0}));
  // Lost-device recovery from a new installation revokes the old one.
  const recovered = ok(await call('recoverSession', user, {accountId: user.localId,
    installationId: randomUUID(), walletId, proofKind: 'recovery', proof: proofs.recovery}));
  reason(await call('putEncryptedBatch', user, batch(cred, walletId, 1, [env(2)])), 'DEVICE_REVOKED');
  reason(await call('getEncryptedChanges', user, {...cred, walletId, sinceRev: 0}), 'DEVICE_REVOKED');
  assert.equal((await db.doc(`wallets/${walletId}`).get()).data().headRev, 1);
  assert.ok(recovered.secret);
});

test('rotateRecovery: same BMK slot swap, old proof dead, password + ciphertext untouched, idempotent', async () => {
  const {user, cred, walletId, proofs} = await claimed();
  ok(await call('putBackupKeyring', user, keyring(cred, walletId, proofs)));
  ok(await call('enableBackup', user, {...cred, walletId}));
  ok(await call('putEncryptedBatch', user, batch(cred, walletId, 0, [env(1)], {checkpoint: true})));
  const entityDocs = async () => (await db.collection(`wallets/${walletId}/entities`).get())
    .docs.map(d => JSON.stringify({id: d.id, ...d.data()})).sort();
  const entitiesBefore = await entityDocs();
  const kr = () => db.doc(`accounts/${user.localId}/backupKeyrings/${walletId}`).get().then(d => d.data());
  const before = await kr();
  const slot = {salt: b(32), kdf: {alg: 'hkdf-sha256'}, nonce: b(12), wrapped: b(48)};
  const rotate = (extra = {}) => ({...cred, walletId, mode: 'rotateRecovery', expectedRev: 1,
    recovery: slot, recoveryProof: token(), rotationId: token(), ...extra});
  const req = rotate();
  invalid(await call('putBackupKeyring', user, {...req, password: before.password}));
  invalid(await call('putBackupKeyring', user, {...req, rotationId: 'short'}));
  // Other account / stale credential: denied, nothing changes.
  const x = await account();
  const xCred = await activate(x);
  reason(await call('putBackupKeyring', x, {...req, ...xCred}), 'NO_KEYRING');
  denied(await call('putBackupKeyring', user, {...req, secret: token()}));
  assert.equal((await kr()).rev, 1);

  assert.deepEqual(ok(await call('putBackupKeyring', user, req)), {rev: 2});
  // Lost response → same request again = receipt, no second swap.
  assert.deepEqual(ok(await call('putBackupKeyring', user, req)), {rev: 2});
  reason(await call('putBackupKeyring', user, {...req, recoveryProof: token()}), 'KEYRING_CHANGED');
  reason(await call('putBackupKeyring', user, rotate()), 'KEYRING_CHANGED'); // stale expectedRev
  const after = await kr();
  assert.equal(after.rev, 2);
  assert.deepEqual(after.password, before.password);
  assert.equal(after.passwordProofHash, before.passwordProofHash);
  assert.deepEqual(after.recovery, slot);
  assert.notEqual(after.recoveryProofHash, before.recoveryProofHash);
  const served = ok(await call('getBackupKeyring', user, {...cred, walletId}));
  assert.deepEqual(Object.keys(served).sort(), ['cryptoVersion', 'password', 'recovery', 'rev']);
  assert.deepEqual(await entityDocs(), entitiesBefore, 'no envelope rewritten');
  assert.equal((await db.doc(`wallets/${walletId}`).get()).data().headRev, 1);
  // Old Recovery Key proof is dead immediately; new one and the password still work.
  const recover = (kind, proof) => call('recoverSession', user, {accountId: user.localId,
    installationId: randomUUID(), walletId, proofKind: kind, proof});
  denied(await recover('recovery', proofs.recovery));
  ok(await recover('recovery', req.recoveryProof));
  ok(await recover('password', proofs.password));
});

test('Rules stay deny-all for direct client access', async () => {
  const {user, walletId} = await claimed();
  const url = `http://127.0.0.1:8080/v1/projects/${project}/databases/(default)/documents/wallets/${walletId}`;
  const read = await fetch(url, {headers: {Authorization: `Bearer ${user.idToken}`}});
  assert.equal(read.status, 403);
  const write = await fetch(`${url}/entities/x`, {method: 'PATCH',
    headers: {Authorization: `Bearer ${user.idToken}`, 'Content-Type': 'application/json'},
    body: JSON.stringify({fields: {c: {stringValue: 'x'}}})});
  assert.equal(write.status, 403);
});

// 2026-09-27: one Firebase project = PRODUCTION. Accident guards.
test('clientEnv: missing or other-environment client is refused before anything runs', async () => {
  const user = await account();
  const raw = async data => (await fetch(`http://127.0.0.1:5001/${project}/us-central1/activateSession`, {
    method: 'POST', headers: {'Content-Type': 'application/json', Authorization: `Bearer ${user.idToken}`},
    body: JSON.stringify({data}),
  })).json();
  const base = {accountId: user.localId, installationId: randomUUID(), confirm: true};
  reason(await raw(base), 'CLIENT_ENVIRONMENT');
  reason(await raw({...base, clientEnv: 'prod'}), 'CLIENT_ENVIRONMENT');
  assert.equal((await db.doc(`accounts/${user.localId}/session/current`).get()).exists, false);
  ok(await raw({...base, clientEnv: 'dev'}));
});

test('wallet claimed by ANOTHER environment is frozen: no ciphertext, not offered for restore', async () => {
  const {user, cred, walletId, proofs} = await claimed();
  ok(await call('putBackupKeyring', user, keyring(cred, walletId, proofs)));
  ok(await call('enableBackup', user, {...cred, walletId}));
  ok(await call('putEncryptedBatch', user, batch(cred, walletId, 0, [env(1)], {checkpoint: true})));
  assert.deepEqual(ok(await call('listBackupWallets', user, {...cred})).walletIds, [walletId]);
  // Same document as if it had been claimed while the project served another environment.
  await db.doc(`wallets/${walletId}`).update({environment: 'legacy-other'});
  reason(await call('getEncryptedChanges', user, {...cred, walletId, sinceRev: 0}), 'ENVIRONMENT_MISMATCH');
  reason(await call('putEncryptedBatch', user, batch(cred, walletId, 1, [env(1)])), 'ENVIRONMENT_MISMATCH');
  reason(await call('enableBackup', user, {...cred, walletId}), 'ENVIRONMENT_MISMATCH');
  reason(await call('promoteToFamily', user, {...cred, walletId}), 'ENVIRONMENT_MISMATCH');
  assert.deepEqual(ok(await call('listBackupWallets', user, {...cred})).walletIds, []);
  // Frozen, not deleted: the ciphertext is still there.
  assert.equal((await db.collection(`wallets/${walletId}/entities`).get()).size, 1);
});
