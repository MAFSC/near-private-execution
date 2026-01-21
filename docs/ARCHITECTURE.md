# Architecture — Private Execution → Public Settlement on NEAR (MVP)

This document explains the system at a glance: components, data flow, and the minimal security model used in the hackathon MVP.

---

## High-level idea

Run sensitive logic **off-chain** (private execution) and publish only a **verifiable final result** on-chain (public settlement).

NEAR stores:
- commitments (hashes) of private inputs / results
- minimal public output (what the dApp needs)
- receipts (who executed what, when)
- async callback triggers to dApps

No changes to NEAR consensus.

---

## Components

### On-chain
- **`shade-gateway`** (core)
  - `request_job()` stores job metadata + commitments
  - `get_pending_jobs()` exposes jobs to executors (worker)
  - `submit_result()` verifies & settles the result, stores receipt
  - triggers async callback to a dApp (`on_private_result`)

- **`shade-verifier`** (modular verification placeholder)
  - policy registry interface (sig/tee/zk-lite)
  - allowlist-based verification in MVP
  - designed for future TEE attestation / zk-lite proof verification

- **`shade-callback-demo`** (demo dApp)
  - receives settlement callback
  - stores last callback payload for easy verification

### Off-chain
- **Worker (`worker/`)**
  - polls NEAR for pending jobs
  - executes “private” logic (TEE-simulated in MVP)
  - produces:
    - `result_commitment = H(result || salt)`
    - `public_output` (minimal)
    - `proof` (MVP: signature placeholder)
  - calls `submit_result()` on `shade-gateway`

---

## Data flow (commit → execute → settle)

```text
dApp ── request_job(commit) ──▶ NEAR (shade-gateway)
  ▲                              │
  │            callback          │ verify(proof) + store receipt
  └──────── on_private_result ◀──┘
              ▲
              │ submit_result(commit+proof)
        Off-chain Worker (private execution)
