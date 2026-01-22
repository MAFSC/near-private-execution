#!/usr/bin/env bash
set -euo pipefail

# End-to-end demo:
# 1) creates a job on shade-gateway (commit)
# 2) waits until worker submits result (settle)
# 3) prints receipt + demo dApp state
#
# Usage:
#   GATEWAY=shade-gateway.testnet DEMO=shade-demo.testnet USER=youraccount.testnet \
#   bash scripts/demo.testnet.sh
#
# Optional:
#   TIMEOUT_SEC=120 POLL_SEC=3

: "${GATEWAY:?Set GATEWAY account (e.g. shade-gateway.testnet)}"
: "${DEMO:?Set DEMO account (e.g. shade-demo.testnet)}"
: "${USER:?Set USER account (e.g. yourname.testnet)}"

TIMEOUT_SEC="${TIMEOUT_SEC:-180}"
POLL_SEC="${POLL_SEC:-3}"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

echo "==> Demo config"
echo "  GATEWAY=$GATEWAY"
echo "  DEMO=$DEMO"
echo "  USER=$USER"
echo "  TIMEOUT_SEC=$TIMEOUT_SEC"
echo "  POLL_SEC=$POLL_SEC"
echo ""

# We keep the "private inputs" off-chain in this MVP.
# Here we only put an input_commitment on-chain.
#
# The worker should be configured to understand `program_id="demo_v1"`
# and compute some deterministic public_output based on a secret it knows
# (or a mocked "private" value).

PROGRAM_ID="demo_v1"
POLICY_ID="sig_v1" # signature-based "TEE-simulated" proof in MVP

# Simple commitment: H("secret:42|salt:demo") in hex.
# Replace with your worker's expected commitment scheme if different.
INPUT_COMMITMENT="0x$(printf 'secret:42|salt:demo' | sha256sum | awk '{print $1}')"

# Callback target: DEMO contract method
CALLBACK_CONTRACT="$DEMO"
CALLBACK_METHOD="on_private_result"

echo "==> Creating job (request_job)"
REQ_JSON=$(cat <<JSON
{
  "program_id": "$PROGRAM_ID",
  "policy_id": "$POLICY_ID",
  "public_inputs": "{\"note\":\"hackathon_demo\"}",
  "input_commitment": "$INPUT_COMMITMENT",
  "callback_contract": "$CALLBACK_CONTRACT",
  "callback_method": "$CALLBACK_METHOD"
}
JSON
)

# We expect request_job to return a job_id (string or u64).
# If your contract returns a struct, adjust parsing accordingly.
JOB_ID=$(near call "$GATEWAY" request_job "$REQ_JSON" --accountId "$USER" --deposit 0.1 --gas 200000000000000 \
  | tail -n 1 | tr -d '"' || true)

if [[ -z "${JOB_ID:-}" ]]; then
  echo "❌ Could not parse JOB_ID from near-cli output."
  echo "Check your contract return value and update this script parsing."
  exit 1
fi

echo "✅ job_id=$JOB_ID"
echo ""
echo "==> Waiting for receipt (worker must be running)"
DEADLINE=$(( $(date +%s) + TIMEOUT_SEC ))

while true; do
  now=$(date +%s)
  if (( now > DEADLINE )); then
    echo "❌ Timeout waiting for receipt. Is the worker running?"
    echo "Try: (cd worker && npm run start)"
    exit 1
  fi

  # Expect a view method get_receipt(job_id) returning null/None or a receipt object.
  RECEIPT=$(near view "$GATEWAY" get_receipt "{\"job_id\":\"$JOB_ID\"}" 2>/dev/null || true)

  if echo "$RECEIPT" | grep -qiE 'null|None|not found|^$'; then
    echo "… not settled yet (poll in ${POLL_SEC}s)"
    sleep "$POLL_SEC"
    continue
  fi

  echo "✅ Receipt found:"
  echo "$RECEIPT"
  break
done

echo ""
echo "==> Demo dApp state (callback side effects)"
# Expect demo contract has a view get_last_result() or similar.
# If not, adjust to your demo contract API.
DEMO_STATE=$(near view "$DEMO" get_last_result '{}' 2>/dev/null || true)
echo "$DEMO_STATE"

echo ""
echo "🎉 End-to-end demo complete."
echo "Job was requested on-chain, executed privately by worker, and settled with an async callback."
