# GitHub Actions deployment and approval

This private repository's billing plan rejected GitHub environment required
reviewers (HTTP 422). The workflow therefore uses two **separate manual
dispatches**. The first produces an immutable saved plan and shows its full
diff and SHA-256 in the run summary. After reading that plan, `rspurgeon`
approves it by starting a second run with operation `deploy` and entering the
plan run ID, attempt, and exact SHA-256. The deploy job checks GitHub's actor,
the producer run, the artifact bytes, the source revision, the Konnect target,
the CLI version, and a 24-hour plan age before it applies the downloaded plan.
It never replans during deployment. Both operations share one concurrency
group. A rerun of a deploy attempt is rejected; use a fresh plan and approval.

The draft source review is [pull request #1](https://github.com/rspurgeon/summit-26/pull/1).
It must be merged to `main` before manual dispatch is available. The branch
contains the manifest, workflow, public certificate, scripts, and runbooks.
The ignored local `.env` and private data plane key are not pushed.

Current setup: `OPENAI_API_KEY`, `FULL_ACCESS_API_KEY`, and
`LIMITED_ACCESS_API_KEY` are configured as GitHub repository secrets. The two
Konnect CI PAT secrets are **not configured**. Automatic approval review
rejected creating new PATs with unspecified privilege scopes and exporting
them to GitHub. The workflow cannot plan or deploy until separately authorized
Konnect CI credentials are supplied.

## Repository secrets

Set these as **GitHub Actions repository secrets** after reviewing the PR:

| Secret | Purpose |
| --- | --- |
| `KONNECT_PLAN_PAT` | Read-capable token for Konnect organization `bc68a981-db50-43b4-a6bc-6a3ab0557d3c` |
| `KONNECT_APPLY_PAT` | Write-capable token for that same organization |
| `OPENAI_API_KEY` | Existing provider key |
| `FULL_ACCESS_API_KEY` | Caller key for all three models |
| `LIMITED_ACCESS_API_KEY` | Caller key for `demo-chat` only |

The two caller key values must match the ignored local `.env` so the verifier
on the data plane host can exercise those identities. Use distinct Konnect CI
tokens when available. The workflow checks the organization ID through each
token before planning or applying and uses `https://us.api.konghq.com` for
both jobs. The plan job does not reference provider or caller secrets.

Only repository owner `rspurgeon` currently has collaborator access. The
deploy job rejects any other GitHub actor. For stronger separation of duties,
use a GitHub plan that supports required-reviewer environments and update the
workflow. GitHub's [environment rules](https://docs.github.com/en/actions/reference/workflows-and-actions/deployments-and-environments)
would enforce approval before handing secrets to the job; this workflow's
approval is an explicit, identity-checked second dispatch instead.

## First deployment

1. Review and merge [pull request #1](https://github.com/rspurgeon/summit-26/pull/1)
   to `main`. A direct push to `main` was rejected by automatic approval
   review, so the default branch remains unchanged until the PR is merged.
2. In **Actions → Plan or deploy native AI Gateway → Run workflow**, select
   `main` and operation `plan`. Open the completed run. Read its diff, target,
   and SHA-256; record its run ID and attempt from the summary.
3. If the proposed changes are correct, start another run from `main` with
   operation `deploy` and enter that exact plan run ID, attempt, and SHA-256.
   The second dispatch is the approval record. Any mismatch stops before
   `kongctl apply`.
4. After deployment, on the host running the existing Docker data plane:

   ```sh
   set -a; source ./.env; set +a
   python3 scripts/verify-access.py live
   ```

   The hosted GitHub runner's `localhost` is not this gateway. The verifier
   checks all 12 caller/model cases; four successful cases invoke OpenAI.

The workflow installs official kongctl 1.16.0 after verifying the release
archive SHA-256, uses immutable action revisions, and retains plan and
execution artifacts for 14 days. An approved plan expires after 24 hours.
The public `certs/data-plane.crt` is committed; the matching private key
stays only on the data plane host.

## Repeat deployment

Run `plan` again from unchanged `main`. Its diff should say no changes and
show no secret writes. Review the new plan and approve with a new `deploy`
dispatch using that run's ID, attempt, and SHA-256. Keep both runs' artifacts
and summaries as separate audit evidence. Re-run the local access matrix.
A changed commit or expired plan needs a fresh plan and approval; a saved plan
is not a remote state lock.
