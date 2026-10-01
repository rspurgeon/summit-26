#!/usr/bin/env bash
set -euo pipefail

project_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -f "${project_dir}/.env" ]]; then
  set -a
  source "${project_dir}/.env"
  set +a
fi

if [[ $# -eq 0 || "${1:-}" == --help || "${1:-}" == -h ]]; then
  echo 'Usage: bash chat.sh "Your prompt"'
  echo 'Optional environment: AIGW_PROXY_PORT (8000), AIGW_MODEL (demo-chat)'
  exit 0
fi

for tool in curl jq; do
  command -v "${tool}" >/dev/null 2>&1 || {
    echo "${tool} is required" >&2
    exit 1
  }
done

payload="$(jq -n --arg model "${AIGW_MODEL:-demo-chat}" --arg prompt "$*" \
  '{model: $model, messages: [{role: "user", content: $prompt}]}')"

if ! response="$(curl --fail-with-body --silent --show-error --max-time 60 \
  "http://127.0.0.1:${AIGW_PROXY_PORT:-8000}/v1/chat/completions" \
  -H 'Content-Type: application/json' --data-binary "${payload}")"; then
  printf '%s\n' "${response}" >&2
  exit 1
fi

printf '%s\n' "${response}" | jq -er \
  '.choices[0].message.content | select(type == "string" and length > 0)'
