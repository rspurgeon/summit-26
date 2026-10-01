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
mkdir -p .artifacts .plans
cli=(kongctl)
context=(--profile default --region "$KONNECT_REGION" --log-file .artifacts/kongctl.log)
case "${1:-}" in
  plan)
    bash data-plane.sh preflight
    bash data-plane.sh certs
    "${cli[@]}" get organization "${context[@]}" -o json --jq '.id' --jq-raw-output > .plans/organization-id
    printf '%s\n' "$KONNECT_REGION" > .plans/region
    "${cli[@]}" plan "${context[@]}" --mode apply -f ai-gateway.yaml \
      --require-namespace summit-ai-demo --output-file .plans/apply.json
    "${cli[@]}" diff "${context[@]}" --plan .plans/apply.json
    ;;
  apply)
    [[ -f .plans/apply.json ]] || { echo 'Generate and review the saved plan first.' >&2; exit 1; }
    [[ "$(cat .plans/region)" == "$KONNECT_REGION" ]] || { echo 'Region changed; generate a new plan.' >&2; exit 1; }
    current_org="$("${cli[@]}" get organization "${context[@]}" -o json --jq '.id' --jq-raw-output)"
    [[ "$current_org" == "$(cat .plans/organization-id)" ]] || { echo 'Organization changed; generate a new plan.' >&2; exit 1; }
    : "${OPENAI_API_KEY:?Set OPENAI_API_KEY for the deferred provider secret}"
    "${cli[@]}" apply "${context[@]}" --plan .plans/apply.json -o json \
      --auto-approve --execution-report-file .artifacts/apply-report.json
    ;;
  start)
    gateway="$("${cli[@]}" get ai-gateway 'Summit AI Demo' "${context[@]}" -o json)"
    AIGW_CONTROL_PLANE="$(jq -er '.endpoints.configuration | sub("^https://"; "") | sub(":443$"; "")' <<< "$gateway")"
    AIGW_TELEMETRY="$(jq -er '.endpoints.telemetry | sub("^https://"; "") | sub(":443$"; "")' <<< "$gateway")"
    export AIGW_CONTROL_PLANE AIGW_TELEMETRY
    bash data-plane.sh run
    ;;
  nodes)
    "${cli[@]}" get ai-gateway nodes "${context[@]}" --gateway-name 'Summit AI Demo' -o json
    ;;
  smoke)
    curl --fail-with-body --silent --show-error --max-time 60 \
      "http://127.0.0.1:${AIGW_PROXY_PORT:-8000}/v1/chat/completions" \
      -H 'Content-Type: application/json' \
      -d '{"model":"demo-chat","messages":[{"role":"user","content":"Reply with a short greeting."}],"max_tokens":32}' \
      > .artifacts/inference.json
    jq -e '.choices[0].message.content | select(type == "string" and length > 0)' .artifacts/inference.json
    ;;
  drift)
    "${cli[@]}" plan "${context[@]}" --mode apply -f ai-gateway.yaml \
      --require-namespace summit-ai-demo --output-file .plans/follow-up.json
    "${cli[@]}" diff "${context[@]}" --plan .plans/follow-up.json
    ;;
  cleanup-plan)
    "${cli[@]}" plan "${context[@]}" --mode delete -f ai-gateway.yaml \
      --require-namespace summit-ai-demo --output-file .plans/delete.json
    "${cli[@]}" diff "${context[@]}" --plan .plans/delete.json
    ;;
  status|preflight|check|stop) bash data-plane.sh "$1" ;;
  *) echo 'Usage: bash gateway.sh plan|apply|start|nodes|smoke|drift|cleanup-plan|status|preflight|check|stop' >&2; exit 1 ;;
esac
