# Summit local Kong AI Gateway

This project runs a Kong AI Gateway 2.0 data plane in Docker and manages its Konnect configuration with `kongctl`. The demo proxy listens only on `127.0.0.1:8000` (HTTP) and `127.0.0.1:8443` (HTTPS). The client-facing model alias is `demo-chat`; it routes to OpenAI `gpt-4o-mini`.

## Configuration and ownership

- Manifest: `ai-gateway.yaml`
- Konnect profile and region: `default`, US
- Konnect organization ID used for the initial deployment: `bc68a981-db50-43b4-a6bc-6a3ab0557d3c`
- Namespace and gateway name: `summit-ai-demo`
- Gateway display name: `Summit AI Demo`
- Local container: `summit-ai-demo-data-plane`

The OpenAI provider credential is loaded from `OPENAI_API_KEY` in the local `.env` only when applying a plan. `kongctl` does not load `.env` automatically. The manifest uses a deferred `!secret`, so the key is absent from the YAML and saved plan. Keep `.env` and `certs/data-plane.key` private; both are ignored by Git. The public `certs/data-plane.crt` is referenced by the manifest and should be kept with it. Preserve the matching private key for this data plane. If you replace the pair, create and apply a new plan before starting the container.

## Reconcile Konnect

Run from this directory with `kongctl` authenticated to the intended organization (`kongctl login` or the `KONGCTL_DEFAULT_KONNECT_PAT` environment variable). Confirm the organization ID above before applying changes:

```bash
mkdir -p .plans .artifacts
kongctl get organization -o json --jq '.id' --jq-raw-output --log-file .artifacts/kongctl.log
bash data-plane.sh certs
kongctl plan --mode apply -f ai-gateway.yaml \
  --require-namespace summit-ai-demo \
  --output-file .plans/apply.json --log-file .artifacts/kongctl.log
kongctl diff --plan .plans/apply.json --log-file .artifacts/kongctl.log
set -a
source ./.env
set +a
kongctl apply --plan .plans/apply.json -o json --auto-approve \
  --execution-report-file .artifacts/apply-report.json \
  --log-file .artifacts/kongctl.log
```

Review the diff before applying. `apply` creates or updates the declared resources. Use a fresh plan whenever the manifest, certificate, profile, or target organization changes. The initial plan created four resources: the gateway, data plane certificate, OpenAI provider, and model.

## Run the local data plane

The helper checks for existing containers and occupied ports before starting. It never replaces an existing container. Use `bash data-plane.sh status` to inspect local state and `bash data-plane.sh check` to verify the certificate pair.

```bash
set -a
source ./.env
set +a
bash data-plane.sh preflight
gateway_json="$(kongctl get ai-gateway 'Summit AI Demo' -o json \
  --log-file .artifacts/kongctl.log)"
export AIGW_CONTROL_PLANE="$(jq -r '.endpoints.configuration | sub("^https://"; "") | sub(":443$"; "")' <<< "$gateway_json")"
export AIGW_TELEMETRY="$(jq -r '.endpoints.telemetry | sub("^https://"; "") | sub(":443$"; "")' <<< "$gateway_json")"
bash data-plane.sh run
kongctl get ai-gateway nodes --gateway-name 'Summit AI Demo' \
  --log-file .artifacts/kongctl.log
```

If the data plane does not register, inspect `docker logs summit-ai-demo-data-plane` and check outbound TLS to both discovered endpoints. A Docker restart resolved an initial connection timeout during this deployment.

## Verify and stop

One small inference request confirms routing, provider authentication, and a real model completion:

```bash
set -o pipefail
curl --fail-with-body --silent --show-error --max-time 60 \
  "http://127.0.0.1:${AIGW_PROXY_PORT:-8000}/v1/chat/completions" \
  -H 'Content-Type: application/json' \
  -d '{"model":"demo-chat","messages":[{"role":"user","content":"Reply with a short greeting."}]}' \
  | jq -e '.choices[0].message.content | select(type == "string" and length > 0)'
```

The proxy has no caller authentication in this local demo, so keep its port bound to loopback. Stop the local container with `bash data-plane.sh stop`; that does not remove Konnect resources. To remove the Konnect resources deliberately, create a `--mode delete` plan with the same namespace guard, inspect it with `kongctl diff --plan`, then execute `kongctl delete --plan` only for the intended scope. Deleting the gateway also removes its child resources. A scoped preview is saved locally at `.plans/delete-preview.json`; generate a fresh plan before any later deletion.

If you change `AIGW_PROXY_PORT`, also update `proxy_urls[].port` in `ai-gateway.yaml` and replan. If you change the upstream model, update `targets[].name` while keeping the `demo-chat` client alias stable.

## Deploy reviewed changes with GitHub Actions

`.github/workflows/deploy-ai-gateway.yaml` manually applies the exact committed `ci/plan.json`. It checks the plan SHA-256, apply mode, `kongctl` version, namespace, default branch, and Konnect organization before execution. The workflow uses the existing GitHub repository secrets `KONNECT_APPLY_PAT` and `OPENAI_API_KEY`; it records the diff and execution report as a short-lived Actions artifact. The runner applies Konnect configuration only. The Docker data plane continues to run on this host.

For each change, edit `ai-gateway.yaml`, generate and review a fresh plan against the same Konnect organization, and commit the manifest, public certificate (if changed), plan, and workflow together:

```bash
mkdir -p ci .artifacts
kongctl get organization --profile default --base-url https://us.api.konghq.com \
  -o json --jq '.id' --jq-raw-output --log-file .artifacts/kongctl.log
kongctl plan --mode apply -f ai-gateway.yaml --profile default \
  --base-url https://us.api.konghq.com \
  --require-namespace summit-ai-demo \
  --output-file ci/plan.json --log-file .artifacts/kongctl.log
kongctl diff --plan ci/plan.json --log-file .artifacts/kongctl.log
shasum -a 256 ci/plan.json
```

Confirm the organization ID matches the one above, inspect every proposed change and any secret writes, then publish through the repository's review process. The workflow must be present on `main` before its first manual dispatch. A repository writer can run it from GitHub Actions or with:

```bash
gh workflow run deploy-ai-gateway.yaml --ref main \
  -f plan_sha256="$(shasum -a 256 ci/plan.json | cut -d ' ' -f 1)"
```

Use the SHA-256 from the reviewed plan on `main`; if files change after review, generate and review a new plan. Check the run's execution report, then run the local inference check above and generate a fresh apply plan to confirm convergence. GitHub-hosted runners cannot reach this host's loopback proxy. The first committed `ci/plan.json` has zero changes and is intended to smoke test the deployment workflow.
