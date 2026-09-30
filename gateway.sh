#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
if [[ -f .env ]]; then
  set -a
  source ./.env
  set +a
fi
case "${1:-}" in
  certs|check|status|preflight|stop)
    bash data-plane.sh "$1"
    ;;
  run)
    gateway_json="$(bash kongctl.sh get ai-gateway 'Summit AI' -o json)"
    AIGW_CONTROL_PLANE="$(jq -er '.endpoints.configuration | sub("^https://"; "") | sub(":443$"; "")' <<< "$gateway_json")"
    AIGW_TELEMETRY="$(jq -er '.endpoints.telemetry | sub("^https://"; "") | sub(":443$"; "")' <<< "$gateway_json")"
    export AIGW_CONTROL_PLANE AIGW_TELEMETRY
    bash data-plane.sh run
    ;;
  smoke)
    mkdir -p .artifacts
    completion="$(curl --fail-with-body --silent --show-error --max-time 60 \
      "http://127.0.0.1:${AIGW_PROXY_PORT:-8000}/v1/chat/completions" \
      -H 'Content-Type: application/json' \
      -d '{"model":"demo-chat","messages":[{"role":"user","content":"Reply with a short greeting."}],"max_tokens":32}' \
      | jq -er '.choices[0].message.content | select(type == "string" and length > 0)')"
    jq -n --arg completion "$completion" \
      '{path:"/v1/chat/completions",alias:"demo-chat",completion:$completion}' \
      | tee .artifacts/inference-check.json
    ;;
  *)
    echo 'Usage: bash gateway.sh certs|check|status|preflight|run|smoke|stop' >&2
    exit 1
    ;;
esac
