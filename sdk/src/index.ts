import crypto from 'crypto';
import { Account } from 'near-api-js';

/**
 * Types
 */
export type RequestJobArgs = {
  gatewayContractId: string;
  programId: string;
  policyId: string;
  publicInputs?: Record<string, any>;
  inputCommitment: string;
  callbackContract: string;
  callbackMethod: string;
  depositNear?: string; // e.g. "0.1"
};

export type Receipt = {
  job_id: string;
  executor: string;
  result_commitment: string;
  public_output: string;
  settled_at_ms: number;
};

/**
 * Submit a private execution job to the ShadeGateway contract.
 */
export async function requestJob(
  account: Account,
  args: RequestJobArgs
): Promise<string> {
  const {
    gatewayContractId,
    programId,
    policyId,
    publicInputs = {},
    inputCommitment,
    callbackContract,
    callbackMethod,
    depositNear = '0'
  } = args;

  const res = await account.functionCall({
    contractId: gatewayContractId,
    methodName: 'request_job',
    args: {
      program_id: programId,
      policy_id: policyId,
      public_inputs: JSON.stringify(publicInputs),
      input_commitment: inputCommitment,
      callback_contract: callbackContract,
      callback_method: callbackMethod
    },
    attachedDeposit: BigInt(Math.floor(Number(depositNear) * 1e24)),
    gas: BigInt('200000000000000')
  });

  // near-api-js returns SuccessValue base64 sometimes, but
  // our contract returns job_id directly (string).
  // near-cli-style output is simpler, but for SDK we parse logs/result.
  const status: any = res.status;
  if (status?.SuccessValue) {
    const decoded = Buffer.from(status.SuccessValue, 'base64').toString();
    return decoded.replace(/"/g, '');
  }

  throw new Error('Failed to parse job_id from request_job result');
}

/**
 * Poll gateway contract until receipt is available.
 */
export async function awaitReceipt(
  account: Account,
  gatewayContractId: string,
  jobId: string,
  opts?: {
    pollIntervalMs?: number;
    timeoutMs?: number;
  }
): Promise<Receipt> {
  const pollIntervalMs = opts?.pollIntervalMs ?? 2000;
  const timeoutMs = opts?.timeoutMs ?? 120_000;

  const start = Date.now();

  while (true) {
    if (Date.now() - start > timeoutMs) {
      throw new Error('Timeout waiting for receipt');
    }

    const receipt = await account.viewFunction({
      contractId: gatewayContractId,
      methodName: 'get_receipt',
      args: { job_id: jobId }
    });

    if (receipt) {
      return receipt as Receipt;
    }

    await sleep(pollIntervalMs);
  }
}

/**
 * Verify that a revealed result matches an on-chain commitment.
 * (client-side verification helper)
 */
export function verifyCommitment(
  result: any,
  salt: string,
  expectedCommitment: string
): boolean {
  const serialized = JSON.stringify(result);
  const hash =
    '0x' +
    crypto
      .createHash('sha256')
      .update(serialized + '|' + salt)
      .digest('hex');

  return hash === expectedCommitment;
}

/**
 * Helper to create an input commitment on the client.
 */
export function makeInputCommitment(
  privateInput: any,
  salt: string
): string {
  const serialized = JSON.stringify(privateInput);
  return (
    '0x' +
    crypto
      .createHash('sha256')
      .update(serialized + '|' + salt)
      .digest('hex')
  );
}

function sleep(ms: number) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}
