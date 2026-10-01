#!/usr/bin/env bash
set -euo pipefail
project_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${project_dir}"
if [[ -f .env ]]; then
  set -a
  source ./.env
  set +a
fi
export AIGW_CONTAINER_NAME="${AIGW_CONTAINER_NAME:-summit-ai-demo-data-plane}"
export AIGW_PROXY_PORT="${AIGW_PROXY_PORT:-8000}"
export AIGW_PROXY_TLS_PORT="${AIGW_PROXY_TLS_PORT:-8443}"
case "${1:-}" in
  run)
    AIGW_CONTROL_PLANE="$(bash kongctl.sh get ai-gateway 'Summit AI' -o json \
      --jq '.endpoints.configuration | sub("^https://"; "") | sub(":443$"; "")' --jq-raw-output)"
    AIGW_TELEMETRY="$(bash kongctl.sh get ai-gateway 'Summit AI' -o json \
      --jq '.endpoints.telemetry | sub("^https://"; "") | sub(":443$"; "")' --jq-raw-output)"
    export AIGW_CONTROL_PLANE AIGW_TELEMETRY
    bash data-plane.sh run
    ;;
  smoke)
    mkdir -p .artifacts
    curl --fail-with-body --silent --show-error --max-time 60 \
      "http://127.0.0.1:${AIGW_PROXY_PORT}/v1/chat/completions" \
      -H 'Content-Type: application/json' \
      -d '{"model":"demo-chat","messages":[{"role":"user","content":"Reply with a short greeting."}],"max_tokens":32}' \
      > .artifacts/inference.json
    jq -e '.choices[0].message.content | select(type == "string" and length > 0)' \
      .artifacts/inference.json
    ;;
  certs|check|status|preflight|stop) bash data-plane.sh "$1" ;;
  *) echo 'Usage: bash local.sh certs|check|status|preflight|run|smoke|stop' >&2; exit 1 ;;
esac
