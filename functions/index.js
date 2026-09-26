'use strict';
const {randomBytes, createHash, timingSafeEqual} = require('node:crypto');
const {initializeApp} = require('firebase-admin/app');
const {getFirestore, Timestamp} = require('firebase-admin/firestore');
const {onCall, HttpsError} = require('firebase-functions/v2/https');
initializeApp();
const db = getFirestore();
const hash = value => createHash('sha256').update(value).digest('hex');
const uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

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
  return {data, ref: db.doc(`accounts/${request.auth.uid}/session/current`)};
}
function valid(record) {
  return record && Number.isSafeInteger(record.generation) && record.generation > 0 &&
    typeof record.installationId === 'string' && uuid.test(record.installationId) &&
    typeof record.sessionSecretHash === 'string' && /^[0-9a-f]{64}$/.test(record.sessionSecretHash) &&
    record.activatedAt instanceof Timestamp && typeof record.active === 'boolean';
}
function authorize(record, data) {
  if (!valid(record) || !record.active || data.generation !== record.generation ||
      data.installationId !== record.installationId ||
      typeof data.secret !== 'string' || !/^[A-Za-z0-9_-]{43}$/.test(data.secret) ||
      !timingSafeEqual(Buffer.from(hash(data.secret), 'hex'),
        Buffer.from(record.sessionSecretHash, 'hex'))) {
    throw new HttpsError('permission-denied', 'Session not current');
  }
}
const options = {region: 'us-central1', enforceAppCheck: false, maxInstances: 5};
exports.activateSession = onCall(options, async request => {
  const {data, ref} = context(request);
  if (!uuid.test(data.installationId) || data.confirm !== true) {
    throw new HttpsError('invalid-argument', 'Explicit activation required');
  }
  const secret = randomBytes(32).toString('base64url');
  const generation = await db.runTransaction(async tx => {
    const snapshot = await tx.get(ref);
    const previous = snapshot.data();
    if (snapshot.exists && (!valid(previous) || previous.generation >= Number.MAX_SAFE_INTEGER)) {
      throw new HttpsError('failed-precondition', 'Invalid session state');
    }
    const next = snapshot.exists ? previous.generation + 1 : 1;
    tx.set(ref, {generation: next, installationId: data.installationId,
      sessionSecretHash: hash(secret), activatedAt: Timestamp.now(), active: true});
    return next;
  });
  // No logging of credentials; returned only by this activation response.
  return {generation, secret};
});
exports.protectedPing = onCall(options, async request => {
  const {data, ref} = context(request);
  return db.runTransaction(async tx => {
    authorize((await tx.get(ref)).data(), data);
    // P8+ must perform protected mutations IN this transaction after the gate.
    return {allowed: true};
  });
});
exports.deactivateSession = onCall(options, async request => {
  const {data, ref} = context(request);
  return db.runTransaction(async tx => {
    authorize((await tx.get(ref)).data(), data);
    tx.update(ref, {active: false});
    return {deactivated: true};
  });
});
