#!/bin/bash
# Example: Perforce trigger that kicks off a Jenkins build when commit message contains #ci.
#
# Install as a Perforce trigger:
#   Triggers:
#       jenkins-ci change-commit //depot/... "/path/to/jenkins-trigger.sh %changelist%"
#
# Required environment variables:
#   JENKINS_URL   - e.g., http://jenkins:8080
#   JENKINS_JOB   - e.g., GameBuild
#   JENKINS_USER  - Jenkins username
#   JENKINS_TOKEN - Jenkins API token

CHANGELIST="$1"
JENKINS_URL="${JENKINS_URL:-http://localhost:8080}"
JENKINS_JOB="${JENKINS_JOB:-Build}"
JENKINS_USER="${JENKINS_USER:-admin}"
JENKINS_TOKEN="${JENKINS_TOKEN:-}"

if [ -z "$CHANGELIST" ]; then
    exit 0
fi

# Check if commit message contains #ci
DESCRIPTION=$(p4 describe -s "$CHANGELIST" 2>/dev/null | head -20)
if ! echo "$DESCRIPTION" | grep -qi "#ci"; then
    exit 0
fi

echo "Found #ci in changelist $CHANGELIST - triggering Jenkins build..."

TRIGGER_URL="${JENKINS_URL}/job/${JENKINS_JOB}/buildWithParameters?P4_CHANGELIST=${CHANGELIST}"
HTTP_CODE=$(curl -s -o /dev/null -w '%{http_code}' \
    -X POST \
    -u "${JENKINS_USER}:${JENKINS_TOKEN}" \
    --max-time 10 \
    "$TRIGGER_URL" 2>/dev/null || echo "000")

if [ "$HTTP_CODE" -ge 200 ] && [ "$HTTP_CODE" -lt 300 ] 2>/dev/null; then
    echo "Jenkins build triggered for changelist $CHANGELIST"
else
    echo "WARNING: Jenkins trigger failed (HTTP $HTTP_CODE)" >&2
fi

# Never block submit
exit 0
