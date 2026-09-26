'use strict';
const {test} = require('node:test');
const assert = require('node:assert/strict');
const {randomUUID} = require('node:crypto');
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
async function call(name, user, data) {
  const response = await fetch(`http://127.0.0.1:5001/${project}/us-central1/${name}`, {
    method: 'POST', headers: {'Content-Type': 'application/json',
      ...(user ? {Authorization: `Bearer ${user.idToken}`} : {})},
    body: JSON.stringify({data}),
  });
  return response.json();
}
const denied = response => assert.equal(response.error?.status, 'PERMISSION_DENIED');
async function activate(user, installationId = randomUUID()) {
  const response = await call('activateSession', user,
    {accountId: user.localId, installationId, confirm: true});
  assert.ok(response.result?.secret);
  return {accountId: user.localId, installationId, ...response.result};
}
test('real callable boundary: replacement, replay, isolation, logout and refresh', async () => {
  const user = await account();
  const other = await account();
  assert.equal((await call('activateSession', null, {})).error.status, 'UNAUTHENTICATED');
  denied(await call('activateSession', user, {accountId: other.localId}));
  denied(await call('protectedPing', user, {accountId: user.localId}));
  const a = await activate(user);
  assert.equal((await call('protectedPing', user, a)).result.allowed, true);
  const stored = (await db.doc(`accounts/${user.localId}/session/current`).get()).data();
  assert.equal(stored.secret, undefined);
  assert.notEqual(stored.sessionSecretHash, a.secret);
  const b = await activate(user);
  assert.equal(b.generation, a.generation + 1);
  assert.equal((await call('protectedPing', user, b)).result.allowed, true);
  // EXACT SAME Firebase token still accepted; secret A is what is rejected.
  denied(await call('protectedPing', user, a));
  denied(await call('protectedPing', user, {...b, secret: a.secret}));
  denied(await call('protectedPing', user, {...b, generation: a.generation}));
  denied(await call('protectedPing', user, {...b, secret: 'x'.repeat(43)}));
  denied(await call('protectedPing', user, {...b, secret: undefined}));
  denied(await call('protectedPing', other, b));
  denied(await call('protectedPing', other, {...b, accountId: other.localId}));
  denied(await call('deactivateSession', user, a));
  assert.equal((await call('protectedPing', user, b)).result.allowed, true);
  const refresh = await fetch('http://127.0.0.1:9099/securetoken.googleapis.com/v1/token?key=fake', {
    method: 'POST', headers: {'Content-Type': 'application/x-www-form-urlencoded'},
    body: new URLSearchParams({grant_type: 'refresh_token', refresh_token: user.refreshToken}),
  });
  const refreshed = await refresh.json();
  assert.ok(refreshed.id_token);
  const reopened = {...user, idToken: refreshed.id_token};
  denied(await call('protectedPing', reopened, a));
  assert.equal((await call('protectedPing', reopened, b)).result.allowed, true);
  const a2 = await activate(reopened, a.installationId);
  denied(await call('protectedPing', user, b));
  assert.equal((await call('protectedPing', reopened, a2)).result.allowed, true);
  assert.equal((await call('deactivateSession', reopened, a2)).result.deactivated, true);
  denied(await call('protectedPing', reopened, a2));
  const a3 = await activate(reopened);
  assert.ok(a3.generation > a2.generation);
  await db.doc(`accounts/${user.localId}/session/current`).update({generation: 'bad'});
  denied(await call('protectedPing', user, a3));
  assert.equal((await call('activateSession', user, {...a3, confirm: true})).error.status,
    'FAILED_PRECONDITION');
});
test('Firestore REST Rules deny self promotion, reads and alternate cloud writes', async () => {
  const user = await account();
  await activate(user);
  for (const path of [`accounts/${user.localId}/session/current`, 'wallets/test',
    'wallets/test/transactions/test']) {
    for (const method of ['GET', 'PATCH']) {
      const response = await fetch(`http://127.0.0.1:8080/v1/projects/${project}/databases/(default)/documents/${path}`, {
        method, headers: {Authorization: `Bearer ${user.idToken}`, 'Content-Type': 'application/json'},
        ...(method === 'PATCH' ? {body: JSON.stringify({fields: {generation: {integerValue: '999'}}})} : {}),
      });
      assert.equal(response.status, 403);
    }
  }
});
test('concurrent activations leave exactly one current secret', async () => {
  const user = await account();
  const credentials = await Promise.all([activate(user), activate(user), activate(user)]);
  const results = await Promise.all(credentials.map(c => call('protectedPing', user, c)));
  assert.equal(results.filter(r => r.result?.allowed).length, 1);
  assert.equal(new Set(credentials.map(c => c.generation)).size, 3);
});
