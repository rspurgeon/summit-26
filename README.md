# Local OpenAI AI Gateway

Native Kong AI Gateway: a local Docker data plane receives declarative configuration
from a Konnect control plane. Requests stay on loopback at
`http://127.0.0.1:8000/v1/chat/completions`. The public model alias `demo-chat`
routes to OpenAI `gpt-4.1-mini`.

Configuration lives in `ai-gateway.yaml`, owned by namespace `summit-ai-demo`.
The gateway is named `summit-ai-demo` and displayed as **Summit AI Demo**.
The setup uses kongctl 1.20.1 and `kong/kong-ai-gateway:2.0.3`.
The helper pins the verified multi-platform image digest
`sha256:367ed5985b7648e4fdd6e1d7857562d24a5fb5a1db4985876b16d5b35eec84cb`.

Verified on September 30, 2026: all four resources were provisioned in region `us`,
the local node connected with fully compatible runtime 2.0.3, and one request
returned "Hello! How can I assist you today?". An unchanged follow-up plan
reported no changes. Local evidence is saved in `.artifacts/apply-report.json`,
`.artifacts/nodes.json`, `.artifacts/smoke-completion.json`, and
`.plans/follow-up.json`.

## Prerequisites

Install kongctl with native `ai_gateways` support, Docker, OpenSSL, curl, and jq.
Start your Docker engine (Rancher Desktop on this machine).
Your trusted, shell-compatible `.env` must contain `OPENAI_API_KEY`, `KONNECT_PAT`,
and `KONNECT_REGION`. `gateway.sh` loads it without printing credentials and maps
`KONNECT_PAT` to `KONGCTL_DEFAULT_KONNECT_PAT` for the default profile.
Every remote command passes the same explicit region and profile.
Environment variables also work when `.env` is absent. GitHub Actions uses the existing
`KONNECT_PAT` and `OPENAI_API_KEY` repository secrets and the `KONNECT_REGION`
repository variable (`us`).

## Provision and start

```bash
bash gateway.sh status
bash gateway.sh preflight
bash gateway.sh certs
bash gateway.sh check
bash gateway.sh plan
```

Review the diff, organization ID, and region. The plan is additive (`--mode apply`)
and restricted to `summit-ai-demo`; it does not delete omitted resources.
The saved plan is `.plans/apply.json`, with its target in `.plans/target.json`.
The OpenAI key is a deferred `!secret`: apply writes it to the provider's
Authorization header, while YAML contains only the environment reference.

After approving that concrete plan:

```bash
bash gateway.sh apply
bash gateway.sh up
bash gateway.sh nodes
# Wait for the node to connect and receive configuration, then make one small paid request:
bash gateway.sh smoke
```

`apply` requests CLI confirmation. `up` discovers actual configuration and telemetry
endpoints from Konnect, mounts the mTLS certificate pair read-only, and starts Docker.
The proxy binds HTTP 8000 and HTTPS 8443 to `127.0.0.1` only. No caller key is configured
for this local demo. The OpenAI provider key belongs in Konnect configuration and is
not needed in client headers or Docker environment variables.

If a container already exists, inspect it before restarting or replacing it:
`bash gateway.sh status` and `docker logs summit-ai-demo-data-plane`.
The helper refuses to overwrite containers or certificate pairs.

## Change configuration

Send your own test prompt through the local gateway:

```bash
./ask.sh 'Explain what an AI Gateway does in one sentence.'
```

The script safely encodes the prompt as JSON and prints the assistant's reply.
It requests at most 256 output tokens. If your gateway uses a different HTTP
port, pass it as `AIGW_PROXY_PORT=8001 ./ask.sh 'Your prompt'`.

Edit the YAML, then run `plan`, review `diff`, and run `apply`.
Keep the namespace, resource refs, gateway name, and certificate pair stable.
After an unchanged apply, replan to check for drift. Routine runs do not force
secret rewrites; for deliberate key rotation, generate and review a new plan using
`bash gateway.sh ctl plan --mode apply -f ai-gateway.yaml --require-namespace summit-ai-demo --write-secrets --output-file .plans/rotation.json`.
Then inspect `bash gateway.sh ctl diff --plan .plans/rotation.json` and apply that
reviewed plan with `bash gateway.sh ctl apply --plan .plans/rotation.json -o text`.

Optional `.env` settings are documented in `.env.example`. If HTTP host port changes,
also change `proxy_urls[].port` in the manifest before planning. The upstream model
ID is committed in YAML so model changes appear in configuration review.

Only the public certificate `certs/data-plane.crt` belongs in source control.
Never commit `.env`, private keys, `.plans`, or `.artifacts`; those paths are ignored.
Logs, endpoints, and the smoke completion stay in `.artifacts`.

## GitHub Actions CI/CD

`.github/workflows/deploy-ai-gateway.yaml` manages the existing gateway in
namespace `summit-ai-demo`, organization `bc68a981-db50-43b4-a6bc-6a3ab0557d3c`,
using kongctl 1.20.1 and the repository's existing credentials and controls.

On a same-repository PR to `main` changing the manifest, public certificates,
workflow, or `ci/plan.json`, the planning job:

1. Generates an additive plan with `--mode apply` and the namespace guard.
2. Retains the committed plan bytes if only the generation timestamp differs.
3. Runs `kongctl diff --plan ci/plan.json` against that exact file.
4. Commits a changed plan to the PR branch without force-pushing.
5. Replaces only the `<!-- ai-gateway-plan:start -->` / `<!-- ai-gateway-plan:end -->`
   section in the PR description with the diff, target, plan commit, and SHA-256.

Review the plan commit and marked diff using the repository's normal PR process.
When a merge updates `ci/plan.json` on `main`, the deployment job validates its
apply mode, CLI version, namespace, actions, and allowed deferred secret sources,
checks the live organization, and applies the committed file without regenerating
it. Execution evidence is retained as a workflow artifact for seven days.
A config-only push to `main` does not deploy; a direct plan-file push to `main`
also qualifies under the existing repository controls.

Planning uses only the Konnect credential. Deployment additionally supplies
`OPENAI_API_KEY` for deferred secret writes. Private keys and `.env` stay local;
the Docker data plane continues receiving updated configuration from Konnect.
The workflow neither starts Docker nor sends inference requests from CI.

Run the independent, read-only drift check:

```bash
gh workflow run deploy-ai-gateway.yaml --ref main -f expect_no_changes=true
```

The default is `true`: any resource change or secret write fails the check while
retaining the saved plan and diff as artifacts. Use `-f expect_no_changes=false`
to inspect proposed changes without asserting convergence. Manual dispatch never
commits a plan or deploys. This additive check covers declared resources;
it does not detect extra remote resources omitted from the manifest.

Only planning receives repository write permissions. Fork PRs and bot-triggered
planning are skipped. Same-repository writers are trusted with the existing shared
Konnect credential. GitHub may require a writer to approve additional workflow
runs created by the bot's PR update; use **Approve workflows to run** when shown.
No additional token, environment gate, or repository policy is introduced.
See [GitHub's token-trigger behavior](https://docs.github.com/en/actions/how-tos/write-workflows/choose-when-workflows-run/trigger-a-workflow).

## Stop and remove

`bash gateway.sh stop` stops only this project's container; Konnect configuration
and the certificate pair remain available for reuse.
To remove remote resources deliberately:

```bash
bash gateway.sh ctl plan --mode delete -f ai-gateway.yaml \
  --require-namespace summit-ai-demo --output-file .plans/delete.json
bash gateway.sh ctl diff --plan .plans/delete.json
# Only after reviewing and approving the gateway and child-resource removals:
bash gateway.sh ctl delete --plan .plans/delete.json -o text
```

Kong's architecture and management documentation:
https://developer.konghq.com/ai-gateway/
