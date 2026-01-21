# near-private-execution
# 🕶️ Private Execution → Public Settlement on NEAR

Privacy-preserving execution layer for NEAR: run sensitive logic off-chain (TEE / zk-lite-ready) and settle only a verifiable result on-chain using commitments + NEAR async callbacks — **no consensus changes**.

## What we built (MVP)
- **On-chain**: `shade-gateway` contract that accepts execution requests, stores commitments, verifies results, and triggers async settlement callbacks.
- **Off-chain**: a private execution **worker** that picks up jobs, executes confidential logic (TEE-simulated), produces `result_commitment + proof`, and submits settlement on-chain.
- **Demo dApp**: `shade-callback-demo` contract that receives `on_private_result(...)` callback.

## How it works (commit → execute → settle)
1) **Commit (on-chain)**  
   dApp calls `request_job()` with `input_commitment` (hash of private inputs) + public params + callback target.

2) **Private Execute (off-chain)**  
   Worker fetches the job, runs the logic privately, outputs:
   - `public_output` (minimal public result)
   - `result_commitment = H(result || salt)`
   - `proof` (MVP: signature; architecture ready for TEE attestation / zk-lite)

3) **Settle (on-chain)**  
   Contract verifies `proof`, stores a receipt, and triggers an async callback to the dApp contract.

## Why NEAR
- **Async calls** make multi-step settlement native (request → result → callback).
- **Low-cost state** for commitments/receipts.
- **Account-based model** fits executor isolation (per-worker accounts).

## Infra / Privacy judging criteria alignment
**Working demo**  
✅ End-to-end pipeline: `request_job → worker execute → submit_result → callback`.

**Infrastructure value**  
✅ Reusable primitive for any dApp needing confidential computation with public settlement (auctions, DAO, DeFi, MEV-resistant flows).

**Privacy-by-design**  
✅ Private inputs are never published on-chain; only commitments + minimal public output.  
✅ Verifiable settlement through proof verification (signature now; TEE/zk-lite extension points included).

**Technical clarity**  
✅ Clear separation of layers: on-chain settlement vs off-chain private execution.  
✅ Deterministic job IDs, receipts, replay protection.

## Use cases
- Sealed-bid auctions
- Confidential DAO governance / rules execution
- Private trading strategy execution
- MEV-resistant execution workflows

## Quickstart (Testnet)
### Prereqs
- NEAR CLI
- Node.js 18+
- Rust toolchain for NEAR contracts

### 1) Deploy contracts
```bash
bash scripts/deploy.testnet.sh
