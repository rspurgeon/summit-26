# Access expansion plan for review

**Status:** Prepared; awaiting human approval and deployment. The currently
running gateway still has its original single model and no caller auth until
this expansion is applied.

The source is in [draft PR #1](https://github.com/rspurgeon/summit-26/pull/1).
The GitHub provider and caller secrets are configured; Konnect CI PATs are
pending explicit authorization. No expansion plan has been applied.

The manifest preserves gateway `summit-ai-demo`, namespace `summit-ai-demo`,
the public data plane certificate, and the `demo-chat` alias. It adds
`budget-chat` (`gpt-4o-mini`) and `advanced-chat` (`gpt-4.1`). The existing
OpenAI key returned HTTP 200 for read-only model lookups of both new IDs.

The saved local plan is [`.plans/access-expansion.json`](.plans/access-expansion.json),
generated against the US Konnect organization `AI Summit 2026`
(`bc68a981-db50-43b4-a6bc-6a3ab0557d3c`) with kongctl 1.16.0.

- 7 creates: key auth strategy, two consumers, two caller credentials, and
  two models.
- 1 update: attach key auth and an allow list to `demo-chat`.
- 2 deferred secret writes: the new caller credentials.
- 0 deletions; no gateway, provider, or certificate replacement.

Plan SHA-256: `398b23f70cd5b9c356ecfc27b02ab9d467c8a9d1dedde8e2c70802b3e1dbea2d`

```sh
kongctl diff --plan .plans/access-expansion.json --profile default --region us \
  --log-file .artifacts/kongctl.log
```

The GitHub Actions workflow will create its own saved plan from the committed
revision and publish its exact diff and hash. After human review, a separate
identity-checked `deploy` dispatch names that plan run and hash; it applies
the downloaded artifact after verifying its identity. The local saved plan
is a review preview, not a substitute for the CI artifact. The local Docker
data plane stays on this host. See [CI_CD.md](CI_CD.md).

After approval and application, run `python3 scripts/verify-access.py live`
on this host. The expected matrix is:

| Caller | `demo-chat` | `budget-chat` | `advanced-chat` |
| --- | --- | --- | --- |
| `full-access` | 200 + completion | 200 + completion | 200 + completion |
| `limited-access` | 200 + completion | 403 | 403 |
| Missing or invalid key | 401 | 401 | 401 |

Repeat deployment by dispatching the same workflow at an unchanged revision.
Its apply-mode plan should report no changes; keep the new run's plan, diff,
approval, and execution record as separate audit evidence.
