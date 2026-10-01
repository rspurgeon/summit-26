#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: bash scripts/chat.sh [--system TEXT] [--json] [--] [PROMPT]

Send one chat request to the local AI Gateway using model alias demo-chat.
If PROMPT is omitted, read it from stdin. Output the assistant's reply;
--json outputs the full response, including token usage.

Examples:
  bash scripts/chat.sh "Explain what an AI gateway does."
  printf '%s\n' "Write a short greeting." | bash scripts/chat.sh
  bash scripts/chat.sh --system "Be concise." --json "What is Kong?"

Local .env settings are loaded automatically. AIGW_PROXY_PORT defaults to 8000.
Requires curl and jq. Each request uses your configured OpenAI account.
EOF
}

fail() { printf 'Error: %s\n' "$*" >&2; exit 1; }

system_prompt=""
json_output=false
while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help) usage; exit 0 ;;
    --system)
      [[ $# -ge 2 ]] || fail "--system requires text"
      system_prompt="$2"
      shift 2
      ;;
    --json) json_output=true; shift ;;
    --) shift; break ;;
    -*) fail "Unknown option: $1 (use -- before a prompt starting with '-')" ;;
    *) break ;;
  esac
done

if [[ $# -gt 0 ]]; then
  prompt="$*"
elif [[ ! -t 0 ]]; then
  prompt="$(cat)"
else
  usage >&2
  exit 1
fi
[[ "$prompt" =~ [^[:space:]] ]] || fail "Supply a nonempty prompt"
for tool in curl jq; do
  command -v "$tool" >/dev/null 2>&1 || fail "$tool is required"
done

project_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if [[ -f "${project_dir}/.env" ]]; then
  set -a
  source "${project_dir}/.env"
  set +a
fi
proxy_port="${AIGW_PROXY_PORT:-8000}"
[[ "$proxy_port" =~ ^[1-9][0-9]{0,4}$ ]] && (( proxy_port <= 65535 )) ||
  fail "AIGW_PROXY_PORT must be an integer from 1 to 65535"

payload="$(jq -n --arg prompt "$prompt" --arg system "$system_prompt" '{
  model: "demo-chat",
  messages: ((if $system != "" then [{role: "system", content: $system}] else [] end)
    + [{role: "user", content: $prompt}]),
  max_tokens: 256
}')"
if response="$(curl --fail-with-body --silent --show-error --max-time 60 \
  "http://127.0.0.1:${proxy_port}/v1/chat/completions" \
  -H 'Content-Type: application/json' --data-binary "$payload")"; then
  if ! jq -e '.choices[0].message.content | select(type == "string" and length > 0)' \
    >/dev/null 2>&1 <<< "$response"; then
    printf '%s\n' "$response" >&2
    fail "Gateway response did not contain an assistant reply"
  fi
else
  [[ -z "$response" ]] || printf '%s\n' "$response" >&2
  fail "Chat request failed; check the gateway is running with bash data-plane.sh status"
fi

if [[ "$json_output" == true ]]; then
  jq '.' <<< "$response"
else
  jq -r '.choices[0].message.content' <<< "$response"
fi
