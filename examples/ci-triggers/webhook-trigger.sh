#!/bin/bash
# Example: Perforce trigger that sends a webhook on changelist submit.
#
# Install as a Perforce trigger:
#   Triggers:
#       webhook change-commit //depot/... "/path/to/webhook-trigger.sh %changelist%"
#
# Configure the WEBHOOK_URL environment variable or edit the default below.

CHANGELIST="$1"
WEBHOOK_URL="${WEBHOOK_URL:-http://localhost:3000/webhooks/perforce}"
WEBHOOK_TOKEN="${WEBHOOK_TOKEN:-}"

if [ -z "$CHANGELIST" ]; then
    echo "Usage: webhook-trigger.sh <changelist>" >&2
    exit 0  # Exit 0 so we don't block the submit
fi

# Build JSON payload
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
JSON_PAYLOAD=$(cat <<EOF
{
    "changelist": "$CHANGELIST",
    "timestamp": "$TIMESTAMP",
    "server": "$P4PORT",
    "trigger": "submit"
}
EOF
)

# Send webhook (don't block submit on failure)
CURL_ARGS="-s -X POST -H 'Content-Type: application/json' -d '$JSON_PAYLOAD' --max-time 10"

if [ -n "$WEBHOOK_TOKEN" ]; then
    CURL_ARGS="$CURL_ARGS -H 'Authorization: Bearer $WEBHOOK_TOKEN'"
fi

RESPONSE=$(eval curl $CURL_ARGS -w "HTTPSTATUS:%{http_code}" "$WEBHOOK_URL" 2>/dev/null || echo "HTTPSTATUS:000")
HTTP_CODE=$(echo "$RESPONSE" | sed -e 's/.*HTTPSTATUS://')

if [ "$HTTP_CODE" -ge 200 ] && [ "$HTTP_CODE" -lt 300 ] 2>/dev/null; then
    echo "Webhook sent for changelist $CHANGELIST (HTTP $HTTP_CODE)"
else
    echo "WARNING: Webhook failed for changelist $CHANGELIST (HTTP $HTTP_CODE)" >&2
fi

# Always exit 0 - never block a submit because the webhook failed
exit 0
