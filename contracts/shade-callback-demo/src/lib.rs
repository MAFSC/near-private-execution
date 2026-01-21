mkdir -p contracts/shade-callback-demo/src
cat > contracts/shade-callback-demo/src/lib.rs <<'RS'
use near_sdk::borsh::{self, BorshDeserialize, BorshSerialize};
use near_sdk::{env, near, AccountId, PanicOnDefault};

#[near(serializers=[borsh, json])]
pub struct LastResult {
    pub job_id: String,
    pub caller: AccountId,
    pub public_output: String,
    pub result_commitment: String,
    pub receipt_ref: String,
    pub received_at_ms: u64,
}

#[near(contract_state)]
#[derive(PanicOnDefault)]
pub struct ShadeCallbackDemo {
    gateway: AccountId,
    last: Option<LastResult>,
}

#[near]
impl ShadeCallbackDemo {
    #[init]
    pub fn new(gateway: AccountId) -> Self {
        Self { gateway, last: None }
    }

    /// This method is called by ShadeGateway as an async callback.
    /// In real dApps, this is where you mint, transfer, update state, etc.
    pub fn on_private_result(
        &mut self,
        job_id: String,
        public_output: String,
        result_commitment: String,
        receipt_ref: String,
    ) {
        // Basic access control: only gateway can call.
        let caller = env::predecessor_account_id();
        if caller != self.gateway {
            env::panic_str("Only gateway can call on_private_result");
        }

        self.last = Some(LastResult {
            job_id,
            caller,
            public_output,
            result_commitment,
            receipt_ref,
            received_at_ms: env::block_timestamp_ms(),
        });

        env::log_str("DEMO_CALLBACK_RECEIVED");
    }

    pub fn get_last_result(&self) -> Option<LastResult> {
        self.last.as_ref().map(|x| LastResult {
            job_id: x.job_id.clone(),
            caller: x.caller.clone(),
            public_output: x.public_output.clone(),
            result_commitment: x.result_commitment.clone(),
            receipt_ref: x.receipt_ref.clone(),
            received_at_ms: x.received_at_ms,
        })
    }

    pub fn get_gateway(&self) -> AccountId {
        self.gateway.clone()
    }
}
RS
