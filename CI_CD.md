# GitHub Actions deployment setup

The workflow at `.github/workflows/deploy-ai-gateway.yml` is manually
dispatched from `main`. It plans against the existing US Konnect organization,
uploads a run and attempt specific plan/diff/manifest artifact, and exposes
the proposed actions and SHA-256 in the run summary. The apply job downloads
that same artifact after environment review. It verifies the plan hash,
source revision, target, kongctl version, apply mode, 24-hour age, and current
`main` revision before applying. Jobs for this target are serialized.

## Repository configuration required before dispatch

1. In **Settings → Environments**, create `konnect-ai-gateway`. Configure
   **Required reviewers** (for example, repository owner `rspurgeon`); leave
   **Prevent self-review** off so the person
   who starts the run may approve it. Restrict deployment branches to `main`.
   The workflow also checks the reviewer rule through GitHub's API and fails
   closed if it is absent. Confirm the repository's visibility and GitHub
   plan support required reviewers.
2. Add repository secret `KONNECT_PLAN_PAT` with read access to organization
   `bc68a981-db50-43b4-a6bc-6a3ab0557d3c` at
   `https://us.api.konghq.com`.
3. Add these **environment secrets** to `konnect-ai-gateway`:
   `KONNECT_APPLY_PAT` (write capable for that same org), `OPENAI_API_KEY`,
   `FULL_ACCESS_API_KEY`, and `LIMITED_ACCESS_API_KEY`. Use the same two caller
   key values stored in the local ignored `.env` so the local verifier can
   exercise those identities. Keep the caller keys distinct.
4. Protect `main` so workflow and manifest edits receive code review. Check
   that the public `certs/data-plane.crt` is committed; the matching private
   key remains only on the data plane host.

GitHub [required reviewers and environment secrets](https://docs.github.com/en/actions/reference/workflows-and-actions/deployments-and-environments)
provide the human gate. An environment name in YAML alone does not. The
workflow checks the actual [environment protection rule](https://docs.github.com/en/rest/deployments/environments)
before applying. If that API check fails, deployment stops.

The current local GitHub CLI token is invalid, so repository environment
settings and secrets have **not** been configured here. The source is on
review branch `ai-gateway-access-ci` at
`https://github.com/rspurgeon/summit-26/pull/new/ai-gateway-access-ci`.

## First approved run

1. Review the `ai-gateway-access-ci` branch in a pull request and merge it to
   `main`. The existing local private key and `.env` are ignored.
2. In **Actions → Deploy native AI Gateway → Run workflow**, select `main`.
   Inspect the plan job's summary, full diff, and artifact digest.
3. Approve the waiting `konnect-ai-gateway` environment deployment as the
   configured reviewer. Reject and rerun if the source, target, or actions
   differ from the intended change.
4. After apply succeeds, check the local container and run
   `python3 scripts/verify-access.py live` from this host with caller keys
   loaded from `.env`. The hosted runner's `localhost` is not this gateway.

The workflow's plan job does not receive provider or caller secrets. The
apply job receives them only after the environment gate. It installs the
official kongctl 1.16.0 Linux archive after checking its pinned SHA-256, and
uses immutable action revisions. It retains the plan and execution artifacts
for 14 days. Expired plans require a new run and approval.

## Repeat deployment

Dispatch the workflow again from unchanged `main`. The new plan should say
`No changes detected` and include no secret writes. Review and approve that
new run. Verify the execution report and run the local access matrix again.
An unrelated manual Konnect edit or a changed commit needs a fresh plan and
review; the saved plan is not a remote state lock.
