#!/usr/bin/env bash
# Source from project scripts; only load the trusted local .env when present.
project_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if [[ -f "${project_dir}/.env" ]]; then
  set -a
  source "${project_dir}/.env"
  set +a
fi
: "${KONNECT_REGION:?Set KONNECT_REGION in .env or the environment}"
if [[ -n "${KONNECT_PAT:-}" ]]; then
  export KONGCTL_DEFAULT_KONNECT_PAT="${KONNECT_PAT}"
fi
export KONGCTL_DEFAULT_KONNECT_REGION="${KONNECT_REGION}"
export KONGCTL_NO_TELEMETRY=true
mkdir -p "${project_dir}/.artifacts" "${project_dir}/.plans"
