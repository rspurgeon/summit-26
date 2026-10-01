#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/env.sh"
# One bounded request; successful output proves a real assistant completion.
curl --fail-with-body --silent --show-error --max-time 60 \
  "http://127.0.0.1:${AIGW_PROXY_PORT:-8000}/v1/chat/completions" \
  -H 'Content-Type: application/json' \
  -d '{"model":"demo-chat","messages":[{"role":"user","content":"Reply with a short greeting."}],"max_tokens":32}' \
  | jq -e '{id, model, content: .choices[0].message.content, usage} | select(.content | type == "string" and length > 0)' \
  | tee "${project_dir}/.artifacts/inference-check.json"
