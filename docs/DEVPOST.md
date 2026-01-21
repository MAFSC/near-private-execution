# Private Execution → Public Settlement on NEAR

## Elevator Pitch
Privacy-preserving execution layer for NEAR that runs sensitive logic off-chain (TEE / zk-lite-ready) and settles only a verifiable result on-chain using commitments and async smart contracts — without modifying NEAR consensus.

---

## What We Built
We built a working infrastructure MVP that allows dApps on NEAR to:
- submit a job with **private inputs committed on-chain**,
- execute confidential logic **off-chain**,
- and settle a **verifiable final result on-chain** with an async callback.

The system follows a clean **commit → execute → settle** flow and is designed as a reusable primitive for privacy-sensitive applications.

---

## How It Works
1. **Commit (on-chain)**  
   A dApp calls `request_job()` on the `shade-gateway` contract with:
   - a commitment to private inputs,
   - public parameters,
   - and a callback target.

2. **Private Execution (off-chain)**  
   A worker polls for pending jobs, executes the logic privately (TEE-simulated in MVP), and produces:
   - `result_commitment`,
   - minimal `public_output`,
   - and a verification proof.

3. **Public Settlement (on-chain)**  
   The worker submits the result.  
   The contract verifies it, stores a receipt, and triggers an **async callback** to the dApp.

At no point are private inputs or intermediate computation steps revealed on-chain.

---

## Why NEAR
This project is NEAR-native by design:
- **Async cross-contract calls** enable clean multi-step settlement.
- **Low-cost state** allows storing commitments and receipts efficiently.
- **Account-based model** enables executor isolation and future staking.
- No changes to NEAR consensus are required.

---

## Use Cases
- Sealed-bid auctions
- Confidential DAO governance and rules execution
- Private trading strategy execution
- MEV-resistant execution workflows
- Off-chain state machines with on-chain finality

---

## What’s Implemented in the MVP
- ✅ On-chain settlement contract (`shade-gateway`)
- ✅ Modular verifier contract (`shade-verifier`)
- ✅ Off-chain private execution worker
- ✅ Commit → execute → settle pipeline
- ✅ Async callback demo dApp
- ❌ Production TEE attestation (simulated for hackathon)
- ❌ Full zk verification (architecture ready)

---

## Infrastructure & Privacy Value
**Infrastructure**  
This is a reusable execution primitive that any NEAR dApp can integrate to add privacy-preserving computation without redesigning their contracts.

**Privacy**  
Private inputs never touch the blockchain.  
Only cryptographic commitments and minimal public outputs are published, preserving confidentiality while keeping results publicly verifiable.

---

## Tech Stack
- NEAR Protocol
- Rust (NEAR smart contracts)
- Node.js / TypeScript (off-chain worker)
- Cryptographic commitments
- Async smart contracts

---

## Demo
The repository includes:
- one-command contract deployment,
- an off-chain worker,
- and an end-to-end demo script showing:
  `request_job → private execution → on-chain settlement → async callback`.

---

## Future Work
- Real TEE attestation verification
- zk-lite invariant proofs
- Executor staking, slashing, and quorum execution
- Production SDK for dApp developers

---

Built for the **NEAR Innovation Sandbox / NEAR Hackathon**  
Track: **Infrastructure / Privacy**

