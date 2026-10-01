# Local Kong AI Gateway with OpenAI

This repository manages a native Konnect AI Gateway declaratively with
kongctl. Its Docker data plane runs locally; Konnect hosts its control plane.
The client model alias `demo-chat` routes to OpenAI `gpt-4.1-mini`.
The lower-cost alias `demo-chat-nano` routes to OpenAI `gpt-4.1-nano`
through the same endpoint and provider.

The manifests are `ai-gateway.yaml` and `portal.yaml`, owned by namespace
`summit-ai-demo`.
The gateway name is `summit-ai-demo`, with display name `Summit AI Demo`.
Tooling checked during setup: kongctl 1.20.1, Docker, OpenSSL, curl and jq.
The runtime image is `kong/kong-ai-gateway:2.0.3`, pinned in the helper and
example environment to digest
`sha256:367ed5985b7648e4fdd6e1d7857562d24a5fb5a1db4985876b16d5b35eec84cb`.
An explicit `KONG_AI_GATEWAY_IMAGE` setting overrides this default.

## Inputs

Keep `OPENAI_API_KEY`, `KONNECT_PAT` and `KONNECT_REGION` in the existing
trusted, shell-compatible `.env`. `gateway.sh` loads it and maps the PAT to
`KONGCTL_DEFAULT_KONNECT_PAT`; commands use the default profile and explicit
region (`us` for this setup). The same variable names can be supplied by CI.
Provider credentials use deferred `!secret` values and stay out of YAML and
saved plans. GitHub secrets alone do not populate a local shell.

See `.env.example` for local container settings. HTTP port changes must also
update `proxy_urls[].port` in `ai-gateway.yaml` before replanning.
The proxy binds only to `127.0.0.1:8000` and `127.0.0.1:8443` and has no
caller authentication in this local demo.

## Provision and run

Docker must be running. Generate the local certificate pair and a saved,
additive plan, then review the diff, organization ID in
`.plans/organization-id`, and region in `.plans/region`:

```sh
bash gateway.sh plan
```

After approving that exact plan and target, provision the Konnect resources:

```sh
bash gateway.sh apply
bash gateway.sh start
bash gateway.sh nodes
```

Allow the node to connect and receive configuration. Inspect
`docker logs summit-ai-demo-data-plane` if necessary. Once connected, run
one small, paid OpenAI request and assert a nonempty assistant completion:

```sh
bash gateway.sh smoke
```

The request goes to `http://127.0.0.1:8000/v1/chat/completions` using model
`demo-chat`. Clients do not need the provider key. Results remain locally
under ignored `.artifacts/`.

## Chat from your terminal

Use `chat.sh` to send a prompt and print the assistant's reply:

```sh
./chat.sh "Explain what an AI gateway does in two sentences."
printf '%s' 'Give me three names for a hiking app.' | ./chat.sh
./chat.sh --system "Answer concisely." "What is Kong?"
./chat.sh --json "Say hello."
./chat.sh --model demo-chat-nano "Suggest three hiking app names."
```

The script works from any directory when invoked by its full path. It reads
the project's trusted `.env` for the local port and sends requests through
`demo-chat`. Each invocation starts a new conversation and can generate
OpenAI usage charges. Use `--model` for another configured gateway alias.
`AIGW_URL` overrides the gateway base URL; `AIGW_MAX_TOKENS` defaults to 512
and `AIGW_TIMEOUT` to 60 seconds. Run `./chat.sh --help` for usage.

`certs/data-plane.crt` is public and may be committed. The matching private
key is ignored and must remain on this host. The helper reuses matching
certificates and refuses to replace incomplete or mismatched pairs.
Use `AIGW_DATA_PLANE_KEY` for an absolute path to an existing private key.

## Manage changes and cleanup

Edit either manifest and generate a new plan for review. For a running gateway,
use `bash gateway.sh drift` to plan without the new-container preflight.
Review `.plans/follow-up.json`; do not execute an older plan after changing
inputs. `bash gateway.sh plan` is intended for initial setup, when the
project container does not exist.

```sh
bash gateway.sh status
bash gateway.sh check
bash gateway.sh drift
bash gateway.sh stop
```

Stopping removes only this project's local container. To remove the Konnect
resources declared in both manifests (gateway, portal, and API documentation),
first generate and review the scoped deletion plan:

```sh
bash gateway.sh cleanup-plan
```

Only after approving those removals, load the environment and execute:

```sh
set -a
source ./.env
set +a
export KONGCTL_DEFAULT_KONNECT_PAT="$KONNECT_PAT"
kongctl delete --profile default --region "$KONNECT_REGION" \
  --log-file .artifacts/kongctl.log --plan .plans/delete.json \
  --auto-approve -o json --execution-report-file .artifacts/delete-report.json
```

Keep the certificate pair for deliberate reuse. `.plans/`, `.artifacts/`
and private keys are excluded from Git. Local startup and teardown are
separate from remote Konnect provisioning.

## GitHub Actions CI/CD

`.github/workflows/deploy-ai-gateway.yaml` uses kongctl 1.20.1 and targets
the existing `summit-ai-demo` namespace in region `us`, organization
`bc68a981-db50-43b4-a6bc-6a3ab0557d3c`. It uses repository secrets
`KONNECT_PAT` and `OPENAI_API_KEY`, and the repository variable
`KONNECT_REGION=us`. The public certificate must be committed; the private
key remains on the local data plane host.

On a same-repository PR to `main` changing either manifest, portal content,
OpenAPI specifications, public certificate, plan, or workflow, the planning job:

1. Generates one apply-mode plan from `ai-gateway.yaml` and `portal.yaml` as
   `ci/plan.json` using only `KONNECT_PAT`.
2. Runs `kongctl diff --plan ci/plan.json` against those exact saved bytes.
3. Commits the plan on the PR branch and replaces the marked deployment
   section in the PR description, preserving surrounding prose. The section
   includes the diff, target, plan commit, and SHA-256.

Review the generated plan commit and PR description before merging. A plan
that differs only in its generation timestamp retains the already committed
bytes. Stale PR-head checks and a push without force prevent overwriting a
newer branch commit. Fork and Dependabot PRs do not receive planning secrets.
This workflow trusts repository writers and uses the existing shared PAT.

A push to `main` changing `ci/plan.json` applies that committed file with
`--auto-approve`; the deploy job never regenerates it. Configuration-only
pushes do not deploy. Direct plan pushes to `main` also deploy, so use the
repository's PR review process. Deployment validates the plan mode, CLI
version, namespace, action types, secret sources, organization, and region.
GitHub-hosted runners provision Konnect resources; the existing Docker data
plane stays on this laptop and receives the updated configuration.

Manual dispatch runs only the read-only drift job. After the workflow is
available on the default branch:

```sh
gh workflow run deploy-ai-gateway.yaml --ref main -f expect_no_changes=true
```

Set `expect_no_changes=false` to inspect proposed changes without failing
on drift. The job saves a fresh plan and renders its exact diff as artifacts;
it never applies or commits. Apply-mode drift checks cover declared resources
and do not detect extra undeclared remote resources.

Planning, drift, and deployment evidence is retained in Actions artifacts
for seven days. Failed drift assertions also retain the plan and diff.
`GITHUB_TOKEN` write-back may produce follow-up PR runs requiring approval
under GitHub's token-trigger rules; inspect the run state and existing merge
requirements. No additional token or repository policy change is configured.

## Public developer portal

`portal.yaml` declares the public `summit-ai-developer-portal`, its published
pages, and the `Summit AI Gateway Chat API`. The landing page content is in
`portal/pages/index.md` and its root slug `/` serves it at the portal domain
root. The API catalog is at `/apis`, with terminal examples at
`/getting-started`. Navigation and public visibility are configured explicitly.

The API publishes OpenAPI 3.0.3 specification versions:

- `specs/chat-completions-v1.0.0.json`: original `demo-chat` contract.
- `specs/chat-completions-v1.1.0.json`: current `demo-chat` and
  `demo-chat-nano` contract.

Both versions describe `POST /v1/chat/completions`, text messages, generation
parameters, assistant replies, streaming events, and errors. They are
documentation versions of the same endpoint. API name, description, and
version metadata come from the OpenAPI files using `!file` extraction.

The public documentation does not expose the loopback data plane. Execute
requests from the local terminal or Insomnia; browser Try It is disabled
because the gateway has no configured public endpoint or browser CORS policy.
After merging the reviewed plan, discover the portal's assigned domain with:

```sh
set -a
source ./.env
set +a
export KONGCTL_DEFAULT_KONNECT_PAT="$KONNECT_PAT"
kongctl get portal summit-ai-developer-portal --profile default \
  --region "$KONNECT_REGION" --log-file .artifacts/kongctl.log -o json
```

Use `bash gateway.sh drift` to plan both manifests locally without applying.
The pre-existing `Summit AI Chat Completions` catalog entry belongs to the
different `summit-ai` namespace; this configuration uses a distinct API name
and slug under `summit-ai-demo`.

## Verified deployment

On October 1, 2026, the approved plan created all four resources with no
failures in organization `bc68a981-db50-43b4-a6bc-6a3ab0557d3c`, region `us`.
The Docker data plane reported fully compatible and in sync. One request
through `/v1/chat/completions`, using `demo-chat`, returned a nonempty OpenAI
assistant completion. An unchanged follow-up plan reported no changes.
Local evidence is in `.artifacts/apply-report.json`, `.artifacts/nodes.json`,
`.artifacts/inference.json`, and `.plans/follow-up.json`.
