#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
if [[ -f .env ]]; then
  set -a
  source ./.env
  set +a
fi
: "${KONNECT_PAT:?Set KONNECT_PAT in .env or the environment}"
: "${KONNECT_REGION:?Set KONNECT_REGION in .env or the environment}"
export KONGCTL_DEFAULT_KONNECT_PAT="$KONNECT_PAT"
mkdir -p .artifacts
exec kongctl "$@" --profile default --region "$KONNECT_REGION" \
  --log-file .artifacts/kongctl.log
