# near-private-execution
# 🕶️ Private Execution → Public Settlement on NEAR

# NEAR Private Execution

## What it does
Private execution layer for NEAR:
- Sensitive logic runs off-chain (TEE / zk-lite)
- Only commitments & proofs settle on-chain
- No changes to NEAR consensus

## Why it matters
- Public blockchains leak business logic
- Enables private DeFi, auctions, games, voting

## Architecture
1. Gateway contract (NEAR)
2. Off-chain executor (TEE / zk-lite)
3. Verifier contract
4. Public settlement

## Demo flow
1. User submits job
2. Private execution off-chain
3. Commitment verified on-chain
4. Callback executed

## Status
✔ Contracts deployed on NEAR Testnet  
✔ End-to-end demo flow  
✔ Open-source

## Run Demo
bash scripts/deploy.testnet.sh

bash scripts/demo.testnet.sh

## Quick demo (NEAR testnet)

### 1. Prerequisites
- near-cli
- cargo-near
- Rust 1.86.0
- wasm32-unknown-unknown

### 2. Setup
cp .env.testnet.example .env.testnet
# fill USER=myaccount.testnet

### 3. Run demo
set -a; source ./.env.testnet; set +a
bash scripts/demo.testnet.sh

### 4. Expected output
- Gateway config printed
- Job submitted
- Demo contract receives callback



