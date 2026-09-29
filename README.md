# Local Kong AI Gateway with OpenAI

This project declares one Konnect AI Gateway in the `summit-ai-demo` namespace. Its local Docker data plane serves OpenAI-compatible chat requests at `http://127.0.0.1:8000/v1/chat/completions`. The model aliases are `demo-chat` for `gpt-4o-mini` and `budget-chat` for `gpt-4.1-nano`.

## Inputs and local files

- `.env` supplies `OPENAI_API_KEY`, `KONNECT_TOKEN`, and `KONNECT_REGION`. It is ignored by Git. See `.env.example` for optional Docker settings.
- `ai-gateway.yaml` is the declarative Konnect configuration. The OpenAI key is a deferred `!secret`; the key is supplied only when the reviewed plan is applied.
- `certs/data-plane.crt` is the public certificate registered in Konnect. `certs/data-plane.key` is ignored by Git and stays on this machine.
- `data-plane.sh` manages the local Docker node. Its proxy ports bind to loopback only. No caller authentication is configured for this local demo.

The existing certificate pair can be checked with `bash data-plane.sh check`. If starting from a fresh checkout, run `bash data-plane.sh certs` before planning. Keep this pair when reusing the same gateway.

## Local review and apply

Use kongctl 1.17.1 and load the local environment in every shell used for kongctl commands. The `.env` file must be trusted shell-compatible input.

```sh
set -a
. ./.env
set +a
export KONGCTL_DEFAULT_KONNECT_PAT="$KONNECT_TOKEN"
mkdir -p .plans .artifacts
```

Generate a fresh plan for the current manifest and region, then review its diff before applying locally:

```sh
kongctl --log-file .artifacts/kongctl.log plan --mode apply \
  -f ai-gateway.yaml --region "$KONNECT_REGION" \
  --require-namespace summit-ai-demo --output-file .plans/apply.json
kongctl --log-file .artifacts/kongctl.log diff --plan .plans/apply.json -o text
```

After approving that exact plan and target, provision the Konnect resources:

```sh
kongctl --log-file .artifacts/kongctl.log apply --plan .plans/apply.json \
  --region "$KONNECT_REGION" \
  -o json --auto-approve --execution-report-file .artifacts/apply-report.json
```

## Run and verify the local data plane

Check Docker and port availability with `bash data-plane.sh status` and `bash data-plane.sh preflight`. Once the Konnect apply succeeds, discover its actual endpoints:

```sh
export AIGW_CONTROL_PLANE="$(kongctl --log-file .artifacts/kongctl.log \
  get ai-gateway 'Summit AI Demo' --region "$KONNECT_REGION" -o json \
  --jq '.endpoints.configuration | sub("^https://"; "") | sub(":443$"; "")' -r)"
export AIGW_TELEMETRY="$(kongctl --log-file .artifacts/kongctl.log \
  get ai-gateway 'Summit AI Demo' --region "$KONNECT_REGION" -o json \
  --jq '.endpoints.telemetry | sub("^https://"; "") | sub(":443$"; "")' -r)"
bash data-plane.sh run
kongctl --log-file .artifacts/kongctl.log get ai-gateway nodes \
  --gateway-name 'Summit AI Demo' --region "$KONNECT_REGION"
```

The helper rejects empty or invalid endpoint hostnames. If the node does not connect, inspect `docker logs "${AIGW_CONTAINER_NAME:-summit-ai-demo-data-plane}"` and the endpoint values. The OpenAI key belongs in the Konnect provider configuration; it is not sent by callers to the local proxy.

Send one small inference request after the node connects:

```sh
set -o pipefail
curl --fail-with-body --silent --show-error --max-time 60 \
  "http://127.0.0.1:${AIGW_PROXY_PORT:-8000}/v1/chat/completions" \
  -H 'Content-Type: application/json' \
  -d '{"model":"demo-chat","messages":[{"role":"user","content":"Reply with a short greeting."}]}' \
  | jq -e '.choices[0].message.content | select(type == "string" and length > 0)'
```

After deploying the additional model, use `"model":"budget-chat"` in the same request body to route to `gpt-4.1-nano`.

Stop only this local node with `bash data-plane.sh stop`. To remove the Konnect gateway later, create and review a `--mode delete` plan for `summit-ai-demo` before running `kongctl delete --plan`; deletion includes its child resources. Keep the certificate pair if you intend to redeploy it.

## Deploy later changes through GitHub Actions

The manual [deployment workflow](.github/workflows/deploy-ai-gateway.yaml) runs only from this repository's default branch. It checks the SHA-256 of committed `ci/plan.json`, verifies the plan's `kongctl` version, apply mode, and namespace, confirms the Konnect organization, and applies the reviewed plan. It uses the existing GitHub secrets `KONNECT_APPLY_PAT` and `OPENAI_API_KEY`. The run uploads its diff and execution report as a short-lived artifact.

The committed plan is the next reviewed change for this gateway. Its hash is printed by `shasum -a 256 ci/plan.json`; review the diff before dispatching it. The workflow reads the plan from `main`, so the plan and manifest must be merged there before dispatch.

For each later configuration change, use **kongctl 1.17.1** locally, edit `ai-gateway.yaml`, and generate a new apply-mode plan against the same organization and region:

```sh
set -a
. ./.env
set +a
export KONGCTL_DEFAULT_KONNECT_PAT="$KONNECT_TOKEN"
kongctl plan --mode apply -f ai-gateway.yaml --profile default \
  --base-url https://us.api.konghq.com \
  --require-namespace summit-ai-demo --output-file ci/plan.json
kongctl diff --plan ci/plan.json
shasum -a 256 ci/plan.json
```

Review the exact diff and hash, then commit `ci/plan.json` with the manifest and any public certificate changes. Merge them through the repository's source-review process. A repository writer can then dispatch the workflow with that exact hash:

```sh
gh workflow run deploy-ai-gateway.yaml --ref main \
  -f plan_sha256=THE_REVIEWED_SHA256
```

GitHub Actions runs on a remote machine. Check inference through this project's local data plane after the run, and generate a fresh local plan to confirm zero drift. Do not reuse an old saved create plan for later changes.
