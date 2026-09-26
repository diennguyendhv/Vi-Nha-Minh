'use strict';
// P8.2 — explicit Personal Wallet claim (emulator only).
const {test} = require('node:test');
const assert = require('node:assert/strict');
const {randomUUID, randomBytes} = require('node:crypto');
const {initializeApp} = require('firebase-admin/app');
const {getFirestore} = require('firebase-admin/firestore');
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
function staleSignIn(user) {
  const [header, payload] = user.idToken.split('.');
  const claims = JSON.parse(Buffer.from(payload, 'base64url').toString());
  claims.auth_time -= 24 * 3600;
  return {...user, idToken: `${header}.${Buffer.from(JSON.stringify(claims)).toString('base64url')}.`};
}
async function call(name, user, data) {
  const response = await fetch(`http://127.0.0.1:5001/${project}/us-central1/${name}`, {
    method: 'POST', headers: {'Content-Type': 'application/json',
      ...(user ? {Authorization: `Bearer ${user.idToken}`} : {})},
    body: JSON.stringify({data}),
  });
  return response.json();
}
const denied = response => assert.equal(response.error?.status, 'PERMISSION_DENIED', JSON.stringify(response));
const reason = (response, expected) =>
  assert.equal(response.error?.details?.reason, expected, JSON.stringify(response));
const invalid = response => assert.equal(response.error?.status, 'INVALID_ARGUMENT', JSON.stringify(response));
async function activate(user, installationId = randomUUID()) {
  const response = await call('activateSession', user,
    {accountId: user.localId, installationId, confirm: true});
  assert.ok(response.result?.secret, JSON.stringify(response));
  return {accountId: user.localId, installationId, ...response.result};
}
const b = n => randomBytes(n).toString('base64');
const token = () => randomBytes(32).toString('base64url');
/** Exactly what the app sends: P7.1 credential + ownership metadata, nothing else. */
const claim = (credential, walletId, extra = {}) => ({...credential, walletId, selfMemberId: 'chong',
  membersMinimalMetadata: [{memberId: 'vo'}, {memberId: 'chong'}], payloadSchema: 10,
  cryptoVersion: 1, environment: 'dev', claimRequestId: randomUUID(), ...extra});
const abandon = (credential, walletId, claimed) => ({...credential, walletId,
  selfMemberId: claimed.selfMemberId, claimRequestId: claimed.claimRequestId});
async function snapshotOf(uid, walletId) {
  const wallet = (await db.doc(`wallets/${walletId}`).get()).data();
  const memberships = (await db.collection(`wallets/${walletId}/memberships`).get()).docs.map(d => [d.id, d.data()]);
  const index = (await db.doc(`accounts/${uid}/walletIndex/personal`).get()).data();
  const subcollections = (await db.doc(`wallets/${walletId}`).listCollections()).map(c => c.id).sort();
  return {wallet, memberships, index, subcollections};
}

test('claim writes ownership metadata only, exactly once; retries are idempotent', async () => {
  const user = await account();
  const a = await activate(user);
  const walletId = randomUUID();
  // Financial or unknown fields are rejected outright, never stored.
  invalid(await call('claimWallet', user, claim(a, walletId, {amount: 1234567})));
  invalid(await call('claimWallet', user, claim(a, walletId,
    {membersMinimalMetadata: [{memberId: 'vo', label: 'Vợ'}, {memberId: 'chong'}]})));
  invalid(await call('claimWallet', user, claim(a, 'fixture-abc')));
  invalid(await call('claimWallet', user, claim(a, walletId, {selfMemberId: 'ai-do'})));
  invalid(await call('claimWallet', user, claim(a, walletId,
    {membersMinimalMetadata: [{memberId: 'a'}, {memberId: 'b'}, {memberId: 'chong'}]})));
  invalid(await call('claimWallet', user, claim(a, walletId, {cryptoVersion: 2})));
  reason(await call('claimWallet', user, claim(a, walletId, {environment: 'prod'})), 'ENVIRONMENT_MISMATCH');
  assert.equal((await db.doc(`wallets/${walletId}`).get()).exists, false);

  const request = claim(a, walletId);
  const first = (await call('claimWallet', user, request)).result;
  assert.deepEqual(first, {claimed: true, idempotent: false, walletId, selfMemberId: 'chong',
    claimRequestId: request.claimRequestId, headRev: 0, backupState: null, checkpointRev: null});
  const before = await snapshotOf(user.localId, walletId);
  assert.deepEqual(Object.keys(before.wallet).sort(), ['claimRequestId', 'claimedAt', 'cryptoVersion',
    'environment', 'headRev', 'kind', 'memberIds', 'ownerAccountId', 'payloadSchema', 'selfMemberId', 'state']);
  assert.equal(before.wallet.ownerAccountId, user.localId);
  assert.equal(before.wallet.state, 'CLAIMED');
  assert.deepEqual(before.wallet.memberIds, ['chong', 'vo']);
  assert.deepEqual(before.memberships.map(([id, m]) => [id, m.role, m.status, m.memberId]),
    [[user.localId, 'OWNER', 'ACTIVE', 'chong']]);
  assert.equal(before.index.walletId, walletId);
  // Nothing financial: no entities/batches, no session secret, no labels.
  assert.deepEqual(before.subcollections, ['memberships']);
  assert.equal(JSON.stringify(before).includes(a.secret), false);

  // Double tap / timeout after commit: same request ⇒ same answer, no new writes.
  const again = (await call('claimWallet', user, request)).result;
  assert.equal(again.idempotent, true);
  assert.equal(again.claimRequestId, request.claimRequestId);
  // App lost its CLAIMING row and re-claimed with a new id: compatible ⇒ original claim.
  const compatible = (await call('claimWallet', user, claim(a, walletId))).result;
  assert.equal(compatible.idempotent, true);
  assert.equal(compatible.claimRequestId, request.claimRequestId);
  // Order of members is irrelevant; a stale sign-in may replay a committed claim.
  assert.equal((await call('claimWallet', staleSignIn(user), claim(a, walletId,
    {membersMinimalMetadata: [{memberId: 'chong'}, {memberId: 'vo'}]}))).result.idempotent, true);
  assert.deepEqual(await snapshotOf(user.localId, walletId), before);

  reason(await call('claimWallet', user, claim(a, walletId, {selfMemberId: 'vo'})), 'SELF_MEMBER_MISMATCH');
  reason(await call('claimWallet', user, claim(a, walletId,
    {membersMinimalMetadata: [{memberId: 'chong'}]})), 'CLAIM_MISMATCH');
  // Claimed wallets are not uploadable in P8.2 (encrypted backup is P8.3).
  reason(await call('putEncryptedBatch', user, {...a, walletId, batchId: token(), baseHeadRev: 0,
    fixture: true, envelopes: [{v: 1, id: token(), rev: 1, n: b(12), c: b(40), aad: 1}]}), 'BACKUP_NOT_ENABLED');
  assert.deepEqual(await snapshotOf(user.localId, walletId), before);

  const status = (await call('getWalletClaim', user, {...a, walletId})).result;
  assert.equal(status.ownedByYou, true);
  assert.equal(status.selfMemberId, 'chong');
  assert.deepEqual((await call('getWalletClaim', user, {...a, walletId: randomUUID()})).result, {claimed: false});
});

test('conflicts: other owner, second wallet per Account, pre-claim fixture doc', async () => {
  const owner = await account();
  const other = await account();
  const o = await activate(owner);
  const x = await activate(other);
  const walletId = randomUUID();
  await call('claimWallet', owner, claim(o, walletId));
  const before = await snapshotOf(owner.localId, walletId);
  reason(await call('claimWallet', other, claim(x, walletId)), 'ALREADY_CLAIMED');
  reason(await call('claimWallet', other, claim(x, walletId, {selfMemberId: 'vo'})), 'ALREADY_CLAIMED');
  assert.deepEqual((await call('getWalletClaim', other, {...x, walletId})).result,
    {claimed: true, ownedByYou: false});
  reason(await call('claimWallet', owner, claim(o, randomUUID())), 'ACCOUNT_HAS_WALLET');
  reason(await call('abandonClaim', other, abandon(x, walletId, before.wallet)), 'ALREADY_CLAIMED');
  assert.deepEqual(await snapshotOf(owner.localId, walletId), before);
  assert.equal((await db.doc(`accounts/${other.localId}/walletIndex/personal`).get()).exists, false);
  // A backup document that predates claims is never silently converted.
  const legacy = randomUUID();
  await db.doc(`wallets/${legacy}`).set({ownerAccountId: other.localId, cryptoVersion: 1, fixture: true, headRev: 1});
  reason(await call('claimWallet', other, claim(x, legacy)), 'WALLET_NOT_CLAIMABLE');
});

test('races: exactly one authoritative claim, no duplicate ownership documents', async () => {
  // Two Accounts race the same walletId.
  const u1 = await account();
  const u2 = await account();
  const c1 = await activate(u1);
  const c2 = await activate(u2);
  const walletId = randomUUID();
  const results = await Promise.all([call('claimWallet', u1, claim(c1, walletId)),
    call('claimWallet', u2, claim(c2, walletId))]);
  const winners = results.filter(r => r.result?.claimed);
  assert.equal(winners.length, 1, JSON.stringify(results));
  reason(results.find(r => !r.result), 'ALREADY_CLAIMED');
  const owner = (await db.doc(`wallets/${walletId}`).get()).data().ownerAccountId;
  assert.ok([u1.localId, u2.localId].includes(owner));
  assert.equal((await db.collection(`wallets/${walletId}/memberships`).get()).size, 1);
  const loser = owner === u1.localId ? u2 : u1;
  assert.equal((await db.doc(`accounts/${loser.localId}/walletIndex/personal`).get()).exists, false);

  // One Account races two different wallets.
  const u3 = await account();
  const c3 = await activate(u3);
  const [w1, w2] = [randomUUID(), randomUUID()];
  const pair = await Promise.all([call('claimWallet', u3, claim(c3, w1)), call('claimWallet', u3, claim(c3, w2))]);
  assert.equal(pair.filter(r => r.result?.claimed).length, 1, JSON.stringify(pair));
  reason(pair.find(r => !r.result), 'ACCOUNT_HAS_WALLET');
  const won = (await db.doc(`accounts/${u3.localId}/walletIndex/personal`).get()).data().walletId;
  const lost = won === w1 ? w2 : w1;
  assert.equal((await db.doc(`wallets/${lost}`).get()).exists, false);

  // Same Account, same wallet, same request, parallel (double tap).
  const u4 = await account();
  const c4 = await activate(u4);
  const w4 = randomUUID();
  const request = claim(c4, w4);
  const taps = await Promise.all([1, 2, 3].map(() => call('claimWallet', u4, request)));
  assert.equal(taps.every(r => r.result?.claimed && r.result.claimRequestId === request.claimRequestId), true,
    JSON.stringify(taps));
  assert.equal(taps.filter(r => r.result.idempotent === false).length, 1);
  assert.equal((await db.collection(`wallets/${w4}/memberships`).get()).size, 1);
});

test('P7.1 boundary: stale, revoked, inactive or non-recent devices cannot claim', async () => {
  const user = await account();
  const a = await activate(user);
  // Recent sign-in required to CREATE ownership.
  reason(await call('claimWallet', staleSignIn(user), claim(a, randomUUID())), 'RECENT_LOGIN_REQUIRED');
  // Firebase Auth alone (second device, no active P7.1 session): denied.
  const bInstallation = randomUUID();
  denied(await call('claimWallet', user, claim({accountId: user.localId, installationId: bInstallation,
    generation: a.generation, epoch: a.epoch, secret: token()}, randomUUID())));
  denied(await call('claimWallet', user, claim({accountId: user.localId}, randomUUID())));
  // Another Account's credential / uid mismatch.
  const other = await account();
  denied(await call('claimWallet', other, claim(a, randomUUID())));
  // Stale device after approved takeover: A's old credential is dead.
  const request = (await call('requestTakeover', user, {accountId: user.localId, installationId: bInstallation})).result;
  await call('approveTakeover', user, {...a, requestId: request.requestId});
  const bSession = (await call('completeTakeover', user, {accountId: user.localId, installationId: bInstallation,
    requestId: request.requestId, requestSecret: request.requestSecret})).result;
  const bCred = {accountId: user.localId, installationId: bInstallation, ...bSession};
  const walletId = randomUUID();
  denied(await call('claimWallet', user, claim(a, walletId)));
  assert.equal((await db.doc(`wallets/${walletId}`).get()).exists, false);
  // Lost-device recovery revokes B; B is told DEVICE_REVOKED and cannot claim.
  const proofs = {password: token(), recovery: token()};
  const keyringWallet = 'fixture-' + randomBytes(8).toString('hex');
  await call('putBackupKeyring', user, {...bCred, walletId: keyringWallet, mode: 'create', cryptoVersion: 1,
    password: {salt: b(16), kdf: {alg: 'argon2id', v: 19, m: 65536, t: 3, p: 4, norm: 'NFC'}, nonce: b(12), wrapped: b(48)},
    recovery: {salt: b(32), kdf: {alg: 'hkdf-sha256'}, nonce: b(12), wrapped: b(48)},
    passwordProof: proofs.password, recoveryProof: proofs.recovery});
  const cInstallation = randomUUID();
  const recovered = (await call('recoverSession', user, {accountId: user.localId, installationId: cInstallation,
    walletId: keyringWallet, proofKind: 'recovery', proof: proofs.recovery})).result;
  reason(await call('claimWallet', user, claim(bCred, walletId)), 'DEVICE_REVOKED');
  assert.equal((await db.doc(`wallets/${walletId}`).get()).exists, false);
  // Only the current installation (C) can claim.
  const cCred = {accountId: user.localId, installationId: cInstallation, ...recovered};
  assert.equal((await call('claimWallet', user, claim(cCred, walletId))).result.claimed, true);
  // ...and a stale device cannot even replay/read the committed claim.
  denied(await call('claimWallet', user, claim(a, walletId)));
  reason(await call('getWalletClaim', user, {...bCred, walletId}), 'DEVICE_REVOKED');
});

test('abandonClaim: only before any backup, only by owner with the exact claim', async () => {
  const user = await account();
  const a = await activate(user);
  const walletId = randomUUID();
  const claimed = (await call('claimWallet', user, claim(a, walletId))).result;
  reason(await call('abandonClaim', staleSignIn(user), abandon(a, walletId, claimed)), 'RECENT_LOGIN_REQUIRED');
  reason(await call('abandonClaim', user, {...abandon(a, walletId, claimed), claimRequestId: randomUUID()}),
    'CLAIM_MISMATCH');
  reason(await call('abandonClaim', user, {...abandon(a, walletId, claimed), selfMemberId: 'vo'}), 'CLAIM_MISMATCH');
  denied(await call('abandonClaim', user, {...abandon(a, walletId, claimed), secret: token()}));
  invalid(await call('abandonClaim', user, {...abandon(a, walletId, claimed), note: 'x'}));
  assert.deepEqual((await call('abandonClaim', user, abandon(a, walletId, claimed))).result,
    {abandoned: true, alreadyAbsent: false});
  const gone = await snapshotOf(user.localId, walletId);
  assert.deepEqual(gone, {wallet: undefined, memberships: [], index: undefined, subcollections: []});
  // Retry after commit is harmless.
  assert.equal((await call('abandonClaim', user, abandon(a, walletId, claimed))).result.alreadyAbsent, true);
  // The Account may claim again (e.g. after picking the wrong member).
  const reclaimed = (await call('claimWallet', user, claim(a, walletId, {selfMemberId: 'vo'}))).result;
  assert.equal(reclaimed.selfMemberId, 'vo');

  // Once backup has started (headRev > 0 or any encrypted entity) abandon is refused.
  await db.doc(`wallets/${walletId}`).update({headRev: 1});
  reason(await call('abandonClaim', user, abandon(a, walletId, reclaimed)), 'BACKUP_STARTED');
  await db.doc(`wallets/${walletId}`).update({headRev: 0});
  await db.doc(`wallets/${walletId}/entities/${token()}`).set({v: 1});
  reason(await call('abandonClaim', user, abandon(a, walletId, reclaimed)), 'BACKUP_STARTED');
  assert.equal((await db.doc(`wallets/${walletId}`).get()).exists, true);
  assert.equal((await db.doc(`accounts/${user.localId}/walletIndex/personal`).get()).data().walletId, walletId);
});

test('Rules: clients can neither read nor write claim documents directly', async () => {
  const user = await account();
  const a = await activate(user);
  const walletId = randomUUID();
  await call('claimWallet', user, claim(a, walletId));
  for (const path of [`wallets/${walletId}`, `wallets/${walletId}/memberships/${user.localId}`,
    `accounts/${user.localId}/walletIndex/personal`]) {
    for (const method of ['GET', 'PATCH', 'DELETE']) {
      const response = await fetch(`http://127.0.0.1:8080/v1/projects/${project}/databases/(default)/documents/${path}`, {
        method, headers: {Authorization: `Bearer ${user.idToken}`, 'Content-Type': 'application/json'},
        ...(method === 'PATCH' ? {body: JSON.stringify({fields: {ownerAccountId: {stringValue: 'x'}}})} : {}),
      });
      assert.equal(response.status, 403, `${method} ${path}`);
    }
  }
  assert.equal((await db.doc(`wallets/${walletId}`).get()).data().ownerAccountId, user.localId);
});
