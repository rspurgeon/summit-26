# Deployment plan for review

**Status:** Approved and deployed on 2026-09-22. The saved plan was applied,
the local Docker data plane is healthy, and one inference request succeeded.
This records the original one-model deployment. The proposed access expansion
is recorded separately in [ACCESS_EXPANSION_PLAN.md](ACCESS_EXPANSION_PLAN.md).

## Target and inputs

| Item | Planned value |
| --- | --- |
| Konnect CLI target | `--profile default --region us` |
| Namespace guard | `summit-ai-demo` |
| Operation | `kongctl apply` of saved `--mode apply` plan |
| Gateway | Native hybrid AI Gateway `summit-ai-demo` (`Summit AI Demo`) |
| Data plane | Local Docker, `kong/kong-ai-gateway:2.0.3`, loopback port 8000 |
| Provider and upstream model | OpenAI `gpt-4.1-mini` |
| Request alias and path | `demo-chat` at `/v1/chat/completions` |
| Client auth | None in this local demo; the proxy binds to `127.0.0.1` |

The local private key is `certs/data-plane.key` and is ignored by Git. Its
public certificate is `certs/data-plane.crt`. The provider key stays in the
local `.env` and is resolved only when the saved plan is executed.

## Saved kongctl plan

The actual plan is [`.plans/apply.json`](.plans/apply.json) (ignored by Git).
It was generated with kongctl 1.16.0 against the reachable US default Konnect
profile. The plan proposes **4 creates, 0 updates, 0 deletes, and 1 deferred
secret write**:

1. Create native hybrid AI Gateway `summit-ai-demo`.
2. Add its data plane mTLS certificate.
3. Add the OpenAI model provider with a deferred Authorization header.
4. Add model `demo-chat`, routed by the request body to `gpt-4.1-mini`.

Plan SHA-256: `c46e4079fcb027a8c43c6f464bbcee569524d633b6a68ba213421daf93a1ffde`

Review the full action diff with:

```sh
kongctl diff --plan .plans/apply.json --profile default --region us \
  --log-file .artifacts/kongctl.log
```

If the selected organization, model, or any input needs to change, regenerate
the plan and review the new diff before executing it.

OpenAI [lists `gpt-4.1-mini` for Chat Completions](https://developers.openai.com/api/docs/models/gpt-4.1-mini),
but that listing does not establish access for this local key.

## Deployment result

- Applied the saved plan with all four creates succeeding. Execution details
  are in the ignored `.artifacts/apply-report.json`.
- Konnect registered the local data plane as fully compatible and delivered a
  nonzero config version. The Docker container is healthy.
- One `POST /v1/chat/completions` request with model alias `demo-chat` returned
  HTTP 200 and a nonempty assistant greeting. The response identified upstream
  model `gpt-4.1-mini-2025-04-14`.
- A separate read-only follow-up plan at `.plans/post-apply.json` reported
  no changes.

## Future runs

Use [README.md](README.md) for connection, request, and cleanup commands. Keep
the original saved plan as an audit artifact; generate a new plan for any
future change.

If the plan becomes stale or execution changes its proposed scope, stop and
save a new plan for review.
