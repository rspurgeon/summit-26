#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
umask 077
if [[ -f .env ]]; then
  set -a
  . ./.env
  set +a
fi
export AIGW_CONTAINER_NAME="${AIGW_CONTAINER_NAME:-summit-ai-demo-data-plane}"
export AIGW_PROXY_PORT="${AIGW_PROXY_PORT:-8000}"
export AIGW_PROXY_TLS_PORT="${AIGW_PROXY_TLS_PORT:-8443}"
mkdir -p .plans .artifacts
namespace=summit-ai-demo
gateway_name='Summit AI Demo'

konnect_context() {
  : "${KONNECT_PAT:?Set KONNECT_PAT in .env or the environment}"
  : "${KONNECT_REGION:?Set KONNECT_REGION in .env or the environment}"
  export KONGCTL_DEFAULT_KONNECT_PAT="$KONNECT_PAT"
}
kctl() {
  konnect_context
  kongctl "$@" --profile default --region "$KONNECT_REGION" \
    --log-file .artifacts/kongctl.log
}
organization_id() {
  kctl get organization -o json --jq '.id' --jq-raw-output
}
plan_changes() {
  local mode="$1" organization
  organization="$(organization_id)"
  kctl plan --mode "$mode" -f ai-gateway.yaml \
    --require-namespace "$namespace" --output-file ".plans/${mode}.json"
  jq -n --arg org "$organization" --arg region "$KONNECT_REGION" \
    --arg hash "$(shasum -a 256 ".plans/${mode}.json" | awk '{print $1}')" \
    '{organization_id:$org, region:$region, plan_sha256:$hash}' \
    > ".plans/${mode}-target.json"
  cat ".plans/${mode}-target.json"
  kctl diff --plan ".plans/${mode}.json" -o text
}
execute_plan() {
  local mode="$1" organization
  konnect_context
  [[ -f ".plans/${mode}.json" && -f ".plans/${mode}-target.json" ]] || {
    echo 'Generate and review a saved plan first.' >&2; exit 1;
  }
  organization="$(organization_id)"
  jq -e --arg org "$organization" --arg region "$KONNECT_REGION" \
    --arg hash "$(shasum -a 256 ".plans/${mode}.json" | awk '{print $1}')" \
    '.organization_id == $org and .region == $region and .plan_sha256 == $hash' \
    ".plans/${mode}-target.json" >/dev/null || {
      echo 'Target or saved plan changed; generate and review a new plan.' >&2; exit 1;
    }
  : "${OPENAI_API_KEY:?Set OPENAI_API_KEY in .env or the environment}"
  kctl "$mode" --plan ".plans/${mode}.json" -o json --auto-approve \
    --execution-report-file ".artifacts/${mode}-report.json"
  [[ -s ".artifacts/${mode}-report.json" ]] || {
    echo 'Execution returned successfully, but no report was written. Inspect remote state before retrying.' >&2
    exit 1
  }
}

case "${1:-}" in
  certs|check|status|preflight|stop) bash data-plane.sh "$1" ;;
  plan) plan_changes apply ;;
  diff) kctl diff --plan .plans/apply.json -o text ;;
  apply) execute_plan apply ;;
  run)
    kctl get ai-gateway "$gateway_name" -o json \
      --jq '{id, endpoints}' > .artifacts/gateway.json
    AIGW_CONTROL_PLANE="$(jq -er '.endpoints.configuration | select(type == "string" and length > 0) | sub("^https://"; "") | sub(":443$"; "")' .artifacts/gateway.json)"
    AIGW_TELEMETRY="$(jq -er '.endpoints.telemetry | select(type == "string" and length > 0) | sub("^https://"; "") | sub(":443$"; "")' .artifacts/gateway.json)"
    export AIGW_CONTROL_PLANE AIGW_TELEMETRY
    bash data-plane.sh run
    ;;
  nodes) kctl get ai-gateway nodes --gateway-name "$gateway_name" -o json ;;
  smoke)
    curl --fail-with-body --silent --show-error --max-time 60 \
      "http://127.0.0.1:${AIGW_PROXY_PORT}/v1/chat/completions" \
      -H 'Content-Type: application/json' \
      -d '{"model":"demo-chat","messages":[{"role":"user","content":"Reply with a short greeting."}],"max_tokens":32}' \
      > .artifacts/inference.json
    jq -e '.choices[0].message.content | select(type == "string" and length > 0)' \
      .artifacts/inference.json
    ;;
  cleanup-plan) plan_changes delete ;;
  cleanup) execute_plan delete ;;
  *) echo 'Usage: bash gateway.sh certs|check|status|preflight|plan|diff|apply|run|nodes|smoke|stop|cleanup-plan|cleanup' >&2; exit 1 ;;
esac
