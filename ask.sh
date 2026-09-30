#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 || -z "$1" ]]; then
  echo "Usage: $0 'Your prompt'" >&2
  exit 1
fi

jq -n --arg prompt "$1" --arg model "${AIGW_MODEL:-demo-chat}" '{
  model: $model,
  messages: [{role: "user", content: $prompt}],
  max_tokens: 256
}' | curl --fail-with-body --silent --show-error --max-time 60 \
  "http://127.0.0.1:${AIGW_PROXY_PORT:-8000}/v1/chat/completions" \
  -H 'Content-Type: application/json' \
  --data-binary @- \
  | jq -er '.choices[0].message.content // error(.error.message // "No assistant completion returned")'
