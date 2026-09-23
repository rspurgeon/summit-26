# Summit native AI Gateway demo

This project defines one native Konnect AI Gateway in the `summit-ai-demo`
namespace. Its local Docker data plane exposes `http://127.0.0.1:8000`.
The expanded manifest adds three OpenAI model aliases and two API key caller
identities. The proxy stays bound to loopback.

| Alias | Upstream model | Allowed callers |
| --- | --- | --- |
| `demo-chat` | `gpt-4.1-mini` | `full-access`, `limited-access` |
| `budget-chat` | `gpt-4o-mini` | `full-access` |
| `advanced-chat` | `gpt-4.1` | `full-access` |

The expansion is pending deployment; see [ACCESS_EXPANSION_PLAN.md](ACCESS_EXPANSION_PLAN.md).
The GitHub Actions process and required repository settings are in
[CI_CD.md](CI_CD.md).

## Inputs

- `kongctl` 1.16.0, Docker, OpenSSL, and a Konnect PAT for the intended US organization.
- An OpenAI key with access to all three upstream models and two distinct
  caller keys. The local `.env` is ignored by Git.
- Konnect target: `--profile default --region us`. Keep these flags for planning,
  diffing, applying, and discovery. Check that this is the intended organization.

## Plan and deployment history

The approved plan and deployment result are in
[DEPLOYMENT_PLAN.md](DEPLOYMENT_PLAN.md). The original `.plans/apply.json` has
already been executed; keep it as an audit artifact. Do not replay it. Generate
and review a new plan for any future change.

```sh
mkdir -p .artifacts
kongctl diff --plan .plans/apply.json --profile default --region us \
  --log-file .artifacts/kongctl.log
```

The saved plan is additive (`--mode apply`) and guarded to the
`summit-ai-demo` namespace. It is ignored by Git because it can contain
deployment inputs. To prepare a future change, run:

```sh
bash data-plane.sh certs
mkdir -p .plans
mkdir -p .artifacts
kongctl plan --mode apply -f ai-gateway.yaml \
  --require-namespace summit-ai-demo --profile default --region us \
  --output-file .plans/next-apply.json --log-file .artifacts/kongctl.log
kongctl diff --plan .plans/next-apply.json --profile default --region us \
  --log-file .artifacts/kongctl.log
```

After reviewing and approving any proposed changes, load the key from the
local `.env` and apply that new plan:

```sh
set -a; source ./.env; set +a
kongctl apply --plan .plans/next-apply.json --profile default --region us \
  --log-file .artifacts/kongctl.log \
  --execution-report-file .artifacts/next-apply-report.json
```

## Connect the local data plane

After apply, discover the two actual Konnect endpoints and start Docker:

```sh
AIGW_CONTROL_PLANE="$(kongctl get ai-gateway 'Summit AI Demo' \
  --profile default --region us --log-file .artifacts/kongctl.log -o json \
  --jq '.endpoints.configuration | sub("^https://"; "") | sub(":443$"; "")' \
  --jq-raw-output)"
AIGW_TELEMETRY="$(kongctl get ai-gateway 'Summit AI Demo' \
  --profile default --region us --log-file .artifacts/kongctl.log -o json \
  --jq '.endpoints.telemetry | sub("^https://"; "") | sub(":443$"; "")' \
  --jq-raw-output)"
export AIGW_CONTROL_PLANE AIGW_TELEMETRY
bash data-plane.sh run
kongctl get ai-gateway nodes --gateway-name 'Summit AI Demo' \
  --profile default --region us --log-file .artifacts/kongctl.log
```

The helper rejects missing or invalid endpoint hostnames and checks that the
mounted certificate and private key match. Use `bash data-plane.sh check` to
check the pair independently. It was generated for this project and is reused
on later runs.

## Route requests and verify access

After the approved expansion deploys and the node receives config, run the
full access matrix from this host. It asserts status and response semantics
for allowed, denied, missing key, and invalid key cases. It sends four paid
inference requests when all cases pass.

```sh
python3 scripts/verify-access.py self-test
set -a; source ./.env; set +a
python3 scripts/verify-access.py live
```

For one manual request, select any allowed alias. A real completion requires
a successful response with nonempty `choices[0].message.content`.

```sh
curl --fail-with-body --silent --show-error --max-time 60 \
  http://127.0.0.1:8000/v1/chat/completions \
  -H 'Content-Type: application/json' \
  -H "apikey: ${FULL_ACCESS_API_KEY}" \
  -d '{"model":"demo-chat","messages":[{"role":"user","content":"Reply with a short greeting."}]}'
```

Stop only the local container with `bash data-plane.sh stop`. Konnect resource
removal requires a separately reviewed `kongctl plan --mode delete` scoped to
the same namespace and target.
