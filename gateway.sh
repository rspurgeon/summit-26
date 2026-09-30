#!/usr/bin/env bash
set -euo pipefail
project_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${project_dir}"
if [[ -f .env ]]; then
  set -a
  source ./.env
  set +a
fi
: "${KONNECT_PAT:?Set KONNECT_PAT in .env or the environment}"
: "${KONNECT_REGION:?Set KONNECT_REGION in .env or the environment}"
export KONGCTL_DEFAULT_KONNECT_PAT="${KONNECT_PAT}"
mkdir -p .plans .artifacts
ctl() {
  kongctl "$@" --profile default --region "${KONNECT_REGION}" \
    --log-file "${project_dir}/.artifacts/kongctl.log"
}
org_id() {
  ctl get organization -o json --jq '.id' --jq-raw-output
}
case "${1:-}" in
  plan)
    target_org="$(org_id)"
    ctl plan --mode apply -f ai-gateway.yaml \
      --require-namespace summit-ai-demo --output-file .plans/apply.json
    jq -n --arg org "${target_org}" --arg region "${KONNECT_REGION}" \
      '{organization_id:$org,region:$region,profile:"default",namespace:"summit-ai-demo"}' \
      > .plans/target.json
    ctl diff --plan .plans/apply.json
    cat .plans/target.json
    ;;
  diff) ctl diff --plan .plans/apply.json ;;
  apply)
    : "${OPENAI_API_KEY:?Set OPENAI_API_KEY}"
    [[ -f .plans/apply.json && -f .plans/target.json ]] || {
      echo 'Run bash gateway.sh plan and review the saved plan first.' >&2; exit 1;
    }
    target_org="$(org_id)"
    jq -e --arg org "${target_org}" --arg region "${KONNECT_REGION}" \
      '.organization_id == $org and .region == $region' .plans/target.json >/dev/null || {
      echo 'Target changed; generate and review a new plan.' >&2; exit 1;
    }
    # Let kongctl request confirmation of the reviewed saved plan.
    ctl apply --plan .plans/apply.json -o text
    ;;
  up)
    ctl get ai-gateway 'Summit AI Demo' -o json \
      --jq '{configuration:.endpoints.configuration,telemetry:.endpoints.telemetry}' \
      > .artifacts/endpoints.json
    AIGW_CONTROL_PLANE="$(jq -er '.configuration | select(type == "string" and length > 0) | sub("^https://"; "") | sub(":443$"; "")' .artifacts/endpoints.json)"
    AIGW_TELEMETRY="$(jq -er '.telemetry | select(type == "string" and length > 0) | sub("^https://"; "") | sub(":443$"; "")' .artifacts/endpoints.json)"
    export AIGW_CONTROL_PLANE AIGW_TELEMETRY
    bash data-plane.sh run
    ;;
  nodes) ctl get ai-gateway nodes --gateway-name 'Summit AI Demo' -o text ;;
  smoke)
    curl --fail-with-body --silent --show-error --max-time 60 \
      "http://127.0.0.1:${AIGW_PROXY_PORT:-8000}/v1/chat/completions" \
      -H 'Content-Type: application/json' \
      -d '{"model":"demo-chat","messages":[{"role":"user","content":"Reply with a short greeting."}],"max_tokens":32}' \
      | jq -e '.choices[0].message.content | select(type == "string" and length > 0)' \
      | tee .artifacts/smoke-completion.json
    ;;
  certs|check|status|preflight|stop) bash data-plane.sh "$1" ;;
  ctl) shift; ctl "$@" ;;
  *) echo 'Usage: bash gateway.sh plan|diff|apply|up|nodes|smoke|certs|check|status|preflight|stop|ctl ...' >&2; exit 1 ;;
esac
