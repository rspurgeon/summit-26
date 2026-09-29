# Local OpenAI AI Gateway

This project manages a native Konnect AI Gateway with kongctl. Its data plane
runs locally in Docker, using the Konnect configuration and telemetry channels.
The `demo-chat` request alias routes to OpenAI `gpt-4o-mini`.

Use kongctl 1.19.0, Docker, OpenSSL, curl and jq. The data plane image is
`kong/kong-ai-gateway:2.0.3`. The configuration follows Kong's
[OpenAI quickstart](https://github.com/Kong/kongctl/tree/main/docs/examples/declarative/ai-gateway/openai-llm).

Put `OPENAI_API_KEY`, `KONNECT_PAT`, and `KONNECT_REGION` in the trusted,
shell-compatible `.env` file, or export them. `gateway.sh` loads `.env` and
maps `KONNECT_PAT` to `KONGCTL_DEFAULT_KONNECT_PAT`. It uses the `default`
profile and the explicit region. GitHub secrets are only needed if CI is added.

The gateway name and namespace are `summit-ai-demo`; its display name is
`Summit AI Demo`. The container is `summit-ai-demo-data-plane`. HTTP and
HTTPS are bound to loopback on 8000 and 8443. If you change the HTTP port,
update `proxy_urls` in `ai-gateway.yaml` and generate a new plan.

## Prepare and review

```sh
bash gateway.sh status
bash gateway.sh preflight
bash gateway.sh certs
bash gateway.sh check
bash gateway.sh plan
```

Review `.plans/apply.json` and its displayed diff, organization ID, region,
namespace and secret writes before applying. Plan uses additive `apply` mode.
After approving this exact saved plan:

```sh
bash gateway.sh apply
bash gateway.sh run
bash gateway.sh nodes
```

Allow the node to connect and configuration to propagate. Then send one small
OpenAI request (billed to the provider account):

```sh
bash gateway.sh smoke
```

The endpoint is `http://127.0.0.1:8000/v1/chat/completions`, with the body model
`demo-chat`. The provider credential is added by the gateway. A nonempty
assistant completion confirms inference. Inspect `docker logs
summit-ai-demo-data-plane` if the node fails to connect.

## Configuration and secrets

Edit `ai-gateway.yaml` and repeat plan, review and apply for future changes.
The OpenAI key uses deferred `!secret` resolution during apply; it is absent
from the manifest and saved plan. Routine apply does not rotate write-only
secrets. The certificate is public and may be committed; the matching private
key remains local. `.env`, private keys, plans and local evidence are ignored.
Keep the certificate pair for subsequent runs.

## Deploy configuration with GitHub Actions

The workflow `.github/workflows/deploy-ai-gateway.yaml` previews live changes
on trusted pull requests to `main`. Deployment is a manual dispatch on `main`
that applies the exact committed `ci/plan.json` reviewed by the operator.
It checks the plan hash, kongctl version, namespace, additive actions, allowed
secret sources, organization ID and region before execution. The existing
repository secrets `KONNECT_PAT` and `OPENAI_API_KEY`, and repository variable
`KONNECT_REGION=us`, supply its inputs.

For each change, edit the manifest and prepare a new plan:

```sh
bash gateway.sh plan
cp .plans/apply.json ci/plan.json
shasum -a 256 ci/plan.json
```

Review the diff and hash, then commit the manifest, public certificate,
`ci/plan.json`, and workflow through your normal source review process.
Once they are on `main`, explicitly approve deployment by dispatching with
the reviewed hash:

```sh
gh workflow run deploy-ai-gateway.yaml --ref main \
  -f plan_sha256=THE_REVIEWED_SHA256
gh run list --workflow deploy-ai-gateway.yaml
```

The workflow must first be published on the default branch to dispatch it.
This is operator approval; it does not require a second reviewer. Deployment
does not replan, and PR previews do not replace saved-plan review. Do not rerun
a completed create plan; generate a fresh plan for subsequent deployments.
Execution reports are retained as GitHub artifacts for seven days.

GitHub deploys Konnect configuration. Start the Docker data plane and verify
inference on this laptop with `bash gateway.sh run` and `bash gateway.sh smoke`.
After a successful deployment, generate a fresh plan to confirm convergence.

For a drift check, save another apply plan and inspect its diff; avoid replacing
an approved plan before executing it. Execution evidence goes in `.artifacts`.

## Stop and clean up

```sh
bash gateway.sh stop
```

Stopping Docker leaves Konnect resources intact. For deliberate remote cleanup,
load `.env`, map the PAT as above, and generate a delete plan with the same target:

```sh
set -a
source .env
set +a
export KONGCTL_DEFAULT_KONNECT_PAT="$KONNECT_PAT"
kongctl plan --mode delete -f ai-gateway.yaml --profile default \
  --region "$KONNECT_REGION" --require-namespace summit-ai-demo \
  --log-file .artifacts/kongctl.log --output-file .plans/delete.json
kongctl diff --plan .plans/delete.json --profile default \
  --region "$KONNECT_REGION" --log-file .artifacts/kongctl.log
```

Review and approve the gateway and child-resource removals before running
`kongctl delete --plan .plans/delete.json` with that same profile and region.
