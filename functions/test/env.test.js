'use strict';
// Pure: which project is served, as which environment (no emulator needed).
const {test} = require('node:test');
const assert = require('node:assert/strict');
const {serverEnvironment, fixturesAllowed} = require('../env');

test('only explicitly listed projects are served', () => {
  assert.equal(serverEnvironment({GCLOUD_PROJECT: 'vi-nha-minh-55c60'}), 'dev');
  assert.equal(serverEnvironment({GCLOUD_PROJECT: 'demo-homewallet-p7', FUNCTIONS_EMULATOR: 'true'}), 'dev');
  // Demo project outside the emulator, unknown projects, prototype keys: refused.
  assert.equal(serverEnvironment({GCLOUD_PROJECT: 'demo-homewallet-p7'}), null);
  assert.equal(serverEnvironment({GCLOUD_PROJECT: 'some-other-project'}), null);
  assert.equal(serverEnvironment({GCLOUD_PROJECT: 'constructor'}), null);
  assert.equal(serverEnvironment({}), null);
});

test('pre-claim fixture wallets exist only in DEV', () => {
  assert.equal(fixturesAllowed('dev'), true);
  assert.equal(fixturesAllowed('prod'), false);
  assert.equal(fixturesAllowed(null), false);
});
