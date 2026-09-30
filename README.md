# Summit AI Gateway

Native Kong AI Gateway with a local Docker data plane and declarative Konnect
configuration managed by kongctl. Konnect hosts the control plane in the region
specified by `KONNECT_REGION`; inference enters through your local data plane.

`ai-gateway.yaml` owns namespace `summit-ai`, gateway `Summit AI`, an OpenAI
provider, a public data plane certificate, and model alias `demo-chat` targeting
`gpt-4.1-mini`. The proxy binds to loopback on ports 8000 and 8443. The demo has
no caller authentication. The OpenAI key is a deferred `!secret`, supplied at
apply time, and is never sent by callers.

## Prerequisites

Use kongctl 1.20.1 or compatible native AI Gateway support, Docker, OpenSSL,
curl, and jq. The data plane image is `kong/kong-ai-gateway:2.0.3`.
Your trusted, shell-compatible `.env` supplies `OPENAI_API_KEY`, `KONNECT_PAT`,
and `KONNECT_REGION`. The scripts load it automatically and map `KONNECT_PAT`
to `KONGCTL_DEFAULT_KONNECT_PAT`; they use the default profile and an explicit
region. `.env.example` describes optional local settings. Real secrets,
private keys, plans, and diagnostic artifacts are ignored by Git.

## Plan and apply

```bash
bash gateway.sh status
bash gateway.sh preflight
bash gateway.sh certs
bash gateway.sh check
mkdir -p .plans .artifacts
bash kongctl.sh get organization -o json --jq '.id' --jq-raw-output
bash kongctl.sh plan --mode apply -f ai-gateway.yaml \
  --require-namespace summit-ai --output-file .plans/apply.json
bash kongctl.sh diff --plan .plans/apply.json
```

Review the saved plan and its organization, region, namespace, and secret writes.
After approving that exact plan and target, execute it with the same credentials
and region used to plan:

```bash
bash kongctl.sh apply --plan .plans/apply.json -o json --auto-approve \
  --execution-report-file .artifacts/apply-report.json
```

Keep the certificate pair; reuse it on subsequent plans. Only the public
certificate is committed. Changes to the manifest, certificate, or target
require a new plan and review. Do not use `--write-secrets` for routine updates;
provider credential rotation is an explicit operation. Existing GitHub secrets
can supply the same three environment variables when CI is added.

## Start and verify

```bash
bash gateway.sh run
bash kongctl.sh get ai-gateway nodes --gateway-name 'Summit AI'
```

The start script discovers both Konnect channel hostnames from the created
gateway and mounts the certificate and key read-only. Wait for the node to
connect and receive configuration before sending one smoke request:

```bash
bash gateway.sh smoke
```

This makes a small paid OpenAI request and requires a nonempty assistant
completion. It saves sanitized evidence in `.artifacts/inference-check.json`.
Clients use `http://127.0.0.1:8000/v1/chat/completions`, model `demo-chat`,
and the standard OpenAI chat JSON body. No provider key is needed in a client
header. If readiness fails, inspect `docker logs summit-ai-data-plane` and
the Konnect node status before retrying inference.

Change the upstream model in YAML to another accessible model while preserving
the alias, then plan and apply. If changing the host HTTP port, also change
`proxy_urls[].port` in YAML before planning. To check for drift, generate a
fresh apply plan with a different output filename and inspect its diff.

## Stop and clean up

```bash
bash gateway.sh stop
```

Stopping removes only this project's local container. To remove Konnect
resources deliberately, prepare and review a scoped delete plan:

```bash
bash kongctl.sh plan --mode delete -f ai-gateway.yaml \
  --require-namespace summit-ai --output-file .plans/delete.json
bash kongctl.sh diff --plan .plans/delete.json
# Only after approving those removals:
bash kongctl.sh delete --plan .plans/delete.json -o json --auto-approve \
  --execution-report-file .artifacts/delete-report.json
```

Gateway deletion includes its children. Preserve the local certificate pair
until a deliberate reset. Inspect local artifacts for secrets before sharing.

## GitHub Actions CI/CD

`.github/workflows/deploy-ai-gateway.yaml` uses kongctl 1.20.1, the existing
`KONNECT_PAT` and `OPENAI_API_KEY` repository secrets, and repository variable
`KONNECT_REGION`. It checks organization
`bc68a981-db50-43b4-a6bc-6a3ab0557d3c` and namespace `summit-ai`.

For same-repository PRs into `main` that change the manifest, public certificate,
plan, or workflow, CI generates an additive apply plan and commits it as
`ci/plan.json` on the PR branch. CI renders that exact saved file with
`kongctl diff --plan` and replaces the `ai-gateway-plan` marked section of the
PR description, preserving surrounding prose. The section includes the plan
commit, SHA-256, and target. Only planning has repository write permissions;
OpenAI credentials are supplied only to deployment.

Review the bot's plan commit and marked diff before merging. A push to `main`
that changes `ci/plan.json` automatically applies that committed file without
regenerating it. Configuration-only pushes do not deploy. Direct plan pushes
to `main` also qualify under the repository's existing controls. Deployment
checks apply mode, namespace, additive actions, generator version, allowed
secret sources, and organization, and retains its execution report. It does
not start or replace your local Docker data plane.

Run an independent read-only drift check after this workflow is on `main`:

```bash
gh workflow run deploy-ai-gateway.yaml --ref main -f expect_no_changes=true
```

The input defaults to true: resource changes or secret writes fail the check.
Use `expect_no_changes=false` to inspect proposals without asserting a no-op.
This job never applies or commits a plan, and uploads its saved plan and diff
even when the assertion fails. Additive drift checks test declared-resource
convergence; they do not detect undeclared extra remote resources.

The workflow reuses the existing repository permissions and review controls.
It trusts same-repository writers with the Konnect planning credential; fork
PRs and bot-triggered planning are excluded. GitHub may require approval of
PR runs caused by the bot's plan commit; inspect that run state before merging.
Plans contain operational configuration and IDs, with credentials deferred.
The public certificate must be tracked; its private key stays on your laptop.
