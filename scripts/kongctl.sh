#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/env.sh"
cd "${project_dir}"
exec kongctl "$@" --profile default --region "${KONNECT_REGION}" \
  --log-file "${project_dir}/.artifacts/kongctl.log"
