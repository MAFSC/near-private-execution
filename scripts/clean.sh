#!/usr/bin/env bash
set -euo pipefail

# Clean local build artifacts and optional NEAR testnet state
#
# Usage:
#   bash scripts/clean.sh            # safe local cleanup
#   CLEAN_NEAR_KEYS=1 bash scripts/clean.sh   # also remove near-cli credentials (DANGEROUS)

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
echo "==> Cleaning repo at $ROOT"

echo "==> Remove Rust build artifacts"
find "$ROOT/contracts" -type d -name target -prune -exec rm -rf {} +

echo "==> Remove worker build artifacts"
rm -rf "$ROOT/worker/dist" || true
rm -rf "$ROOT/worker/node_modules" || true

echo "==> Remove SDK build artifacts (if any)"
rm -rf "$ROOT/sdk/dist" || true
rm -rf "$ROOT/sdk/node_modules" || true

echo "==> Remove root node_modules (if any)"
rm -rf "$ROOT/node_modules" || true

if [[ "${CLEAN_NEAR_KEYS:-0}" == "1" ]]; then
  echo "⚠️  CLEAN_NEAR_KEYS=1 set — removing NEAR CLI credentials"
  echo "    (~/.near-credentials). This cannot be undone."
  rm -rf "$HOME/.near-credentials"
else
  echo "==> Keeping NEAR CLI credentials (default)"
fi

echo "==> Clean completed"
echo ""
echo "Next steps:"
echo "  1) bash scripts/deploy.testnet.sh"
echo "  2) cd worker && cp .env.example .env && npm i && npm run dev"
echo "  3) bash scripts/demo.testnet.sh"

