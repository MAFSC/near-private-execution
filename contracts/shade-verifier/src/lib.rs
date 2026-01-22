use near_sdk::borsh::{self, BorshDeserialize, BorshSerialize};
use near_sdk::collections::UnorderedSet;
use near_sdk::{env, near, AccountId, PanicOnDefault};

/// ShadeVerifier (MVP)
/// Purpose:
/// - Keep verification logic modular (so Gateway can swap policies later)
/// - For hackathon MVP we keep it simple: allowlist executors + policy id gate.
/// - Post-hackathon: replace/extend with real signature verification, TEE attestation checks, zk-lite verifiers.
///
/// Note: In the current MVP `shade-gateway` enforces a trusted executor directly.
/// This contract exists to show the architecture and make future upgrades clean.
#[near(contract_state)]
#[derive(PanicOnDefault)]
pub struct ShadeVerifier {
    allowed_executors: UnorderedSet<AccountId>,
}

#[near]
impl ShadeVerifier {
    #[init]
    pub fn new() -> Self {
        Self {
            allowed_executors: UnorderedSet::new(b"e"),
        }
    }

    /// Ownerless MVP helper: allow anyone to add executor.
    /// Hackathon-friendly, not production.
    /// Post-hackathon: gate by owner / DAO + staking.
    pub fn add_executor(&mut self, executor: AccountId) {
        self.allowed_executors.insert(&executor);
        env::log_str(&format!("EXECUTOR_ADDED {}", executor));
    }

    pub fn remove_executor(&mut self, executor: AccountId) {
        self.allowed_executors.remove(&executor);
        env::log_str(&format!("EXECUTOR_REMOVED {}", executor));
    }

    pub fn is_allowed(&self, executor: AccountId) -> bool {
        self.allowed_executors.contains(&executor)
    }

    /// Verification entrypoint (MVP):
    /// - policy_id: "sig_v1" (signature-based proof), "tee_v1", "zk_lite_v1" (future)
    /// - payload fields are passed separately to keep Gateway clean.
    ///
    /// Returns true if executor is in allowlist and proof is non-empty.
    pub fn verify(
        &self,
        policy_id: String,
        job_id: String,
        result_commitment: String,
        public_output: String,
        executor: AccountId,
        proof: String,
    ) -> bool {
        if !self.allowed_executors.contains(&executor) {
            return false;
        }
        if proof.is_empty() {
            return false;
        }

        // MVP policy gate (placeholder):
        match policy_id.as_str() {
            "sig_v1" => {
                // Post-hackathon: verify NEAR-style signature over:
                // payload = "{job_id}|{result_commitment}|{public_output}"
                // using executor's public key / attestation key.
                let _ = (job_id, result_commitment, public_output);
                true
            }
            "tee_v1" => {
                // Post-hackathon: verify attestation quote + enclave measurement.
                let _ = (job_id, result_commitment, public_output);
                true
            }
            "zk_lite_v1" => {
                // Post-hackathon: verify zk-lite proof or verifier contract call.
                let _ = (job_id, result_commitment, public_output);
                true
            }
            _ => false,
        }
    }
}
