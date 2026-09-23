#!/usr/bin/env python3
"""Fail closed unless the GitHub deployment environment requires review."""

import json
import os
from urllib.request import Request, urlopen

repository = os.environ["GITHUB_REPOSITORY"]
token = os.environ["GITHUB_TOKEN"]
url = f"https://api.github.com/repos/{repository}/environments/konnect-ai-gateway"
request = Request(url, headers={
    "Accept": "application/vnd.github+json",
    "Authorization": f"Bearer {token}",
    "X-GitHub-Api-Version": "2026-03-10",
})
with urlopen(request, timeout=15) as response:
    environment = json.load(response)
rules = environment.get("protection_rules", [])
reviewed = any(
    rule.get("type") == "required_reviewers"
    and len(rule.get("reviewers", [])) >= 1
    for rule in rules
)
if not reviewed:
    raise SystemExit("Deployment blocked: environment needs at least one required reviewer")
print("Required reviewer protection verified")
