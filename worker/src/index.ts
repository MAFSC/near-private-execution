import 'dotenv/config';
import { connect, keyStores, KeyPair, Near, Account } from 'near-api-js';
import crypto from 'crypto';

const {
  NEAR_RPC_URL,
  NEAR_NETWORK_ID,
  WORKER_ACCOUNT_ID,
  NEAR_CREDENTIALS_PATH,
  GATEWAY_CONTRACT_ID,
  POLL_INTERVAL_MS = '2000',
  MAX_JOBS_PER_TICK = '3',
  PROOF_MODE = 'near_sign', // near_sign | hmac
  HMAC_SECRET = '',
  DEMO_PROGRAM_ID = 'demo_v1',
  DEMO_PRIVATE_SECRET = 'secret:42',
  DEMO_PRIVATE_SALT = 'demo',
  LOG_LEVEL = 'info'
} = process.env as Record<string, string>;

if (!WORKER_ACCOUNT_ID || !NEAR_CREDENTIALS_PATH || !GATEWAY_CONTRACT_ID) {
  console.error('Missing required env vars. Check worker/.env');
  process.exit(1);
}

const log = (...args: any[]) => {
  if (LOG_LEVEL !== 'silent') console.log('[worker]', ...args);
};

type Job = {
  job_id: string;
  program_id: string;
  policy_id: string;
  input_commitment: string;
  public_inputs: string;
};

async function initNear(): Promise<Account> {
  const keyStore = new keyStores.UnencryptedFileSystemKeyStore(
    NEAR_CREDENTIALS_PATH.replace(/\/[^/]+$/, '')
  );

  const near = new Near({
    networkId: NEAR_NETWORK_ID,
    nodeUrl: NEAR_RPC_URL,
    keyStore
  });

  return near.account(WORKER_ACCOUNT_ID);
}

// --- MVP "private execution" ---
function executePrivate(job: Job) {
  // Deterministic demo logic:
  // public_output = length of secret + note from public_inputs
  const note = (() => {
    try {
      const p = JSON.parse(job.public_inputs || '{}');
      return p.note || '';
    } catch {
      return '';
    }
  })();

  const result = {
    score: DEMO_PRIVATE_SECRET.length,
    note
  };

  const resultSerialized = JSON.stringify(result);
  const resultCommitment = '0x' + crypto
    .createHash('sha256')
    .update(resultSerialized + '|' + DEMO_PRIVATE_SALT)
    .digest('hex');

  return { result, resultCommitment };
}

// --- Proof generation (MVP) ---
async function makeProof(account: Account, payload: string): Promise<string> {
  if (PROOF_MODE === 'hmac') {
    if (!HMAC_SECRET) throw new Error('HMAC_SECRET is required for hmac mode');
    return crypto.createHmac('sha256', HMAC_SECRET).update(payload).digest('hex');
  }

  // Default: sign with NEAR account key (TEE-simulated)
  const keyPair = await account.connection.signer.getKey(
    NEAR_NETWORK_ID,
    WORKER_ACCOUNT_ID
  );
  if (!keyPair) throw new Error('No keypair found for worker account');

  const signature = keyPair.sign(Buffer.from(payload));
  return Buffer.from(signature.signature).toString('base64');
}

// --- Main loop ---
async function main() {
  const account = await initNear();
  log('Started. Account:', WORKER_ACCOUNT_ID);

  while (true) {
    try {
      // Expect a view method that returns pending jobs array
      const jobs: Job[] = await account.viewFunction({
        contractId: GATEWAY_CONTRACT_ID,
        methodName: 'get_pending_jobs',
        args: { limit: Number(MAX_JOBS_PER_TICK) }
      });

      if (!jobs || jobs.length === 0) {
        await sleep(Number(POLL_INTERVAL_MS));
        continue;
      }

      for (const job of jobs) {
        if (job.program_id !== DEMO_PROGRAM_ID) {
          log('Skip unknown program:', job.program_id);
          continue;
        }

        log('Processing job', job.job_id);

        const { result, resultCommitment } = executePrivate(job);
        const publicOutput = JSON.stringify({ ok: true, score: result.score });

        const proofPayload = [
          job.job_id,
          resultCommitment,
          publicOutput
        ].join('|');

        const proof = await makeProof(account, proofPayload);

        await account.functionCall({
          contractId: GATEWAY_CONTRACT_ID,
          methodName: 'submit_result',
          args: {
            job_id: job.job_id,
            result_commitment: resultCommitment,
            public_output: publicOutput,
            proof
          },
          gas: BigInt('200000000000000')
        });

        log('Submitted result for job', job.job_id);
      }
    } catch (err) {
      console.error('[worker] loop error:', err);
    }

    await sleep(Number(POLL_INTERVAL_MS));
  }
}

function sleep(ms: number) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

main().catch((e) => {
  console.error('[worker] fatal:', e);
  process.exit(1);
});
