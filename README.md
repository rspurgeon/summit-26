# Summit AI Gateway

Native Konnect AI Gateway with a local Docker data plane and declarative
configuration in `ai-gateway.yaml`. Based on the
[Kong OpenAI quickstart](https://github.com/Kong/kongctl/tree/main/docs/examples/declarative/ai-gateway/openai-llm).

The gateway is named `summit-ai` (display name `Summit AI`) and managed in
namespace `summit-ai`. Client alias `demo-chat` routes to OpenAI model
`gpt-4.1-mini`. Alias `nano-chat` routes to the lower-cost `gpt-4.1-nano`.
The proxy binds to `127.0.0.1:8000` and `127.0.0.1:8443`.
The data plane image is `kong/kong-ai-gateway:2.0.3`.

Requires kongctl with native `ai_gateways` support (checked with 1.20.1),
Docker, OpenSSL, curl and jq. The wrappers load the trusted shell-compatible
`.env` if present; otherwise they use environment variables, including GitHub
secrets supplied by a workflow. `kongctl.sh` maps `KONNECT_PAT` to
`KONGCTL_DEFAULT_KONNECT_PAT`, selects profile `default`, and explicitly passes
`KONNECT_REGION`. This setup was planned for region `us`, organization
`bc68a981-db50-43b4-a6bc-6a3ab0557d3c`.

`OPENAI_API_KEY` is a deferred `!secret`: it is resolved during apply and
is never embedded in the manifest or saved plan. The private mTLS key,
local credentials, plans and execution evidence are ignored by Git.
The public certificate is part of the deployment configuration.

## Prepare and review

Keep existing credentials in `.env`. `.env.example` documents the inputs.
Host port changes also require updating `proxy_urls` in `ai-gateway.yaml`
before planning. Generate the certificate once; subsequent runs reuse it.

```bash
bash local.sh status
bash local.sh preflight
bash local.sh certs
bash local.sh check
bash kongctl.sh get organization -o json --jq '.id' --jq-raw-output
bash kongctl.sh plan --mode apply -f ai-gateway.yaml \
  --require-namespace summit-ai --output-file .plans/apply.json
bash kongctl.sh diff --plan .plans/apply.json
```

Review the saved plan and target before execution. Apply creates the gateway,
registers the public certificate, configures the OpenAI provider credential
and adds the model. Apply mode does not delete resources missing from this file.

## Apply the reviewed plan and start locally

```bash
bash kongctl.sh apply --plan .plans/apply.json --auto-approve -o json \
  --execution-report-file .artifacts/apply-report.json
bash local.sh run
bash kongctl.sh get ai-gateway nodes --gateway-name 'Summit AI' -o json
```

`local.sh run` discovers both Konnect channel endpoints from the gateway,
mounts the certificate and key read-only, and starts Docker. If this project's
container already exists, inspect it with `status`; the helper refuses to
replace it. Allow configuration to propagate and check node status before
inference. For diagnostics use `docker logs summit-ai-demo-data-plane`; keep logs local.

## Verify and update

Send your own prompt through the local gateway and print the model's reply:

```bash
bash chat.sh "Explain what an AI gateway does in two sentences."
```

After the model PR is merged and deployed, select the lower-cost model:

```bash
AIGW_MODEL=nano-chat bash chat.sh "Explain what an AI gateway does in two sentences."
```

`chat.sh` uses alias `demo-chat` by default and respects `AIGW_PROXY_PORT` in `.env`.
It handles JSON escaping for prompts and displays errors from failed requests.
The gateway supplies the OpenAI credential; each request uses provider tokens.

Run one small OpenAI request through the gateway; this uses provider tokens:

```bash
bash local.sh smoke
```

This checks a real nonempty assistant completion and keeps the response in
`.artifacts/inference.json`. Client requests use `demo-chat` at
`http://127.0.0.1:8000/v1/chat/completions`; the gateway supplies the provider key.

Edit `ai-gateway.yaml` to change models or configuration, then generate and
review a fresh apply plan. Keep refs, names and namespace stable. Do not use
`--write-secrets` for routine updates; use it deliberately for secret rotation.
After deployment, check an unchanged plan for drift:

```bash
bash kongctl.sh plan --mode apply -f ai-gateway.yaml \
  --require-namespace summit-ai --output-file .plans/follow-up.json
bash kongctl.sh diff --plan .plans/follow-up.json
```

## Stop and clean up

`bash local.sh stop` stops and removes only this local container. Konnect
resources and the certificate pair remain for reuse.

To remove this deployment from Konnect, prepare and review a scoped deletion:

```bash
bash kongctl.sh plan --mode delete -f ai-gateway.yaml \
  --require-namespace summit-ai --output-file .plans/delete.json
bash kongctl.sh diff --plan .plans/delete.json
# Only after approving the listed gateway and child deletions:
bash kongctl.sh delete --plan .plans/delete.json --auto-approve -o json
```



## Verified deployment

On 2026-10-01, the approved plan applied all four resources successfully.
The Docker node connected, reported fully compatible and in sync, and one
request to `/v1/chat/completions` with alias `demo-chat` returned
“Hello! How can I assist you today?” An unchanged follow-up plan reported
no changes. Local evidence is in `.artifacts/apply-report.json`,
`.artifacts/nodes.json`, `.artifacts/inference.json`, and `.plans/follow-up.json`.

The running container uses the existing `.env` name
`summit-ai-demo-data-plane`. Its observed image digest is
`kong/kong-ai-gateway@sha256:367ed5985b7648e4fdd6e1d7857562d24a5fb5a1db4985876b16d5b35eec84cb`.
Set `KONG_AI_GATEWAY_IMAGE` to that digest to reuse the exact image.

## GitHub Actions

`.github/workflows/deploy-ai-gateway.yaml` uses kongctl **1.20.1** and the
existing `summit-ai` namespace and organization. It reuses repository secrets
`KONNECT_PAT` and `OPENAI_API_KEY` and repository variable `KONNECT_REGION`
(currently `us`; a secret of the same name is also supported).

For same-repository PRs targeting `main`, changes to `ai-gateway.yaml`, `dev-portal.yaml`, `specs/**`, `portal/**`, public
certificates, `ci/plan.json`, or this workflow generate an additive apply plan.
The job commits `ci/plan.json` to the PR branch and renders that exact saved
file with `kongctl diff --plan`. The PR description receives a section between
`<!-- ai-gateway-plan:start -->` and `<!-- ai-gateway-plan:end -->`; surrounding
text is preserved. It includes the diff, target, plan commit, and SHA-256.
Plans that differ only in generation time retain their existing committed bytes.
Newer PR commits cause stale planning runs to fail rather than overwrite them.

Review the plan through the existing PR process. A push to `main` that updates
`ci/plan.json` applies the committed file **without regeneration**. Config-only
main pushes do not deploy; direct plan pushes also qualify under the existing
branch controls. Deployment verifies the organization, CLI version, apply mode,
namespace, additive actions, and deferred secret sources, and saves its execution
report as a workflow artifact. Only deployment receives `OPENAI_API_KEY`.
The workflow does not start Docker: the existing local data plane receives updates.

Once the workflow is on `main`, run the independent read-only drift check:

```bash
gh workflow run deploy-ai-gateway.yaml --ref main -f expect_no_changes=true
```

The default is `true`: any resource change or secret write fails the check.
Set `expect_no_changes=false` to inspect a diff without asserting convergence.
This manual job never commits `ci/plan.json` or applies resources. It retains
plan and diff artifacts even when the assertion fails. Apply-mode drift checks
compare declared resources; they do not detect every extra remote resource.

Planning alone has `contents: write` and `pull-requests: write`; deployment and
drift checks have repository read permissions. Fork and bot PR runs do not plan.
Repository writers are trusted with the existing Konnect credential, including
when changing workflow code. Existing branch and Actions controls are preserved.
A bot plan push can create approval-required PR workflow runs; a repository writer
may need to use **Approve workflows to run** in GitHub. See
[GitHub token-trigger behavior](https://docs.github.com/en/actions/how-tos/write-workflows/choose-when-workflows-run/trigger-a-workflow).

## Public developer portal

`dev-portal.yaml` manages `summit-developer-portal` (display name **Summit AI
Developer Portal**) in the existing `summit-ai` namespace. Portal authentication
and RBAC are disabled; API and page defaults are public. It publishes the
**Summit AI Chat Completions** API with public visibility and a published
getting-started document.

The API specification versions are stored outside the resource manifests:

| Specification | Model aliases | Meaning |
| --- | --- | --- |
| `specs/chat-completions-1.0.0.json` | `demo-chat` | Original mini-only contract |
| `specs/chat-completions-1.1.0.json` | `demo-chat`, `nano-chat` | Current contract; nano added |

Both document `POST /v1/chat/completions`, text messages, model selection,
non-streaming replies, streaming chunks, token limits and error responses.
The API's current version is **1.1.0**. Metadata and specification versions are
loaded from OpenAPI files using `!file`; the publication links to the portal
using `!ref`. These are documentation versions of the same gateway endpoint.
The guide in `portal/getting-started.md` supplies curl and repository examples.

The public portal hosts documentation. The data plane remains bound to
`127.0.0.1`; the documented server requires running the request on its host.
Browser Try It is disabled for this local endpoint. No Gateway Service link or
portal-issued application credential is needed for this documentation-only
publication; clients use the existing local gateway as documented.

PR planning and manual drift checks include **both manifests** in the existing
saved-plan pipeline. Specs and guide changes trigger PR planning too. Preview
all declared resources locally with:

```bash
bash kongctl.sh plan --mode apply -f ai-gateway.yaml -f dev-portal.yaml \
  --base-dir "$PWD" --require-namespace summit-ai \
  --output-file .plans/portal.json
bash kongctl.sh diff --plan .plans/portal.json
```

Review the generated `ci/plan.json` and PR diff before merging. Main applies
that saved plan using the existing credentials and repository controls. Until
merge and a successful deployment, the new portal and API remain staged.
After deployment, discover the actual portal URL rather than constructing it:

```bash
bash kongctl.sh get portal 'Summit AI Developer Portal' -o json
```

Stopping the local Docker gateway does not remove the portal or catalog API.
For intended removal of the portal and its documented API, plan a scoped delete
using **only** `-f dev-portal.yaml`, inspect its diff, and approve those removals.
