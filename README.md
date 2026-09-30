# Local OpenAI AI Gateway

This project manages a native Kong AI Gateway declaratively with kongctl.
The control plane runs in Konnect; the data plane runs in local Docker.
Configuration lives in `ai-gateway.yaml`, in namespace `summit-ai-demo`.
The gateway is named `summit-ai-demo`, with display name `Summit AI Demo`.
The public model alias `demo-chat` routes to OpenAI `gpt-4.1-mini`.
The additional alias `demo-nano` routes to OpenAI `gpt-4.1-nano` through
the same `/v1/chat/completions` endpoint and existing provider credential.

Requires kongctl with native `ai_gateways` support (checked with 1.20.1),
Docker, OpenSSL, curl, and jq. The helper uses `kong/kong-ai-gateway:2.0.3`,
pinned to the tested digest
`sha256:367ed5985b7648e4fdd6e1d7857562d24a5fb5a1db4985876b16d5b35eec84cb`.
The HTTP and HTTPS proxy ports bind only to `127.0.0.1`, with no caller
authentication configured for this local demo.

## Inputs

`gateway.sh` loads the trusted, shell-compatible local `.env` automatically.
Supply `OPENAI_API_KEY`, `KONNECT_PAT`, and `KONNECT_REGION`; the wrapper maps
the PAT to `KONGCTL_DEFAULT_KONNECT_PAT` and explicitly uses profile `default`
and your region on every remote command. Existing repository secrets with
those names can supply the same environment variables to future CI jobs.
The GitHub Actions workflow below uses these existing repository inputs.

Local defaults are container `summit-ai-demo-data-plane`, HTTP port `8000`,
and HTTPS port `8443`; `.env.example` documents overrides. If you change
the HTTP host port, also update `proxy_urls[].port` in `ai-gateway.yaml`
before generating a new plan. The upstream model ID is committed in YAML.
OpenAI credentials use deferred `!secret` references and are supplied at apply.

## Review and deploy

```sh
bash gateway.sh status
bash gateway.sh preflight
bash gateway.sh certs
bash gateway.sh check
bash gateway.sh plan
```

Review the organization ID, region, and saved diff. The plan uses additive
`apply` mode and a namespace guard. `.plans/apply.json` contains the saved
plan; `.plans/apply-target.json` records its hash and target identity.
After approving that concrete plan, execute it and start the local node:

```sh
bash gateway.sh apply
bash gateway.sh run
bash gateway.sh nodes
```

The apply command executes the saved plan, checks its hash and target,
and saves `.artifacts/apply-report.json`. The run command discovers both
Konnect endpoints and mounts the certificate and private key read-only.
The helper reuses a matching certificate pair and refuses to overwrite an
existing container. `run` uses `--rm`, so stopping removes that container.

Allow time for the node to connect and receive configuration. Check nodes
and `docker logs summit-ai-demo-data-plane` if connection fails. Then send
one real, billable OpenAI request through the local gateway:

```sh
bash gateway.sh smoke
```

This calls `http://127.0.0.1:8000/v1/chat/completions` with `demo-chat`,
saves a local response, and requires a nonempty assistant completion.
After the model PR merges and its saved plan is applied, test `demo-nano`:

```sh
curl --fail-with-body --silent --show-error --max-time 60 \
  http://127.0.0.1:8000/v1/chat/completions \
  -H 'Content-Type: application/json' \
  -d '{"model":"demo-nano","messages":[{"role":"user","content":"Reply with a short greeting."}],"max_tokens":32}' \
  | jq -e '.choices[0].message.content | select(type == "string" and length > 0)'
```

After successful deployment, rerun `bash gateway.sh plan` to check drift.
Do not routinely use `--write-secrets`; credential rotation is a deliberate
change requiring its own reviewed plan.

## Stop and remove

```sh
bash gateway.sh stop
```

Stopping the local container leaves Konnect configuration intact. To remove
this project's remote gateway and its children, generate and review a
separate delete plan before running cleanup:

```sh
bash gateway.sh cleanup-plan
# After reviewing and approving the saved deletion plan:
bash gateway.sh cleanup
```

Keep the certificate pair for reuse unless deliberately resetting it.
Private keys, `.env`, plans, execution reports, and inference results are
ignored by Git. The public certificate is committed alongside the manifest.

## GitHub Actions CI/CD

`.github/workflows/deploy-ai-gateway.yaml` pins kongctl 1.20.1 and targets
organization `bc68a981-db50-43b4-a6bc-6a3ab0557d3c`, region `us`, namespace
`summit-ai-demo`. It reuses repository secrets `KONNECT_PAT` and
`OPENAI_API_KEY`, and the existing repository variable `KONNECT_REGION`.
Changing the target requires updating the workflow; a mismatching region or
organization fails before planning or applying. Repository controls are
preserved, with no new token or environment approval requirement.

On same-repository PRs changing the manifest, public certificates, committed
plan, or workflow, the planning job generates an additive `apply` plan and
runs `kongctl diff --plan ci/plan.json` against those exact saved bytes. It
commits `ci/plan.json` to the PR branch and replaces only the description
section between `<!-- ai-gateway-plan:start -->` and
`<!-- ai-gateway-plan:end -->`. The section records the target, plan commit,
SHA-256, and diff. Other description text is preserved. If regeneration
changes only the timestamp, the existing committed bytes are retained.
The job checks the PR head and pushes without force to avoid overwriting
newer changes. Fork PRs and bot-triggered planning jobs are excluded.

Review the plan commit and marked diff before merging. When a push to
`main` changes `ci/plan.json`, the deploy job applies that committed plan
without regenerating it. Config-only main pushes do not deploy. Direct
main pushes changing the plan also qualify under existing repository
controls. The deployment checks apply mode, CLI version, namespace,
additive actions, allowed secret sources, and actual organization. It saves
the diff, plan hash, source commit, actor, and execution report as artifacts.
Planning jobs alone have contents and PR write permissions; deployment and
manual drift checks have repository read permissions. The shared Konnect
token is available to trusted repository writers' planning workflows.

GitHub may require a repository writer to approve a workflow run created by
the bot's PR branch update. This is GitHub's existing token event behavior;
the workflow does not introduce an additional deployment approval gate.

The manual dispatch runs only a read-only drift check. It defaults to
asserting zero resource changes and zero secret writes, and retains the
saved plan and diff even if that assertion fails:

```sh
gh workflow run deploy-ai-gateway.yaml --ref main -f expect_no_changes=true
# Inspect proposed changes without asserting convergence:
gh workflow run deploy-ai-gateway.yaml --ref main -f expect_no_changes=false
```

Manual drift checks neither write `ci/plan.json` nor apply configuration.
Additive drift checks compare declared resources; they do not flag extra
remote resources absent from the manifest. The workflow leaves local Docker
and its private key on your laptop; use `bash gateway.sh smoke` there after
runtime changes.

References: [Kong AI Gateway documentation](https://developer.konghq.com/ai-gateway/)
and [kongctl OpenAI example](https://github.com/Kong/kongctl/tree/main/docs/examples/declarative/ai-gateway/openai-llm).
