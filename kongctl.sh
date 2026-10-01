#!/usr/bin/env bash
set -euo pipefail
project_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${project_dir}"
# A trusted shell-compatible .env is optional; CI can supply the same variables.
if [[ -f .env ]]; then
  set -a
  source ./.env
  set +a
fi
: "${KONNECT_PAT:?Set KONNECT_PAT in .env or the environment}"
: "${KONNECT_REGION:?Set KONNECT_REGION in .env or the environment}"
export KONGCTL_DEFAULT_KONNECT_PAT="${KONNECT_PAT}"
mkdir -p .artifacts .plans
exec kongctl --profile default --log-file .artifacts/kongctl.log "$@" \
  --region "${KONNECT_REGION}"
