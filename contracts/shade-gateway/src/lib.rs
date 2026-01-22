use near_sdk::borsh::{self, BorshDeserialize, BorshSerialize};
use near_sdk::collections::{LookupMap, Vector};
use near_sdk::json_types::U128;
use near_sdk::{NearToken, env, near, AccountId, PanicOnDefault, Promise};

#[near(serializers=[borsh, json])]
#[derive(Clone)]
pub struct Job {
    pub job_id: String,
    pub requester: AccountId,
    pub program_id: String,
    pub policy_id: String,
    pub input_commitment: String,
    pub public_inputs: String,
    pub callback_contract: AccountId,
    pub callback_method: String,
    pub created_at_ms: u64,
    pub settled: bool,
}

#[near(serializers=[borsh, json])]
pub struct Receipt {
    pub job_id: String,
    pub executor: AccountId,
    pub result_commitment: String,
    pub public_output: String,
    pub settled_at_ms: u64,
}

/// Minimal verifier interface (MVP):
/// - "sig_v1": verify that `proof` is a signature made by `executor` over payload `job_id|result_commitment|public_output`
/// For hackathon simplicity, this contract does NOT implement cryptographic signature checks.
/// Instead, it allows a single trusted executor account (set in config).
/// This keeps the MVP fully working and demonstrates the flow.
/// Post-hackathon: replace with real signature/TEE attestation/zk verification.
#[near(contract_state)]
#[derive(PanicOnDefault)]
pub struct ShadeGateway {
    verifier: AccountId,
    trusted_executor: AccountId,

    jobs: LookupMap<String, Job>,
    pending_job_ids: Vector<String>,
    receipts: LookupMap<String, Receipt>,
}

#[near]
impl ShadeGateway {
    #[init]
    pub fn new(verifier: AccountId, trusted_executor: AccountId) -> Self {
        Self {
            verifier,
            trusted_executor,
            jobs: LookupMap::new(b"j"),
            pending_job_ids: Vector::new(b"p"),
            receipts: LookupMap::new(b"r"),
        }
    }

    /// Create a new private execution job.
    /// Stores only commitment + public params + callback target.
    ///
    /// Returns job_id.
    #[payable]
    pub fn request_job(
        &mut self,
        program_id: String,
        policy_id: String,
        public_inputs: String,
        input_commitment: String,
        callback_contract: AccountId,
        callback_method: String,
    ) -> String {
        let requester = env::predecessor_account_id();
        let created_at_ms = env::block_timestamp_ms();

        // Deterministic-ish unique id: hash(predecessor|block|nonce)
        let nonce = self.pending_job_ids.len();
        let seed = format!("{}|{}|{}", requester, created_at_ms, nonce);
        let job_hash = env::sha256(seed.as_bytes());
        let job_id = hex::encode(job_hash);

        let job = Job {
            job_id: job_id.clone(),
            requester,
            program_id,
            policy_id,
            input_commitment,
            public_inputs,
            callback_contract,
            callback_method,
            created_at_ms,
            settled: false,
        };

        self.jobs.insert(&job_id, &job);
        self.pending_job_ids.push(&job_id);

        env::log_str(&format!("JOB_CREATED {}", job_id));
        job_id
    }

    /// Worker pulls pending jobs. MVP: simple queue.
    pub fn get_pending_jobs(&self, limit: u32) -> Vec<Job> {
        let mut out: Vec<Job> = vec![];
        let mut i: u32 = 0;

        // naive scan from start; MVP acceptable. Improve with head index later.
        let total = self.pending_job_ids.len();
        while (i as u64) < total && (out.len() as u32) < limit {
            let id = self.pending_job_ids.get(i as u64).unwrap();
            if let Some(job) = self.jobs.get(&id) {
                if !job.settled && self.receipts.get(&id).is_none() {
                    out.push(job);
                }
            }
            i += 1;
        }
        out
    }

    /// Worker submits result commitment + public output + proof.
    /// MVP verification: only `trusted_executor` can settle.
    ///
    /// Also triggers async callback to the dApp.
    #[payable]
    pub fn submit_result(
        &mut self,
        job_id: String,
        result_commitment: String,
        public_output: String,
        proof: String,
    ) {
        let executor = env::predecessor_account_id();

        // Replay protection
        if self.receipts.get(&job_id).is_some() {
            env::panic_str("Already settled");
        }

        let mut job = self.jobs.get(&job_id).expect("Unknown job_id");
        if job.settled {
            env::panic_str("Job already marked settled");
        }

        // MVP verifier:
        // - enforce trusted executor
        // - accept any proof string (demonstration only)
        if executor != self.trusted_executor {
            env::panic_str("Unauthorized executor (MVP uses a trusted executor)");
        }
        if proof.is_empty() {
            env::panic_str("Missing proof");
        }

        job.settled = true;
        self.jobs.insert(&job_id, &job);

        let receipt = Receipt {
            job_id: job_id.clone(),
            executor: executor.clone(),
            result_commitment: result_commitment.clone(),
            public_output: public_output.clone(),
            settled_at_ms: env::block_timestamp_ms(),
        };
        self.receipts.insert(&job_id, &receipt);

        // Async callback to dApp
        // Expected signature:
        // on_private_result(job_id: String, public_output: String, result_commitment: String, receipt_ref: String)
        let receipt_ref = format!("receipt:{}", job_id);
        Promise::new(job.callback_contract.clone()).function_call(
            job.callback_method.clone(),
            near_sdk::serde_json::json!({
                "job_id": job_id,
                "public_output": public_output,
                "result_commitment": result_commitment,
                "receipt_ref": receipt_ref
            })
            .to_string()
            .into_bytes(),
            NearToken::from_yoctonear(0),
            near_sdk::Gas::from_tgas(30),
        );

        env::log_str(&format!("JOB_SETTLED {}", receipt.job_id));
    }

    pub fn get_job(&self, job_id: String) -> Option<Job> {
        self.jobs.get(&job_id)
    }

    pub fn get_receipt(&self, job_id: String) -> Option<Receipt> {
        self.receipts.get(&job_id)
    }

    pub fn get_config(&self) -> (AccountId, AccountId) {
        (self.verifier.clone(), self.trusted_executor.clone())
    }
}

// Small dependency for hex encoding.
mod hex {
    pub fn encode(bytes: Vec<u8>) -> String {
        const CHARS: &[u8; 16] = b"0123456789abcdef";
        let mut s = String::with_capacity(bytes.len() * 2);
        for &b in &bytes {
            s.push(CHARS[(b >> 4) as usize] as char);
            s.push(CHARS[(b & 0x0f) as usize] as char);
        }
        s
    }
}
