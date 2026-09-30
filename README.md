# Local OpenAI AI Gateway

This project manages a native Konnect AI Gateway with kongctl. Its data plane
runs locally in Docker, using the Konnect configuration and telemetry channels.
The `demo-chat` request alias routes to OpenAI `gpt-4o-mini`.
The `demo-nano` alias routes to `gpt-4.1-nano`, another low-cost model.
The `demo-mini` alias routes to `gpt-4.1-mini` once its saved plan is deployed.

Use kongctl 1.19.0, Docker, OpenSSL, curl and jq. The data plane image is
`kong/kong-ai-gateway:2.0.3`. The configuration follows Kong's
[OpenAI quickstart](https://github.com/Kong/kongctl/tree/main/docs/examples/declarative/ai-gateway/openai-llm).

Put `OPENAI_API_KEY`, `KONNECT_PAT`, and `KONNECT_REGION` in the trusted,
shell-compatible `.env` file, or export them. `gateway.sh` loads `.env` and
maps `KONNECT_PAT` to `KONGCTL_DEFAULT_KONNECT_PAT`. It uses the `default`
profile and the explicit region. GitHub Actions uses the repository secrets.

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

After deploying the plan that adds `demo-nano`, request it through the same endpoint:

```sh
curl --fail-with-body --silent --show-error --max-time 60 \
  http://127.0.0.1:8000/v1/chat/completions \
  -H 'Content-Type: application/json' \
  -d '{"model":"demo-nano","messages":[{"role":"user","content":"Reply with a short greeting."}],"max_tokens":32}'
```

After deploying the third-model plan, use `"model":"demo-mini"` in the same
request to select `gpt-4.1-mini`.

## Configuration and secrets

Edit `ai-gateway.yaml` and repeat plan, review and apply for future changes.
The OpenAI key uses deferred `!secret` resolution during apply; it is absent
from the manifest and saved plan. Routine apply does not rotate write-only
secrets. The certificate is public and may be committed; the matching private
key remains local. `.env`, private keys, plans and local evidence are ignored.
Keep the certificate pair for subsequent runs.

## Deploy configuration with GitHub Actions

The workflow `.github/workflows/deploy-ai-gateway.yaml` detects changes to
`ai-gateway.yaml`, public certificates, the plan, and the workflow on trusted
same-repository pull requests to `main`. It generates an additive plan with
`kongctl plan --mode apply`, renders that exact file with `kongctl diff --plan`,
commits it as `ci/plan.json` on the PR branch, and updates a marked section of
the PR description with the diff, target, commit and SHA-256. Existing PR prose
is preserved. Fork and Dependabot PRs are skipped because they lack credentials.

For each change, edit the manifest and open or update a PR. Review the generated
plan commit and the diff in its description. Merging the PR is deployment
approval: a push to `main` that changes `ci/plan.json` automatically applies the
committed file using `kongctl apply --plan ci/plan.json --auto-approve`.
The deployment does not regenerate the plan. Updating configuration on `main`
without updating the plan does not deploy. A direct push changing the plan also
triggers deployment; use the repository's PR review process for changes.

The existing repository secrets `KONNECT_PAT` and `OPENAI_API_KEY`, plus variable
`KONNECT_REGION=us`, supply inputs. Planning uses only the Konnect credential;
provider secrets remain deferred until apply. The planning job has contents and
pull-request write permissions to commit the plan and edit the description;
deployment needs only contents read permission. The workflow rejects stale PR
heads rather than overwriting newer commits, and ignores bot-triggered planning
runs to avoid recursive plan commits.

The committed-plan guard checks kongctl version, namespace, additive actions
and allowed secret sources. Deployment also verifies the organization and region.
Planning and deployment evidence are retained for seven days. Review the plan
again after conflicting configuration changes or remote drift; do not rerun a
completed create plan. A local plan remains available via `bash gateway.sh plan`.

### Manual drift check

Run **Plan and deploy AI Gateway** from the Actions tab, select `main`, and
leave **Fail the drift check if the plan contains changes** enabled to prove
the deployed configuration is a no-op. From the CLI:

```sh
gh workflow run deploy-ai-gateway.yaml --ref main -f expect_no_changes=true
```

Manual dispatch runs only the read-only drift job: it generates a fresh plan,
renders that saved file with `kongctl diff --plan`, publishes the diff in the
Actions summary, and uploads the plan and evidence for seven days. It neither
commits `ci/plan.json` nor applies changes. Disable `expect_no_changes` to inspect
a selected branch's proposed changes without failing when changes are present.
The check uses additive apply mode, so it checks configured resources without
proposing deletion of extra remote resources.

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
