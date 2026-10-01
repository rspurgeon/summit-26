#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/env.sh"
cd "${project_dir}"
# Endpoints must come from the provisioned gateway, never constructed locally.
AIGW_CONTROL_PLANE="$(bash scripts/kongctl.sh get ai-gateway 'Summit AI Demo' \
  -o json --jq '.endpoints.configuration | sub("^https://"; "") | sub(":443$"; "")' --jq-raw-output)"
AIGW_TELEMETRY="$(bash scripts/kongctl.sh get ai-gateway 'Summit AI Demo' \
  -o json --jq '.endpoints.telemetry | sub("^https://"; "") | sub(":443$"; "")' --jq-raw-output)"
export AIGW_CONTROL_PLANE AIGW_TELEMETRY
bash data-plane.sh run
