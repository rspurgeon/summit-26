# Summit local AI Gateway

Native Kong AI Gateway 2.0 with a local Docker data plane, a Konnect control
plane, and two OpenAI models. Configuration is managed by kongctl 1.20.1.

`ai-gateway.yaml` owns namespace `summit-ai-demo` and gateway `Summit AI Demo`.
Clients select a model through the request body's `model` field:

| Gateway alias | Upstream model |
| --- | --- |
| `demo-chat` | `gpt-4.1-mini` |
| `demo-chat-nano` | `gpt-4.1-nano` |

Edit the upstream model in YAML to change it while preserving its alias.
The proxy binds to `127.0.0.1:8000` (HTTP) and `127.0.0.1:8443` (HTTPS).
The data plane runs on your laptop; the control plane and provider credential
are managed in Konnect. Internet access is required.

## Inputs

Required tools: kongctl, Docker with a running daemon, OpenSSL, curl, and jq.
The scripts load your trusted, shell-compatible `.env` automatically, mapping
`KONNECT_PAT` to `KONGCTL_DEFAULT_KONNECT_PAT`. They use the default profile
and explicitly pass `KONNECT_REGION` on every remote command.
The existing local target is region `us`, organization
`bc68a981-db50-43b4-a6bc-6a3ab0557d3c`.

Keep `OPENAI_API_KEY`, `KONNECT_PAT`, and `KONNECT_REGION` in `.env` or the
execution environment. `.env.example` documents non-secret settings.
The OpenAI key uses deferred `!secret` resolution; it is supplied during
apply, rather than embedded in YAML or the saved plan.
The private data-plane key, plans, and local evidence are gitignored.
Only the public certificate belongs in configuration.

The image is pinned to:
`kong/kong-ai-gateway:2.0.3@sha256:367ed5985b7648e4fdd6e1d7857562d24a5fb5a1db4985876b16d5b35eec84cb`.

## Plan and review

Run these commands from the repository root:

```bash
bash data-plane.sh status
bash data-plane.sh preflight
bash data-plane.sh certs
bash scripts/kongctl.sh get organization -o json --jq '.id' --jq-raw-output
bash scripts/kongctl.sh plan --mode apply -f ai-gateway.yaml \
  --require-namespace summit-ai-demo --output-file .plans/apply.json
bash scripts/kongctl.sh diff --plan .plans/apply.json
```

Review the target organization, region, namespace, additions, updates,
deletions, and secret writes before executing. `apply` mode creates or
updates resources; use it for routine configuration changes.
Changing configuration or target requires a new plan and review.
If changing the HTTP host port, also change `proxy_urls[].port` in the YAML
before planning. Certificate generation reuses an existing matching pair.

## Apply the reviewed plan and start

After approving the saved plan:

```bash
bash scripts/kongctl.sh apply --plan .plans/apply.json -o json \
  --auto-approve --execution-report-file .artifacts/apply-report.json
bash scripts/start.sh
bash scripts/kongctl.sh get ai-gateway nodes --gateway-name 'Summit AI Demo' -o json
```

`start.sh` discovers both Konnect endpoints from the provisioned gateway.
It refuses to replace an existing container. For an existing deployment,
inspect its configuration and reuse the running container.
Allow the node to connect and receive configuration before testing:

```bash
bash scripts/smoke.sh
```

The smoke test makes one small, billable OpenAI request through
`http://127.0.0.1:8000/v1/chat/completions` with alias `demo-chat` and verifies
nonempty assistant content. Callers do not need the provider key.
The successful completion and usage are saved locally under `.artifacts/`.
For troubleshooting, inspect node status and
`docker logs summit-ai-demo-data-plane`.

Check for drift after deployment:

```bash
bash scripts/kongctl.sh plan --mode apply -f ai-gateway.yaml \
  --require-namespace summit-ai-demo --output-file .plans/follow-up.json
bash scripts/kongctl.sh diff --plan .plans/follow-up.json
```

## Send a chat request

```bash
bash scripts/chat.sh "Explain what an AI gateway does in one sentence."
printf '%s\n' "Write a short greeting." | bash scripts/chat.sh
bash scripts/chat.sh --system "Be concise." --json "What is Kong?"
```

The script routes one request through the local gateway with alias
`demo-chat` and prints the assistant's reply. Use `--json` for the full
response and token usage. It loads the local proxy port from `.env`, works
from any directory, and requires curl and jq. Each request uses the
configured OpenAI account, with output limited to 256 tokens.

After the model-addition PR is merged and its saved plan is deployed, use
the lower-cost Nano alias at the same endpoint:

```bash
curl --fail-with-body --silent --show-error --max-time 60 \
  http://127.0.0.1:8000/v1/chat/completions \
  -H 'Content-Type: application/json' \
  -d '{"model":"demo-chat-nano","messages":[{"role":"user","content":"Say hello."}],"max_tokens":32}'
```

## Stop and remove

Stop only this project's local container:

```bash
bash data-plane.sh stop
```

This leaves Konnect configuration and the certificate pair available for
reuse. To remove this project's remote configuration, prepare and review
a separate deletion plan:

```bash
bash scripts/kongctl.sh plan --mode delete -f ai-gateway.yaml \
  --require-namespace summit-ai-demo --output-file .plans/delete.json
bash scripts/kongctl.sh diff --plan .plans/delete.json
```

Only after approving those removals:

```bash
bash scripts/kongctl.sh delete --plan .plans/delete.json -o json \
  --auto-approve --execution-report-file .artifacts/delete-report.json
```

The gateway's deletion also removes its child resources. Preserve the
certificate pair unless intentionally resetting the deployment.
## GitHub Actions CI/CD

`.github/workflows/deploy-ai-gateway.yaml` uses kongctl 1.20.1, repository
secrets `KONNECT_PAT` and `OPENAI_API_KEY`, and repository variable
`KONNECT_REGION` (currently `us`). Every remote job verifies organization
`bc68a981-db50-43b4-a6bc-6a3ab0557d3c` and uses namespace `summit-ai-demo`.
The public certificate must be committed; the private key stays local.

For same-repository PRs targeting `main`, changes to `ai-gateway.yaml`,
the public certificates, `ci/plan.json`, or the workflow generate an
apply-mode plan. CI runs `kongctl diff --plan ci/plan.json`, commits that
exact plan on the PR branch, and replaces a marked section in the PR
description with its diff, commit, target, and SHA-256. Other description
text is preserved. If regeneration changes only the timestamp, CI retains
the committed bytes. Stale PR heads fail instead of overwriting newer work.
Fork PRs and bot-triggered planning runs are excluded.

A push to `main` changing `ci/plan.json` applies that committed file with
`--auto-approve`; deployment never regenerates it. Review the plan commit
and PR diff before merging. A configuration-only main push does not deploy.
Direct plan pushes to main also deploy, so use your repository's normal
review process. Deployment checks the plan mode, generator, namespace,
actions, and permitted deferred secret sources before execution.
Apply reports and planning evidence are retained as Actions artifacts.
The existing local data plane receives the updated configuration from
Konnect; GitHub runners do not start a separate local gateway.

After the workflow reaches the default branch, run a read-only drift check:

```bash
gh workflow run deploy-ai-gateway.yaml --ref main -f expect_no_changes=true
```

Manual dispatch runs only `check-drift`: it plans into `evidence/plan.json`,
diffs that exact file, and uploads evidence without committing or applying.
It fails when declared configuration would change or secrets would be
written. Use `expect_no_changes=false` to inspect proposed changes without
the no-op assertion. Apply-mode drift checks cover declared resources.

This workflow uses `GITHUB_TOKEN` for PR write-back. GitHub may create
approval-required runs after bot-generated PR updates; inspect those runs
and any required-check policy before merging. See
[GitHub's token-trigger behavior](https://docs.github.com/en/actions/concepts/security/github_token).
Same-repository writers have access to the configured CI credentials.

Reference: [Kong AI Gateway setup](https://developer.konghq.com/ai-gateway/get-started/).
