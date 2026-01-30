#!/usr/bin/env bash
set -euo pipefail

# scripts/demo.testnet.sh
# One-command demo:
# - load .env.testnet
# - ensure accounts exist
# - build 3 wasm (verifier/gateway/demo)
# - deploy
# - init new() (idempotent)
# - demo flow: request_job -> submit_result -> callback -> get_last_result

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# --- Load env ---
if [[ -f "$ROOT/.env.testnet" ]]; then
  set -a
  # shellcheck disable=SC1090
  source "$ROOT/.env.testnet"
  set +a
fi

NETWORK_ID="${NETWORK_ID:-${NEAR_ENV:-testnet}}"

: "${USER:?missing USER in .env.testnet}"
: "${GATEWAY:?missing GATEWAY in .env.testnet}"
: "${VERIFIER:?missing VERIFIER in .env.testnet}"
: "${DEMO:?missing DEMO in .env.testnet}"
: "${WORKER:?missing WORKER in .env.testnet}"

# Optional toggles
SKIP_BUILD="${SKIP_BUILD:-0}"
SKIP_DEPLOY="${SKIP_DEPLOY:-0}"
SKIP_INIT="${SKIP_INIT:-0}"
SKIP_FLOW="${SKIP_FLOW:-0}"

# Demo params (can override via env)
PROGRAM_ID="${PROGRAM_ID:-demo_program_v1}"
POLICY_ID="${POLICY_ID:-default_policy_v1}"
PUBLIC_INPUTS_JSON="${PUBLIC_INPUTS_JSON:-{\"msg\":\"hello from demo\"}}"
INPUT_COMMITMENT="${INPUT_COMMITMENT:-0x$(printf '%064x' 1)}"
PUBLIC_OUTPUT_JSON="${PUBLIC_OUTPUT_JSON:-{\"ok\":true,\"score\":9}}"
RESULT_COMMITMENT="${RESULT_COMMITMENT:-0x$(printf '%064x' 2)}"
PROOF="${PROOF:-dummy-proof}"
REQUEST_DEPOSIT="${REQUEST_DEPOSIT:-0.1}" # request_job is payable

say() { echo -e "$*"; }
die() { echo "ERROR: $*" >&2; exit 1; }
need_cmd(){ command -v "$1" >/dev/null 2>&1 || die "Missing command: $1"; }

account_exists() { near state "$1" --networkId "$NETWORK_ID" >/dev/null 2>&1; }

ensure_account() {
  local acct="$1"
  if account_exists "$acct"; then
    say "✓ Account exists: $acct"
    return 0
  fi
  if [[ "$acct" != *".${USER}" ]]; then
    die "Account $acct doesn't exist and is not a subaccount of USER=$USER (expected *.${USER})"
  fi
  say "==> Creating account: $acct (master: $USER)"
  near create-account "$acct" --masterAccount "$USER" --initialBalance 3 --networkId "$NETWORK_ID"
  say "✓ Created: $acct"
}

build_contract() {
  local dir="$1"
  say ""
  say "==> Building $(basename "$dir")"
  (cd "$ROOT/$dir" && cargo near build non-reproducible-wasm)
}

deploy_contract() {
  local wasm="$1"
  local acct="$2"
  say ""
  say "==> Deploying $(basename "$wasm") -> $acct"
  near deploy "$acct" "$wasm" --networkId "$NETWORK_ID" --force
  say "✓ Deployed: $acct"
}

call_init_idempotent() {
  local acct="$1"
  local method="$2"
  local args="$3"
  local signer="$4"

  say ""
  say "==> Init ($method) on $acct"
  set +e
  local out
  out="$(near call "$acct" "$method" "$args" --accountId "$signer" --networkId "$NETWORK_ID" 2>&1)"
  local rc=$?
  set -e

  if [[ $rc -eq 0 ]]; then
    echo "$out"
    say "✓ Initialized: $acct"
    return 0
  fi

  if echo "$out" | grep -qi "already been initialized"; then
    say "ℹ️  Already initialized: $acct"
    return 0
  fi

  echo "$out" >&2
  die "Init failed for $acct"
}

extract_job_id_from_output() {
  # Prefer log line: "Log [...]: JOB_CREATED <hex>"
  local out="$1"

  local job_id
  job_id="$(echo "$out" | sed -nE 's/.*JOB_CREATED[[:space:]]+([0-9a-f]{64}).*/\1/p' | tail -n 1 || true)"
  if [[ -n "${job_id:-}" ]]; then
    echo "$job_id"
    return 0
  fi

  # Fallback: try to find a quoted 64-hex string anywhere
  job_id="$(echo "$out" | grep -Eo "'[0-9a-f]{64}'" | tr -d "'" | tail -n 1 || true)"
  if [[ -n "${job_id:-}" ]]; then
    echo "$job_id"
    return 0
  fi

  # Last fallback: json-like "...."
  job_id="$(echo "$out" | grep -Eo '"[0-9a-f]{64}"' | tr -d '"' | tail -n 1 || true)"
  if [[ -n "${job_id:-}" ]]; then
    echo "$job_id"
    return 0
  fi

  return 1
}

# --- Preconditions ---
need_cmd near
need_cmd cargo
need_cmd jq

say ""
say "==> Using networkId=$NETWORK_ID, USER=$USER"
say ""
say "==> Contracts:"
say "  VERIFIER=$VERIFIER"
say "  GATEWAY=$GATEWAY"
say "  DEMO=$DEMO"
say "  WORKER=$WORKER"
say ""

# --- Accounts ---
say "==> Ensuring accounts exist (subaccounts of $USER)"
ensure_account "$VERIFIER"
ensure_account "$GATEWAY"
ensure_account "$DEMO"
ensure_account "$WORKER"

# --- Build ---
if [[ "$SKIP_BUILD" != "1" ]]; then
  build_contract "contracts/shade-verifier"
  build_contract "contracts/shade-gateway"
  build_contract "contracts/shade-callback-demo"
else
  say "==> SKIP_BUILD=1 (skipping builds)"
fi

VERIFIER_WASM="$ROOT/contracts/shade-verifier/target/near/shade_verifier.wasm"
GATEWAY_WASM="$ROOT/contracts/shade-gateway/target/near/shade_gateway.wasm"
DEMO_WASM="$ROOT/contracts/shade-callback-demo/target/near/shade_callback_demo.wasm"

[[ -f "$VERIFIER_WASM" ]] || die "Missing wasm: $VERIFIER_WASM"
[[ -f "$GATEWAY_WASM" ]] || die "Missing wasm: $GATEWAY_WASM"
[[ -f "$DEMO_WASM" ]] || die "Missing wasm: $DEMO_WASM"

# --- Deploy ---
if [[ "$SKIP_DEPLOY" != "1" ]]; then
  deploy_contract "$VERIFIER_WASM" "$VERIFIER"
  deploy_contract "$GATEWAY_WASM" "$GATEWAY"
  deploy_contract "$DEMO_WASM" "$DEMO"
else
  say "==> SKIP_DEPLOY=1 (skipping deploy)"
fi

# --- Init ---
if [[ "$SKIP_INIT" != "1" ]]; then
  call_init_idempotent "$VERIFIER" "new" "{}" "$USER"

  GW_INIT_ARGS="$(jq -nc --arg verifier "$VERIFIER" --arg trusted_executor "$WORKER" '{verifier:$verifier, trusted_executor:$trusted_executor}')"
  call_init_idempotent "$GATEWAY" "new" "$GW_INIT_ARGS" "$USER"

  DEMO_INIT_ARGS="$(jq -nc --arg gateway "$GATEWAY" '{gateway:$gateway}')"
  call_init_idempotent "$DEMO" "new" "$DEMO_INIT_ARGS" "$USER"
else
  say "==> SKIP_INIT=1 (skipping init)"
fi

# --- Sanity checks ---
say ""
say "==> Sanity checks (view)"
say "- GATEWAY.get_config:"
near view "$GATEWAY" get_config '{}' --networkId "$NETWORK_ID"
say "- DEMO.get_gateway:"
near view "$DEMO" get_gateway '{}' --networkId "$NETWORK_ID"
say "- DEMO.get_last_result:"
near view "$DEMO" get_last_result '{}' --networkId "$NETWORK_ID" || true

if [[ "$SKIP_FLOW" == "1" ]]; then
  say ""
  say "==> SKIP_FLOW=1 (skipping demo flow)"
  say ""
  say "==> DONE ✅"
  exit 0
fi

# --- Demo flow ---
say ""
say "==> Demo flow: request_job -> submit_result -> callback"
say ""

REQ_ARGS="$(jq -nc \
  --arg program_id "$PROGRAM_ID" \
  --arg policy_id "$POLICY_ID" \
  --arg public_inputs "$PUBLIC_INPUTS_JSON" \
  --arg input_commitment "$INPUT_COMMITMENT" \
  --arg callback_contract "$DEMO" \
  --arg callback_method "on_private_result" \
  '{
    program_id: $program_id,
    policy_id: $policy_id,
    public_inputs: $public_inputs,
    input_commitment: $input_commitment,
    callback_contract: $callback_contract,
    callback_method: $callback_method
  }'
)"

say "==> Calling GATEWAY.request_job (as USER=$USER)"
say "    program_id=$PROGRAM_ID policy_id=$POLICY_ID deposit=$REQUEST_DEPOSIT"
REQ_OUT="$(near call "$GATEWAY" request_job "$REQ_ARGS" --accountId "$USER" --networkId "$NETWORK_ID" --gas 30000000000000 --deposit "$REQUEST_DEPOSIT")"

JOB_ID="$(extract_job_id_from_output "$REQ_OUT" || true)"
if [[ -z "${JOB_ID:-}" ]]; then
  say ""
  echo "$REQ_OUT" >&2
  die "Could not parse job_id. Expected log: JOB_CREATED <64-hex>"
fi
say "✓ job_id=$JOB_ID"

SUBMIT_ARGS="$(jq -nc \
  --arg job_id "$JOB_ID" \
  --arg result_commitment "$RESULT_COMMITMENT" \
  --arg public_output "$PUBLIC_OUTPUT_JSON" \
  --arg proof "$PROOF" \
  '{
    job_id: $job_id,
    result_commitment: $result_commitment,
    public_output: $public_output,
    proof: $proof
  }'
)"

say ""
say "==> Calling GATEWAY.submit_result (as WORKER=$WORKER)"
set +e
SUBMIT_OUT="$(near call "$GATEWAY" submit_result "$SUBMIT_ARGS" --accountId "$WORKER" --networkId "$NETWORK_ID" --gas 250000000000000 --deposit 0 2>&1)"
SUBMIT_RC=$?
set -e

if [[ $SUBMIT_RC -ne 0 ]]; then
  echo "$SUBMIT_OUT" >&2
  say ""
  say "⚠️ submit_result failed."
  say "Most common reasons:"
  say "  1) No local key for WORKER=$WORKER"
  say "     Check: ls -la ~/.near-credentials/$NETWORK_ID/$WORKER.json"
  say "  2) WORKER is not the trusted_executor configured in gateway"
  say "     Check: near view \"$GATEWAY\" get_config '{}' --networkId $NETWORK_ID"
  say ""
  die "submit_result failed"
fi

echo "$SUBMIT_OUT"

say ""
say "==> Waiting for async callback..."
sleep 2

say ""
say "==> Read DEMO.get_last_result"
near view "$DEMO" get_last_result '{}' --networkId "$NETWORK_ID"

say ""
say "==> DONE ✅"
