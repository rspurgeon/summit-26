#!/usr/bin/env bash
set -euo pipefail

project_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -f "${project_dir}/.env" ]]; then
  # Reuse the trusted local port setting; no credentials are sent by this client.
  source "${project_dir}/.env"
fi

usage() {
  cat <<'EOF'
Usage: ./chat.sh [--json] [--model ALIAS] [--system TEXT] PROMPT
       printf '%s' 'Your prompt' | ./chat.sh [options]

Send a single chat request through the local Kong AI Gateway.
  --json          Print the complete JSON response instead of assistant text
  --model ALIAS   Gateway model alias (default: demo-chat)
  --system TEXT   Optional system instruction
  --              Treat remaining arguments as prompt text
  -h, --help      Show this help

Settings: AIGW_URL (default: http://127.0.0.1:${AIGW_PROXY_PORT:-8000}),
          AIGW_MAX_TOKENS (default: 512), AIGW_TIMEOUT (default: 60 seconds).
Each invocation sends one request and starts a new conversation.
EOF
}

fail() { printf 'Error: %s\n' "$*" >&2; exit 1; }
model=demo-chat
system_prompt=''
json_output=false
while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help) usage; exit 0 ;;
    --json) json_output=true; shift ;;
    --model|--system)
      [[ $# -ge 2 && -n "$2" ]] || fail "$1 requires a value"
      if [[ "$1" == --model ]]; then model="$2"; else system_prompt="$2"; fi
      shift 2
      ;;
    --) shift; break ;;
    -*) fail "Unknown option: $1 (use -- before a prompt beginning with '-')" ;;
    *) break ;;
  esac
done

for tool in curl jq; do
  command -v "$tool" >/dev/null 2>&1 || fail "$tool is required"
done
if [[ $# -gt 0 ]]; then
  prompt="$*"
elif [[ ! -t 0 ]]; then
  prompt="$(cat)"
else
  usage >&2
  exit 1
fi
[[ "$prompt" =~ [^[:space:]] ]] || fail 'Provide a nonempty prompt as arguments or through stdin'
max_tokens="${AIGW_MAX_TOKENS:-512}"
[[ "$max_tokens" =~ ^[1-9][0-9]*$ ]] || fail 'AIGW_MAX_TOKENS must be a positive integer'
url="${AIGW_URL:-http://127.0.0.1:${AIGW_PROXY_PORT:-8000}}"
payload="$(jq -n --arg model "$model" --arg prompt "$prompt" \
  --arg system "$system_prompt" --argjson max_tokens "$max_tokens" \
  '{model: $model, messages: ((if $system == "" then [] else [{role: "system", content: $system}] end) + [{role: "user", content: $prompt}]), max_tokens: $max_tokens}')"
response_file="$(mktemp "${TMPDIR:-/tmp}/summit-chat.XXXXXX")"
trap 'rm -f "$response_file"' EXIT
if curl --fail-with-body --silent --show-error \
  --connect-timeout 5 --max-time "${AIGW_TIMEOUT:-60}" \
  "${url%/}/v1/chat/completions" \
  -H 'Content-Type: application/json' \
  --data-binary "$payload" --output "$response_file"; then
  if [[ "$json_output" == true ]]; then
    jq . "$response_file"
  else
    jq -er '.choices[0].message.content | select(type == "string" and length > 0)' "$response_file" \
      || fail 'Gateway response has no assistant text; use --json to inspect it'
  fi
else
  curl_code=$?
  [[ ! -s "$response_file" ]] || cat "$response_file" >&2
  printf '\nRequest to %s failed. Check the gateway with bash %s/gateway.sh status.\n' "$url" "$project_dir" >&2
  exit "$curl_code"
fi
