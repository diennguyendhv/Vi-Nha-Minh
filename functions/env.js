'use strict';
// Which Firebase project this backend serves, and as which environment.
// EXPLICIT allowlist: deploying this code to any project not listed here serves
// nothing (every callable fails in context()).
// Owner decision 2026-09-27: ONE Firebase project. `vi-nha-minh-55c60` is the
// PRODUCTION cloud from now on; DEV work uses the Emulator Suite (demo project).
const EMULATOR_PROJECT = 'demo-homewallet-p7';
const PROJECT_ENVIRONMENTS = Object.freeze({
  'vi-nha-minh-55c60': 'prod',
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

/**
 * A CLAIMED wallet is served only by the environment that claimed it. Wallets
 * claimed while this project was still DEV (`environment: 'dev'`) are frozen
 * in production: never readable/writable by a production client.
 */
const sameEnvironment = (wallet, environment) =>
  !wallet || wallet.state !== 'CLAIMED' || wallet.environment === environment;

module.exports = {EMULATOR_PROJECT, PROJECT_ENVIRONMENTS, serverEnvironment, fixturesAllowed,
  sameEnvironment};
