mkdir -p scripts
cat > scripts/deploy.testnet.sh <<'SH'
#!/usr/bin/env bash
set -euo pipefail

# Usage:
#   GATEWAY=shade-gateway.testnet VERIFIER=shade-verifier.testnet DEMO=shade-demo.testnet \
#   bash scripts/deploy.testnet.sh
#
# Prereqs: near-cli, cargo, wasm-opt(optional)
# Assumes each contract has a build script or `cargo near build` works.

: "${GATEWAY:?Set GATEWAY account (e.g. shade-gateway.testnet)}"
: "${VERIFIER:?Set VERIFIER account (e.g. shade-verifier.testnet)}"
: "${DEMO:?Set DEMO account (e.g. shade-demo.testnet)}"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
echo "Repo: $ROOT"

build_contract () {
  local dir="$1"
  echo "==> Building $dir"
  (cd "$ROOT/contracts/$dir" && cargo near build --no-docker)
}

deploy_contract () {
  local dir="$1"
  local account="$2"
  local wasm
  wasm="$(ls -1 "$ROOT/contracts/$dir/target/near/"*.wasm | head -n 1)"
  echo "==> Deploying $dir to $account ($wasm)"
  near deploy "$account" "$wasm"
}

echo "==> Build contracts"
build_contract shade-verifier
build_contract shade-gateway
build_contract shade-callback-demo

echo "==> Deploy contracts"
deploy_contract shade-verifier "$VERIFIER"
deploy_contract shade-gateway "$GATEWAY"
deploy_contract shade-callback-demo "$DEMO"

echo "==> Init contracts"
near call "$VERIFIER" new '{}' --accountId "$VERIFIER" || true
near call "$GATEWAY" new "{\"verifier\":\"$VERIFIER\"}" --accountId "$GATEWAY" || true
near call "$DEMO" new "{\"gateway\":\"$GATEWAY\"}" --accountId "$DEMO" || true

echo ""
echo "✅ Deployed:"
echo "  VERIFIER=$VERIFIER"
echo "  GATEWAY=$GATEWAY"
echo "  DEMO=$DEMO"
echo ""
echo "Next: create worker env and run worker (see worker/.env.example)"
SH
chmod +x scripts/deploy.testnet.sh
