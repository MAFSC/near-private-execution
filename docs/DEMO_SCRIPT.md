# Demo Script (2–3 min) — Private Execution → Public Settlement on NEAR

Goal: show an end-to-end working MVP:
**request_job → off-chain private execution worker → submit_result → on-chain verification → async callback**.

---

## 0) Setup (pre-record / before call)
Have these ready:
- Deployed contracts: `shade-verifier`, `shade-gateway`, `shade-callback-demo`
- Worker account funded on testnet
- Worker running locally
- Terminal 1: worker logs
- Terminal 2: NEAR CLI calls + views

---

## 1) One-liner intro (10s)
> “This project adds a privacy-preserving execution layer to NEAR.  
> Sensitive logic runs off-chain, and NEAR only sees verifiable commitments + a final public result.  
> The key is NEAR async calls: commit → execute → settle → callback.”

---

## 2) Show contracts deployed (10–15s)
In Terminal 2:
```bash
near view $GATEWAY get_config '{}'
near view $DEMO get_gateway '{}'
