'use strict';
// P10 Family v1 — invitation, membership binding, key-share storage (emulator only).
const {test} = require('node:test');
const assert = require('node:assert/strict');
const {randomUUID, randomBytes, createHash} = require('node:crypto');
const {initializeApp, getApp} = require('firebase-admin/app');
const {getFirestore, Timestamp} = require('firebase-admin/firestore');
const project = 'demo-homewallet-p7';
if (!process.env.FIRESTORE_EMULATOR_HOST || !process.env.FIREBASE_AUTH_EMULATOR_HOST) {
  throw new Error('Emulators required; never run against live Firebase');
}
initializeApp({projectId: project}, 'family-test');
const db = getFirestore(getApp('family-test'));
/** Emulator account with an email; `verified` forges email_verified in the (unsigned) emulator token. */
async function account(verified = true) {
  const email = `u${randomBytes(6).toString('hex')}@example.test`;
  const response = await fetch('http://127.0.0.1:9099/identitytoolkit.googleapis.com/v1/accounts:signUp?key=fake', {
    method: 'POST', headers: {'Content-Type': 'application/json'},
    body: JSON.stringify({email, password: 'emulator-only-pw', returnSecureToken: true}),
  });
  const user = await response.json();
  const [header, payload] = user.idToken.split('.');
  const claims = JSON.parse(Buffer.from(payload, 'base64url').toString());
  claims.email_verified = verified;
  return {...user, email, idToken: `${header}.${Buffer.from(JSON.stringify(claims)).toString('base64url')}.`};
}
function stale(user) {
  const [header, payload] = user.idToken.split('.');
  const claims = JSON.parse(Buffer.from(payload, 'base64url').toString());
  claims.auth_time -= 24 * 3600;
  return {...user, idToken: `${header}.${Buffer.from(JSON.stringify(claims)).toString('base64url')}.`};
}
async function call(name, user, data) {
  const response = await fetch(`http://127.0.0.1:5001/${project}/us-central1/${name}`, {
    method: 'POST', headers: {'Content-Type': 'application/json', Authorization: `Bearer ${user.idToken}`},
    body: JSON.stringify({data: data && typeof data === 'object' && !Array.isArray(data)
      ? {clientEnv: 'dev', ...data} : data}),
  });
  return response.json();
}
const ok = r => { assert.ok(r.result, JSON.stringify(r)); return r.result; };
const reason = (r, expected) => assert.equal(r.error?.details?.reason, expected, JSON.stringify(r));
const denied = r => assert.equal(r.error?.status, 'PERMISSION_DENIED', JSON.stringify(r));
async function activate(user, installationId = randomUUID()) {
  return {accountId: user.localId, installationId,
    ...ok(await call('activateSession', user, {accountId: user.localId, installationId, confirm: true}))};
}
const b = n => randomBytes(n).toString('base64');
const token = () => randomBytes(32).toString('base64url');
const env = rev => ({v: 1, id: token(), rev, n: b(12), c: b(200), aad: 1});
const pubHash = k => createHash('sha256').update(Buffer.from(k, 'base64')).digest('hex');

/** A (Owner) claims a wallet with members m-a (A) and m-b; backup enabled; promoted to Family. */
async function familyWallet({promote = true} = {}) {
  const a = await account();
  const aCred = await activate(a);
  const walletId = randomUUID();
  ok(await call('claimWallet', a, {...aCred, walletId, selfMemberId: 'm-a',
    membersMinimalMetadata: [{memberId: 'm-a'}, {memberId: 'm-b'}], payloadSchema: 11,
    cryptoVersion: 1, environment: 'dev', claimRequestId: randomUUID()}));
  ok(await call('putBackupKeyring', a, {...aCred, walletId, mode: 'create', cryptoVersion: 1,
    password: {salt: b(16), kdf: {alg: 'argon2id', v: 19, m: 65536, t: 3, p: 4, norm: 'NFC'}, nonce: b(12), wrapped: b(48)},
    recovery: {salt: b(32), kdf: {alg: 'hkdf-sha256'}, nonce: b(12), wrapped: b(48)},
    passwordProof: token(), recoveryProof: token()}));
  ok(await call('enableBackup', a, {...aCred, walletId}));
  if (promote) ok(await call('promoteToFamily', a, {...aCred, walletId}));
  return {a, aCred, walletId};
}

test('Owner invites B for the Wife member; only B (verified email) can accept, exactly once', async () => {
  const {a, aCred, walletId} = await familyWallet();
  const bUser = await account();
  const bCred = await activate(bUser);
  const x = await account();
  const xCred = await activate(x);
  // Idempotent promotion keeps the same wallet.
  assert.equal(ok(await call('promoteToFamily', a, {...aCred, walletId})).idempotent, true);
  const {token: t} = ok(await call('createFamilyInvite', a,
    {...aCred, walletId, memberId: 'm-b', inviteeEmail: bUser.email.toUpperCase()}));
  const stored = (await db.collection('familyInvites').where('walletId', '==', walletId).get()).docs;
  assert.equal(stored.length, 1);
  assert.equal(JSON.stringify(stored[0].data()).includes(t), false, 'only the token hash is stored');
  // Wrong Account cannot preview or accept.
  reason(await call('getFamilyInvite', x, {...xCred, token: t}), 'INVITE_INVALID');
  reason(await call('acceptFamilyInvite', x, {...xCred, token: t, publicKey: b(32)}), 'INVITE_INVALID');
  // B previews then explicitly accepts with its device public key.
  assert.deepEqual(Object.keys(ok(await call('getFamilyInvite', bUser, {...bCred, token: t}))).sort(),
    ['expiresAt', 'memberId', 'walletId']);
  const bKey = b(32);
  assert.deepEqual(ok(await call('acceptFamilyInvite', bUser, {...bCred, token: t, publicKey: bKey})),
    {walletId, memberId: 'm-b', ownerAccountId: a.localId});
  reason(await call('acceptFamilyInvite', bUser, {...bCred, token: t, publicKey: bKey}), 'INVITE_INVALID');
  const claim = ok(await call('getWalletClaim', bUser, {...bCred, walletId}));
  assert.equal(claim.isMember, true);
  assert.equal(claim.ownedByYou, false);
  assert.equal(claim.selfMemberId, 'm-b');
  assert.equal(claim.kind, 'family');
  // Both can exchange ciphertext; X cannot.
  ok(await call('putEncryptedBatch', a, {...aCred, walletId, batchId: token(), baseHeadRev: 0, envelopes: [env(1)]}));
  ok(await call('putEncryptedBatch', bUser, {...bCred, walletId, batchId: token(), baseHeadRev: 1, envelopes: [env(2)]}));
  assert.equal(ok(await call('getEncryptedChanges', bUser, {...bCred, walletId, sinceRev: 0})).envelopes.length, 2);
  denied(await call('getEncryptedChanges', x, {...xCred, walletId, sinceRev: 0}));
  denied(await call('putEncryptedBatch', x, {...xCred, walletId, batchId: token(), baseHeadRev: 2, envelopes: [env(3)]}));
  // Key share: Owner pins the exact public key it verified.
  const members = ok(await call('getFamilyMembers', a, {...aCred, walletId})).members;
  const bm = members.find(m => m.accountId === bUser.localId);
  assert.equal(bm.publicKey, bKey);
  // The device key is bound to the installation that accepted.
  assert.equal(bm.keyInstallationId, bCred.installationId);
  const wrapped = {v: 1, epk: b(32), n: b(12), c: b(48)};
  const pin = {publicKeyHash: pubHash(bKey), keyInstallationId: bCred.installationId};
  reason(await call('getMemberKey', bUser, {...bCred, walletId}), 'KEY_NOT_SHARED');
  reason(await call('putMemberKey', a, {...aCred, walletId, memberAccountId: bUser.localId,
    ...pin, publicKeyHash: pubHash(b(32)), wrapped}), 'PUBLIC_KEY_CHANGED');
  reason(await call('putMemberKey', a, {...aCred, walletId, memberAccountId: bUser.localId,
    ...pin, keyInstallationId: randomUUID(), wrapped}), 'PUBLIC_KEY_CHANGED');
  denied(await call('putMemberKey', bUser, {...bCred, walletId, memberAccountId: bUser.localId,
    ...pin, wrapped}));
  ok(await call('putMemberKey', a, {...aCred, walletId, memberAccountId: bUser.localId, ...pin, wrapped}));
  assert.deepEqual(ok(await call('getMemberKey', bUser, {...bCred, walletId})),
    {wrapped, memberId: 'm-b', ownerAccountId: a.localId, keyInstallationId: bCred.installationId,
      publicKey: bKey});
  denied(await call('getMemberKey', x, {...xCred, walletId}));
  // The Owner is never served a Member key package.
  denied(await call('getMemberKey', a, {...aCred, walletId}));
  assert.deepEqual(ok(await call('getMyFamily', bUser, {...bCred})),
    {member: true, walletId, memberId: 'm-b', ownerAccountId: a.localId, hasKey: true,
      keyInstallationId: bCred.installationId});
  assert.deepEqual(ok(await call('getMyFamily', x, {...xCred})), {member: false});
  // Member cannot manage membership.
  denied(await call('createFamilyInvite', bUser, {...bCred, walletId, memberId: 'm-a', inviteeEmail: x.email}));
  denied(await call('revokeFamilyMember', bUser, {...bCred, walletId, memberAccountId: a.localId}));
  denied(await call('cancelFamilyInvite', bUser, {...bCred, walletId}));
  denied(await call('promoteToFamily', bUser, {...bCred, walletId}));
});

test('two writers: equal batch ids never cross-acknowledge; membership denial has NOT_MEMBER', async () => {
  const {a, aCred, walletId} = await familyWallet();
  const bUser = await account();
  const bCred = await activate(bUser);
  const t = ok(await call('createFamilyInvite', a, {...aCred, walletId, memberId: 'm-b', inviteeEmail: bUser.email})).token;
  ok(await call('acceptFamilyInvite', bUser, {...bCred, token: t, publicKey: b(32)}));
  const batchId = token();
  ok(await call('putEncryptedBatch', a, {...aCred, walletId, batchId, baseHeadRev: 0, envelopes: [env(1)]}));
  // Same writer retry => receipt; other writer, same id => explicit conflict, nothing stored.
  assert.equal(ok(await call('putEncryptedBatch', a, {...aCred, walletId, batchId, baseHeadRev: 0,
    envelopes: [env(1)]})).duplicate, true);
  reason(await call('putEncryptedBatch', bUser, {...bCred, walletId, batchId, baseHeadRev: 0,
    envelopes: [env(1)]}), 'BATCH_ID_CONFLICT');
  // Concurrent head: B still at 0 => HEAD_MOVED (must pull first; never overwrites A).
  reason(await call('putEncryptedBatch', bUser, {...bCred, walletId, batchId: token(), baseHeadRev: 0,
    envelopes: [env(1)]}), 'HEAD_MOVED');
  const x = await account();
  const xCred = await activate(x);
  reason(await call('getEncryptedChanges', x, {...xCred, walletId, sinceRev: 0}), 'NOT_MEMBER');
  // Remote-change signal registration: members only, token bound to the session installation.
  const fcm = `fcm_${randomBytes(24).toString('hex')}`;
  ok(await call('registerSyncSignal', bUser, {...bCred, walletId, token: fcm}));
  const bm = (await db.doc(`wallets/${walletId}/memberships/${bUser.localId}`).get()).data();
  assert.equal(bm.signalToken, fcm);
  assert.equal(bm.signalInstallationId, bCred.installationId);
  reason(await call('registerSyncSignal', x, {...xCred, walletId, token: fcm}), 'NOT_MEMBER');
  assert.equal((await call('registerSyncSignal', bUser, {...bCred, walletId, token: 'bad token!'})).error?.status,
    'INVALID_ARGUMENT');
  // A write still succeeds while signalling (FCM is skipped in the emulator).
  ok(await call('putEncryptedBatch', a, {...aCred, walletId, batchId: token(), baseHeadRev: 1, envelopes: [env(2)]}));
  ok(await call('revokeFamilyMember', a, {...aCred, walletId, memberAccountId: bUser.localId}));
  const revoked = (await db.doc(`wallets/${walletId}/memberships/${bUser.localId}`).get()).data();
  assert.equal(revoked.signalToken, null);
});

test('member device key: bound installation only; new installation re-registers, Owner re-wraps', async () => {
  const {a, aCred, walletId} = await familyWallet();
  const bUser = await account();
  const bCred = await activate(bUser);
  const t = ok(await call('createFamilyInvite', a, {...aCred, walletId, memberId: 'm-b', inviteeEmail: bUser.email})).token;
  const k1 = b(32);
  ok(await call('acceptFamilyInvite', bUser, {...bCred, token: t, publicKey: k1}));
  const wrapped = {v: 1, epk: b(32), n: b(12), c: b(48)};
  ok(await call('putMemberKey', a, {...aCred, walletId, memberAccountId: bUser.localId,
    publicKeyHash: pubHash(k1), keyInstallationId: bCred.installationId, wrapped}));
  // B moves to a new installation (P7.1 approved takeover).
  const next = randomUUID();
  const request = ok(await call('requestTakeover', bUser, {accountId: bUser.localId, installationId: next}));
  ok(await call('approveTakeover', bUser, {...bCred, requestId: request.requestId}));
  const bNew = {accountId: bUser.localId, installationId: next,
    ...ok(await call('completeTakeover', bUser, {accountId: bUser.localId, installationId: next,
      requestId: request.requestId, requestSecret: request.requestSecret}))};
  denied(await call('getMemberKey', bUser, {...bCred, walletId}));
  reason(await call('getMemberKey', bUser, {...bNew, walletId}), 'KEY_DEVICE_MISMATCH');
  reason(await call('registerMemberDeviceKey', stale(bUser), {...bNew, walletId, publicKey: b(32)}),
    'RECENT_LOGIN_REQUIRED');
  const k2 = b(32);
  ok(await call('registerMemberDeviceKey', bUser, {...bNew, walletId, publicKey: k2}));
  reason(await call('getMemberKey', bUser, {...bNew, walletId}), 'KEY_NOT_SHARED');
  // Old pin fails; Owner re-verifies the new fingerprint and wraps again.
  reason(await call('putMemberKey', a, {...aCred, walletId, memberAccountId: bUser.localId,
    publicKeyHash: pubHash(k1), keyInstallationId: bCred.installationId, wrapped}), 'PUBLIC_KEY_CHANGED');
  ok(await call('putMemberKey', a, {...aCred, walletId, memberAccountId: bUser.localId,
    publicKeyHash: pubHash(k2), keyInstallationId: next, wrapped}));
  assert.equal(ok(await call('getMemberKey', bUser, {...bNew, walletId})).keyInstallationId, next);
  // Owner cannot register a member key.
  denied(await call('registerMemberDeviceKey', a, {...aCred, walletId, publicKey: b(32)}));
});

test('invite guards: owner only, not self, not owner member, family only, verified email, expiry, max 2', async () => {
  const {a, aCred, walletId} = await familyWallet({promote: false});
  const bUser = await account();
  const bCred = await activate(bUser);
  reason(await call('createFamilyInvite', a, {...aCred, walletId, memberId: 'm-b', inviteeEmail: bUser.email}), 'NOT_FAMILY');
  ok(await call('promoteToFamily', a, {...aCred, walletId}));
  reason(await call('createFamilyInvite', stale(a), {...aCred, walletId, memberId: 'm-b', inviteeEmail: bUser.email}), 'RECENT_LOGIN_REQUIRED');
  reason(await call('createFamilyInvite', a, {...aCred, walletId, memberId: 'm-b', inviteeEmail: a.email}), 'SELF_INVITE');
  reason(await call('createFamilyInvite', a, {...aCred, walletId, memberId: 'm-a', inviteeEmail: bUser.email}), 'OWNER_MEMBER');
  reason(await call('createFamilyInvite', a, {...aCred, walletId, memberId: 'm-z', inviteeEmail: bUser.email}), 'UNKNOWN_MEMBER');
  denied(await call('createFamilyInvite', bUser, {...bCred, walletId, memberId: 'm-b', inviteeEmail: 'z@example.test'}));
  assert.equal((await call('createFamilyInvite', a, {...aCred, walletId, memberId: 'm-b', inviteeEmail: bUser.email,
    amount: 5})).error?.status, 'INVALID_ARGUMENT');
  // Unverified email cannot accept even with the right address.
  const unverified = await account(false);
  const uCred = await activate(unverified);
  const t0 = ok(await call('createFamilyInvite', a, {...aCred, walletId, memberId: 'm-b', inviteeEmail: unverified.email})).token;
  reason(await call('acceptFamilyInvite', unverified, {...uCred, token: t0, publicKey: b(32)}), 'EMAIL_NOT_VERIFIED');
  // A new invite supersedes the previous one.
  const t1 = ok(await call('createFamilyInvite', a, {...aCred, walletId, memberId: 'm-b', inviteeEmail: bUser.email})).token;
  const t2 = ok(await call('createFamilyInvite', a, {...aCred, walletId, memberId: 'm-b', inviteeEmail: bUser.email})).token;
  reason(await call('acceptFamilyInvite', bUser, {...bCred, token: t1, publicKey: b(32)}), 'INVITE_INVALID');
  // Expired.
  const doc = (await db.collection('familyInvites').where('walletId', '==', walletId)
    .where('status', '==', 'PENDING').get()).docs[0];
  await doc.ref.update({expiresAt: Timestamp.fromMillis(Date.now() - 1000)});
  reason(await call('acceptFamilyInvite', bUser, {...bCred, token: t2, publicKey: b(32)}), 'INVITE_INVALID');
  // Cancelled.
  const t3 = ok(await call('createFamilyInvite', a, {...aCred, walletId, memberId: 'm-b', inviteeEmail: bUser.email})).token;
  assert.equal(ok(await call('cancelFamilyInvite', a, {...aCred, walletId})).cancelled, true);
  reason(await call('acceptFamilyInvite', bUser, {...bCred, token: t3, publicKey: b(32)}), 'INVITE_INVALID');
  // Accept, then the Family is full and m-b is bound.
  const t4 = ok(await call('createFamilyInvite', a, {...aCred, walletId, memberId: 'm-b', inviteeEmail: bUser.email})).token;
  ok(await call('acceptFamilyInvite', bUser, {...bCred, token: t4, publicKey: b(32)}));
  const c = await account();
  reason(await call('createFamilyInvite', a, {...aCred, walletId, memberId: 'm-b', inviteeEmail: c.email}), 'FAMILY_FULL');
  const active = (await db.collection(`wallets/${walletId}/memberships`).where('status', '==', 'ACTIVE').get()).size;
  assert.equal(active, 2);
});

test('race: two Accounts with the same invite ⇒ exactly one membership; stale device denied', async () => {
  const {a, aCred, walletId} = await familyWallet();
  const bUser = await account();
  const bCred = await activate(bUser);
  const t = ok(await call('createFamilyInvite', a, {...aCred, walletId, memberId: 'm-b', inviteeEmail: bUser.email})).token;
  // Stale B device (another installation took over B's session) cannot accept.
  const bInstallation = randomUUID();
  const request = ok(await call('requestTakeover', bUser, {accountId: bUser.localId, installationId: bInstallation}));
  ok(await call('approveTakeover', bUser, {...bCred, requestId: request.requestId}));
  const bNew = {accountId: bUser.localId, installationId: bInstallation,
    ...ok(await call('completeTakeover', bUser, {accountId: bUser.localId, installationId: bInstallation,
      requestId: request.requestId, requestSecret: request.requestSecret}))};
  denied(await call('acceptFamilyInvite', bUser, {...bCred, token: t, publicKey: b(32)}));
  const results = await Promise.all([1, 2, 3].map(() =>
    call('acceptFamilyInvite', bUser, {...bNew, token: t, publicKey: b(32)})));
  assert.equal(results.filter(r => r.result).length, 1, JSON.stringify(results));
  const members = (await db.collection(`wallets/${walletId}/memberships`).get()).docs.map(d => d.data());
  assert.equal(members.filter(m => m.role === 'MEMBER').length, 1);
  assert.equal(members.filter(m => m.memberId === 'm-b').length, 1);
});

test('revoke: Member loses cloud access at once; Owner can bind another Account to the same member', async () => {
  const {a, aCred, walletId} = await familyWallet();
  const bUser = await account();
  const bCred = await activate(bUser);
  const t = ok(await call('createFamilyInvite', a, {...aCred, walletId, memberId: 'm-b', inviteeEmail: bUser.email})).token;
  ok(await call('acceptFamilyInvite', bUser, {...bCred, token: t, publicKey: b(32)}));
  denied(await call('revokeFamilyMember', bUser, {...bCred, walletId, memberAccountId: bUser.localId}));
  ok(await call('revokeFamilyMember', a, {...aCred, walletId, memberAccountId: bUser.localId}));
  reason(await call('getEncryptedChanges', bUser, {...bCred, walletId, sinceRev: 0}), 'NOT_MEMBER');
  assert.deepEqual(ok(await call('getMyFamily', bUser, {...bCred})), {member: false});
  // Revocation drops the device key binding: no new wrapping possible.
  reason(await call('putMemberKey', a, {...aCred, walletId, memberAccountId: bUser.localId,
    publicKeyHash: pubHash(b(32)), keyInstallationId: bCred.installationId,
    wrapped: {v: 1, epk: b(32), n: b(12), c: b(48)}}), 'NOT_MEMBER');
  denied(await call('putEncryptedBatch', bUser, {...bCred, walletId, batchId: token(), baseHeadRev: 0, envelopes: [env(1)]}));
  denied(await call('getMemberKey', bUser, {...bCred, walletId}));
  assert.equal((await db.doc(`accounts/${bUser.localId}/walletIndex/family`).get()).exists, false);
  assert.deepEqual(ok(await call('getWalletClaim', bUser, {...bCred, walletId})), {claimed: true, ownedByYou: false});
  // Same FinancialMember, new Account: history identity (memberId) unchanged.
  const c = await account();
  const cCred = await activate(c);
  const t2 = ok(await call('createFamilyInvite', a, {...aCred, walletId, memberId: 'm-b', inviteeEmail: c.email})).token;
  assert.equal(ok(await call('acceptFamilyInvite', c, {...cCred, token: t2, publicKey: b(32)})).memberId, 'm-b');
  // Rules still deny direct access to invites.
  const read = await fetch(`http://127.0.0.1:8080/v1/projects/${project}/databases/(default)/documents/familyInvites`,
    {headers: {Authorization: `Bearer ${c.idToken}`}});
  assert.equal(read.status, 403);
});
