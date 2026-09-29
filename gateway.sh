#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
# This is a trusted, shell-compatible local file. Never enable shell tracing.
if [[ -f .env ]]; then
  set -a
  source .env
  set +a
fi
mkdir -p .plans .artifacts
export KONGCTL_DEFAULT_KONNECT_PAT="${KONNECT_PAT:?Set KONNECT_PAT in .env or the environment}"
: "${KONNECT_REGION:?Set KONNECT_REGION}"
export AIGW_CONTAINER_NAME="${AIGW_CONTAINER_NAME:-summit-ai-demo-data-plane}"
export AIGW_PROXY_PORT="${AIGW_PROXY_PORT:-8000}"
export AIGW_PROXY_TLS_PORT="${AIGW_PROXY_TLS_PORT:-8443}"
cli() {
  kongctl "$@" --profile default --region "$KONNECT_REGION" \
    --log-file .artifacts/kongctl.log
}
case "${1:-}" in
  plan)
    cli get organization -o json --jq '.id' --jq-raw-output > .plans/organization-id.txt
    printf '%s\n' "$KONNECT_REGION" > .plans/region.txt
    cli plan --mode apply -f ai-gateway.yaml --require-namespace summit-ai-demo \
      --output-file .plans/apply.json
    cli diff --plan .plans/apply.json
    printf 'Organization: %s; region: %s; namespace: summit-ai-demo\n' \
      "$(cat .plans/organization-id.txt)" "$KONNECT_REGION"
    ;;
  apply)
    # Run only after reviewing and approving this exact saved plan and target.
    : "${OPENAI_API_KEY:?Set OPENAI_API_KEY}"
    [[ "$(cat .plans/region.txt)" == "$KONNECT_REGION" ]] || { echo 'Region changed; replan.' >&2; exit 1; }
    [[ "$(cat .plans/organization-id.txt)" == "$(cli get organization -o json --jq '.id' --jq-raw-output)" ]] || { echo 'Organization changed; replan.' >&2; exit 1; }
    cli apply --plan .plans/apply.json -o json --auto-approve \
      --execution-report-file .artifacts/apply-report.json
    ;;
  run)
    gateway="$(cli get ai-gateway 'Summit AI Demo' -o json)"
    export AIGW_CONTROL_PLANE AIGW_TELEMETRY
    AIGW_CONTROL_PLANE="$(jq -er '.endpoints.configuration | select(type == "string" and length > 0) | sub("^https://"; "") | sub(":443$"; "")' <<< "$gateway")"
    AIGW_TELEMETRY="$(jq -er '.endpoints.telemetry | select(type == "string" and length > 0) | sub("^https://"; "") | sub(":443$"; "")' <<< "$gateway")"
    bash data-plane.sh run
    ;;
  nodes) cli get ai-gateway nodes --gateway-name 'Summit AI Demo' -o json ;;
  smoke)
    curl --fail-with-body --silent --show-error --max-time 60 \
      "http://127.0.0.1:${AIGW_PROXY_PORT}/v1/chat/completions" \
      -H 'Content-Type: application/json' \
      -d '{"model":"demo-chat","messages":[{"role":"user","content":"Reply with a short greeting."}],"max_tokens":32}' \
      | jq -e '.choices[0].message.content | select(type == "string" and length > 0)'
    ;;
  certs|check|status|preflight|stop) bash data-plane.sh "$1" ;;
  *) echo 'Usage: bash gateway.sh plan|apply|certs|check|status|preflight|run|nodes|smoke|stop' >&2; exit 1 ;;
esac
