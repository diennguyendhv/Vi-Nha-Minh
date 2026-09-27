'use strict';
// Which Firebase project this backend serves, and as which environment.
// EXPLICIT allowlist: deploying this code to any project not listed here serves
// nothing (every callable fails in context()). PROD is added deliberately, by
// its exact project id, only after the PROD Firebase project exists.
const EMULATOR_PROJECT = 'demo-homewallet-p7';
const PROJECT_ENVIRONMENTS = Object.freeze({
  'vi-nha-minh-55c60': 'dev',
});

/** 'dev' | 'prod' | null (refuse). Pure: reads only the given env object. */
function serverEnvironment(env = process.env) {
  const project = env.GCLOUD_PROJECT;
  if (project === EMULATOR_PROJECT && env.FUNCTIONS_EMULATOR === 'true') return 'dev';
  return Object.prototype.hasOwnProperty.call(PROJECT_ENVIRONMENTS, project)
    ? PROJECT_ENVIRONMENTS[project] : null;
}

/**
 * Pre-claim "fixture" wallets (ciphertext for a wallet that was never claimed)
 * exist only for DEV testing. PROD serves CLAIMED wallets only.
 */
const fixturesAllowed = environment => environment === 'dev';

module.exports = {EMULATOR_PROJECT, PROJECT_ENVIRONMENTS, serverEnvironment, fixturesAllowed};
