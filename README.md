# Local Kong AI Gateway

This repository runs Kong AI Gateway in Docker on localhost and manages its Konnect control plane, OpenAI provider, and model declaratively with kongctl. The gateway exposes `http://localhost:8000/v1/chat/completions`; the client model name `demo-chat` routes to OpenAI `gpt-4o-mini`.

The data plane runs locally. Configuration and provider credentials are managed in your Konnect account, and inference requests go to OpenAI. This follows Kong's [AI Gateway configuration workflow](https://developer.konghq.com/ai-gateway/kongctl/).

## Start locally

Prerequisites: Docker with Compose, kongctl 1.20.1, jq, and OpenSSL. Keep `OPENAI_API_KEY`, `KONNECT_PAT`, and `KONNECT_REGION` in the ignored `.env` file, or export them in your shell. `.env` uses shell assignment syntax and is sourced by the helper.

```bash
scripts/gateway plan
scripts/gateway apply
scripts/gateway up
scripts/gateway test
scripts/gateway status
```

`plan` saves an apply-mode plan in `.local/plan.json`. `apply` executes that saved plan and reads the OpenAI secret from the current environment. `up` creates a local TLS identity if needed, registers its public certificate declaratively, and starts Docker. `test` makes one small, billable OpenAI request.

Proxy ports bind to `127.0.0.1`. The demo endpoint has no client authentication; OpenAI authentication is injected by the gateway. The admin API is disabled. The client does not need your OpenAI key:

```bash
curl --fail-with-body http://localhost:8000/v1/chat/completions \
  -H 'Content-Type: application/json' \
  --data '{"model":"demo-chat","messages":[{"role":"user","content":"Hello!"}]}'
```

## Change configuration

Edit `ai-gateway.yaml`, then run `scripts/gateway plan` and `scripts/gateway apply`. The dedicated `summit-ai-demo` namespace scopes ownership. Apply creates and updates resources; it does not delete them. Replan after editing the manifest because apply uses the saved plan.

To rotate the provider key after updating `.env`:

```bash
scripts/gateway kongctl plan --mode apply -f ai-gateway.yaml \
  --write-secret openai --output-file .local/plan.json
scripts/gateway apply
```

The `!secret` reference keeps the resolved OpenAI key out of saved plans. `.env`, local plans, certificates, runtime settings, and CLI logs are ignored by Git. CI deliberately commits its reviewed plan as `ci/plan.json`. Retain `.local/tls.crt` and `.local/tls.key` together so restarts reuse the registered identity. The certificate lasts one year. Model request and response payload logging is disabled.

Optional Docker settings are listed in `.env.example`. If you change the HTTP proxy port, update `proxy_urls` in `ai-gateway.yaml`, then replan and apply. Inspect Docker logs with `docker compose logs --tail=100 gateway`.

## Configure from GitHub Actions

The **AI Gateway CI/CD** workflow uses the existing `KONNECT_PAT` and `OPENAI_API_KEY` secrets and `KONNECT_REGION` variable (a same-named secret also works). It keeps the existing gateway and `summit-ai-demo` namespace. kongctl is pinned to 1.20.1 and its download is checksum-verified.

For configuration PRs targeting `main`, the workflow generates an additive plan with `kongctl plan --mode apply`, renders `kongctl diff --plan ci/plan.json`, and commits that exact plan to the PR branch. It replaces only the section between `<!-- kongctl-plan:start -->` and `<!-- kongctl-plan:end -->` in the PR description, preserving your other text. Review the diff and wait for the planning job to finish before merging. Later configuration commits generate a replacement plan. Concurrent branch updates cause a normal push to fail rather than overwriting your work; rerun against the latest head.

When merging updates `ci/plan.json` on `main`, deployment validates the additive mode and namespace, then runs `kongctl apply --plan ci/plan.json --auto-approve`. It never regenerates the plan. OpenAI credentials resolve from the deployment environment when a deferred secret write is requested. Plans capture state at PR planning time; if deployment fails because that state changed, replan in a new PR rather than silently replacing the reviewed plan.

Run the workflow manually for a read-only drift check. **Fail if configuration drift is detected** defaults to enabled. Disable it to report drift without failing the run. Drift generates a temporary sync-mode plan to detect changes in declared resource collections, displays its diff, and never applies or commits it. Local certificate management remains separate in `local-dataplane.yaml`.

PR automation runs only for branches in this repository, using job-scoped `contents: write` and `pull-requests: write`. Deployment and drift use read-only GitHub permissions. The existing repository-wide permissions and branch rules are unchanged; no extra GitHub PAT or automatic PR approval is required. Bot events are excluded from planning so a bot-generated follow-up run cannot create a loop. GitHub may mark that follow-up run as requiring approval; it does not need approval because the preceding planning run already saved and posted the plan. Deployment and drift share a concurrency group.

The workflow configures Konnect; it does not start Docker on your laptop. Commit and push the workflow and helpers to make the automation available on GitHub. The first configuration PR will create `ci/plan.json`; no initial deployment plan is seeded on main.

## Stop locally

```bash
scripts/gateway down
```

This removes the local Compose container and network and retains Konnect configuration and the local TLS identity for the next start.
