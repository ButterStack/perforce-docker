#!/bin/bash
# Example: Perforce trigger that dispatches a GitHub Actions workflow.
#
# Install as a Perforce trigger:
#   Triggers:
#       github-ci change-commit //depot/... "/path/to/github-actions-trigger.sh %changelist%"
#
# Required environment variables:
#   GITHUB_TOKEN - Personal access token or fine-grained token with Actions write permission
#   GITHUB_REPO  - e.g., YourOrg/YourGame

CHANGELIST="$1"
GITHUB_TOKEN="${GITHUB_TOKEN:-}"
GITHUB_REPO="${GITHUB_REPO:-}"
GITHUB_WORKFLOW="${GITHUB_WORKFLOW:-build.yml}"
GITHUB_REF="${GITHUB_REF:-main}"

if [ -z "$CHANGELIST" ] || [ -z "$GITHUB_TOKEN" ] || [ -z "$GITHUB_REPO" ]; then
    exit 0
fi

# Check for #ci tag
DESCRIPTION=$(p4 describe -s "$CHANGELIST" 2>/dev/null | head -20)
if ! echo "$DESCRIPTION" | grep -qi "#ci"; then
    exit 0
fi

echo "Found #ci in changelist $CHANGELIST - dispatching GitHub Actions workflow..."

HTTP_CODE=$(curl -s -o /dev/null -w '%{http_code}' \
    -X POST \
    -H "Accept: application/vnd.github+json" \
    -H "Authorization: Bearer $GITHUB_TOKEN" \
    "https://api.github.com/repos/$GITHUB_REPO/actions/workflows/$GITHUB_WORKFLOW/dispatches" \
    -d "{\"ref\":\"$GITHUB_REF\",\"inputs\":{\"changelist\":\"$CHANGELIST\"}}" \
    --max-time 10 2>/dev/null || echo "000")

if [ "$HTTP_CODE" -ge 200 ] && [ "$HTTP_CODE" -lt 300 ] 2>/dev/null; then
    echo "GitHub Actions workflow dispatched for changelist $CHANGELIST"
else
    echo "WARNING: GitHub Actions dispatch failed (HTTP $HTTP_CODE)" >&2
fi

exit 0
