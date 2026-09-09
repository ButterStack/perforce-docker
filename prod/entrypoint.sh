#!/bin/bash
# Perforce Game Server - Production Entrypoint
# SSL enabled, security level 3, strong passwords required.
# Built by ButterStack - https://butterstack.com

set -e

P4ROOT="${P4ROOT:-/data/p4depot/root}"
P4LOG="${P4LOG:-/data/p4depot/logs/log}"
P4PORT="${P4PORT:-1666}"
P4USER="${P4USER:-super}"
P4PASSWD="${P4PASSWD}"
P4REST_PORT="${P4REST_PORT:-8090}"
ENGINE="${ENGINE:-unreal}"
CASE_INSENSITIVE="${CASE_INSENSITIVE:-1}"
UNICODE="${UNICODE:-1}"
SSL="${SSL:-1}"
P4SSLDIR="${P4SSLDIR:-/data/ssl}"

# Validate required environment variables
if [ -z "$P4PASSWD" ]; then
    echo "ERROR: P4PASSWD environment variable is required for production."
    echo "  Set it in your docker-compose.yml or pass via: -e P4PASSWD=YourSecurePass123%"
    echo "  Password must be at least 8 characters with mixed case, numbers, and special chars."
    exit 1
fi

if [ ${#P4PASSWD} -lt 8 ]; then
    echo "ERROR: P4PASSWD must be at least 8 characters for production (security level 3)."
    exit 1
fi

# Ensure data directories exist
mkdir -p "$P4ROOT" "$(dirname "$P4LOG")" "$P4SSLDIR"

# SSL certificate setup
if [ "$SSL" = "1" ]; then
    export P4SSLDIR
    # p4d refuses to read or write SSL keys in a directory it considers
    # insecure and fails outright ("P4SSLDIR directory or key and
    # certificate files not secure"). mkdir -p above creates it 0755 under
    # the default umask, which p4d rejects, so every startup looped forever
    # regenerating a cert it could never write. Verified by running this
    # profile: without this chmod, `docker compose up` crash-loops on this
    # exact error.
    chmod 700 "$P4SSLDIR"
    # SSL_CERT_DIR (README-documented) is mounted read-only at /data/ssl/custom.
    # Prefer it over any previously auto-generated self-signed cert on every
    # startup, so a studio that mounts a real certificate actually gets it
    # instead of silently keeping whatever was generated the first time this
    # container ran without SSL_CERT_DIR set.
    CUSTOM_SSL_DIR="/data/ssl/custom"
    if [ -f "$CUSTOM_SSL_DIR/privatekey.txt" ] && [ -f "$CUSTOM_SSL_DIR/certificate.txt" ]; then
        echo "Using custom SSL certificate from SSL_CERT_DIR ($CUSTOM_SSL_DIR)..."
        cp "$CUSTOM_SSL_DIR/privatekey.txt" "$P4SSLDIR/privatekey.txt"
        cp "$CUSTOM_SSL_DIR/certificate.txt" "$P4SSLDIR/certificate.txt"
        chmod 600 "$P4SSLDIR/privatekey.txt"
    elif [ ! -f "$P4SSLDIR/privatekey.txt" ]; then
        echo "Generating self-signed SSL certificates..."
        # p4d -Gc generates a self-signed certificate pair
        p4d -r "$P4ROOT" -Gc
        # Move generated certs to the SSL directory if not already there
        if [ -f "$P4ROOT/sslkeys/privatekey.txt" ]; then
            cp "$P4ROOT/sslkeys/privatekey.txt" "$P4SSLDIR/"
            cp "$P4ROOT/sslkeys/certificate.txt" "$P4SSLDIR/"
        fi
        echo "SSL certificates generated in $P4SSLDIR"
    else
        echo "Using existing SSL certificates from $P4SSLDIR"
    fi
    P4_LISTEN="ssl:$P4PORT"
    P4_CONNECT="ssl:localhost:$P4PORT"
else
    P4_LISTEN="$P4PORT"
    P4_CONNECT="localhost:$P4PORT"
fi

# Initialize server on first run
if [ ! -f "$P4ROOT/db.config" ]; then
    echo "First run - initializing Perforce server..."
    IS_FIRST_RUN=1

    INIT_ARGS="-r $P4ROOT -J $P4ROOT/journal"
    NEEDS_INIT=0

    if [ "$CASE_INSENSITIVE" = "1" ]; then
        INIT_ARGS="$INIT_ARGS -C1"
        NEEDS_INIT=1
        echo "  Case insensitive mode enabled"
    fi

    if [ "$UNICODE" = "1" ]; then
        INIT_ARGS="$INIT_ARGS -xi"
        NEEDS_INIT=1
        echo "  Unicode mode enabled"
    fi

    if [ "$NEEDS_INIT" = "1" ]; then
        # -C1 only takes effect if it is part of the p4d invocation that first
        # creates the database. The previous code only ran this invocation
        # inside the UNICODE branch, so CASE_INSENSITIVE=1 with UNICODE=0
        # silently created a case-sensitive database while the log line above
        # claimed the opposite.
        p4d $INIT_ARGS
    fi
else
    echo "Existing data detected. Running schema upgrade..."
    IS_FIRST_RUN=0
    p4d -r "$P4ROOT" -J "$P4ROOT/journal" -xu
    echo "Schema upgrade complete."
fi

# Start p4d as daemon for initial setup
echo "Starting Perforce server for setup..."
p4d -r "$P4ROOT" -p "$P4_LISTEN" -L "$P4LOG" -J "$P4ROOT/journal" -d
sleep 3

# Trust our own SSL certificate for local connections. This MUST run after
# p4d is listening: verified by running this profile with SSL=1, trusting
# before the server started (the previous order) is a silent no-op, and the
# "wait for server" loop below then spins forever because `p4 info` over SSL
# fails on an untrusted certificate. The container never came up.
if [ "$SSL" = "1" ]; then
    p4 -p "$P4_CONNECT" trust -y 2>/dev/null || true
fi

# Wait for server
until p4 -u "$P4USER" -p "$P4_CONNECT" info > /dev/null 2>&1; do
    echo "Waiting for p4d..."
    sleep 2
done
echo "Perforce server is running."

# Create super user if it doesn't exist, and set its password if needed.
#
# The previous code branched on p4 login's free-text response ("doesn't
# exist" / "no password"). Verified by running this profile against a truly
# fresh volume: on this p4d version, logging in as a not-yet-configured
# super user with no password set does not return either string. It fails
# with "Password invalid." (when a line is piped as the answer) or a
# "Fatal client error ... EOF reading terminal" (when nothing is piped),
# so neither branch below ever fired, "Setting password for super..." never
# printed, and the server came up with P4PASSWD never actually applied,
# silently, with no error anywhere in the log.
set +e
LOGIN_OUTPUT=$(printf '%s\n' "$P4PASSWD" | p4 -u "$P4USER" -p "$P4_CONNECT" login 2>&1)
LOGIN_STATUS=$?
set -e
if [ $LOGIN_STATUS -ne 0 ]; then
    if echo "$LOGIN_OUTPUT" | grep -q "doesn't exist"; then
        echo "Creating user $P4USER..."
        p4 -u "$P4USER" -p "$P4_CONNECT" user -o \
            | p4 -u "$P4USER" -p "$P4_CONNECT" user -i -f
    fi

    echo "Setting password for $P4USER..."
    # Only the "new password, confirm" form (no old-password line) is used
    # here, and it only succeeds when no password is set yet. If a
    # different password is already set, this fails loudly instead of
    # silently leaving the server unreachable with $P4PASSWD.
    if printf '%s\n%s\n' "$P4PASSWD" "$P4PASSWD" | p4 -u "$P4USER" -p "$P4_CONNECT" passwd 2>&1; then
        printf '%s\n' "$P4PASSWD" | p4 -u "$P4USER" -p "$P4_CONNECT" login
    else
        echo "ERROR: Could not set the password for $P4USER."
        echo "ERROR: A password may already be set that does not match \$P4PASSWD."
        echo "ERROR: Connect manually and run 'p4 passwd' to reconcile it."
    fi
fi

# Ensure we're logged in before configuring security
printf '%s\n' "$P4PASSWD" | p4 -u "$P4USER" -p "$P4_CONNECT" login 2>/dev/null || true

# Fix expired password if needed (can happen on restart with existing data at security>0)
if p4 -u "$P4USER" -p "$P4_CONNECT" depots 2>&1 | grep -q "password has expired"; then
    echo "Password expired - fixing..."
    # Generated, not hardcoded: a fixed recovery password in a public repo
    # would be a literal, well-known credential for the recovery window.
    TEMP_PASS="$(openssl rand -base64 18)"
    printf '%s\n%s\n%s\n' "$P4PASSWD" "$TEMP_PASS" "$TEMP_PASS" \
        | p4 -u "$P4USER" -p "$P4_CONNECT" passwd
    printf '%s\n' "$TEMP_PASS" | p4 -u "$P4USER" -p "$P4_CONNECT" login
    # Temporarily lower security to fix password. The "Set security level"
    # step below restores security=3 before the server accepts real traffic.
    p4 -u "$P4USER" -p "$P4_CONNECT" configure set security=0
    printf '%s\n%s\n%s\n' "$TEMP_PASS" "$P4PASSWD" "$P4PASSWD" \
        | p4 -u "$P4USER" -p "$P4_CONNECT" passwd
    printf '%s\n' "$P4PASSWD" | p4 -u "$P4USER" -p "$P4_CONNECT" login
    echo "Password fix applied."
fi

# Set security level 3 (strong passwords required, ticket-based auth), then
# read the value back rather than trusting the "configure set" exit code:
# both commands below are suppressed (2>/dev/null || true) so a failure here
# would otherwise be invisible, and the banner used to print "Security: Level 3"
# unconditionally regardless of whether either command actually succeeded.
p4 -u "$P4USER" -p "$P4_CONNECT" configure set security=3 2>/dev/null || true
p4 -u "$P4USER" -p "$P4_CONNECT" configure set dm.password.minlength=8 2>/dev/null || true
SECURITY_LEVEL=$( { p4 -u "$P4USER" -p "$P4_CONNECT" configure show security 2>/dev/null | grep -o 'security=[0-9]*' | grep -o '[0-9]*$'; } || true)
SECURITY_LEVEL="${SECURITY_LEVEL:-unknown}"

# Grant protections. This is a deliberately restrictive default: only $P4USER
# has access to anything. Perforce's own wide-open default (`write user * * //...`)
# is NOT applied here, unlike the dev profile, because a production profile that
# advertises itself as "hardened" should not ship the most permissive protections
# table Perforce allows. Grant access to your team explicitly, for example:
#   p4 -p "$P4_CONNECT" protect   # edit the table, add e.g.:
#   write group developers * //depot/...
#
# Seed this table ONLY on first initialization ($IS_FIRST_RUN, set by the
# db.config check above), never on a restart of an already-initialized
# server. p4d persists the protections table in db.protect across restarts,
# so re-running this unconditionally on every container start silently wiped
# out whatever protections an operator had since configured, dropping every
# non-$P4USER account back to no access on the next restart or compose sync.
# This is exactly what happened on the bsg-cp-01 studio box on 2026-09-08.
# Do not remove this guard.
if [ "$IS_FIRST_RUN" = "1" ]; then
    echo "Protections:" > /tmp/protect.txt
    echo "	super user $P4USER * //..." >> /tmp/protect.txt
    if p4 -u "$P4USER" -p "$P4_CONNECT" protect -i < /tmp/protect.txt; then
        echo "Default protections table seeded (super user $P4USER only)."
    else
        echo "ERROR: Could not seed the initial protections table."
        echo "ERROR: The server may be running with no protections table set."
        echo "ERROR: Connect manually and run 'p4 -p \"$P4_CONNECT\" protect' to set one."
    fi
    rm -f /tmp/protect.txt
else
    echo "Existing data detected - leaving the protections table as configured."
fi

# Apply typemap
# P4_CONNECT carries the ssl: prefix p4d is actually listening on (see above).
# Without exporting it here, setup-typemap.sh falls back to a plain
# "localhost:$P4PORT" connect string, which an SSL-only listener refuses,
# and the typemap silently never applies.
TYPEMAP_STATUS="applied"
P4_CONNECT="$P4_CONNECT" setup-typemap.sh || {
    TYPEMAP_STATUS="FAILED"
    echo "ERROR: Typemap setup failed. The server is running but assets will NOT be typed correctly."
    echo "ERROR: Uasset/umap/binary files will get whatever type p4d guesses, with no exclusive lock."
    echo "ERROR: Fix the connection and re-run: P4_CONNECT=$P4_CONNECT setup-typemap.sh"
}

# Start REST API webserver in background
start_webserver() {
    if [ "$P4REST_PORT" = "0" ]; then
        echo "REST API disabled (P4REST_PORT=0)."
        return
    fi

    sleep 5
    until p4 -u "$P4USER" -p "$P4_CONNECT" info > /dev/null 2>&1; do
        sleep 3
    done

    printf '%s\n' "$P4PASSWD" | p4 -u "$P4USER" -p "$P4_CONNECT" login 2>/dev/null || true

    if p4 -u "$P4USER" -p "$P4_CONNECT" webserver start -p "$P4REST_PORT" 2>/dev/null; then
        echo "REST API available at http://localhost:$P4REST_PORT/api/version"

        REST_TICKET=$(printf '%s\n' "$P4PASSWD" | p4 -u "$P4USER" -p "$P4_CONNECT" login -h restapi -p 2>/dev/null | tail -1)
        if [ -n "$REST_TICKET" ]; then
            echo "$REST_TICKET" > /data/p4_rest_ticket
            echo "REST API ticket saved to /data/p4_rest_ticket"
        fi
    else
        echo "WARNING: Failed to start REST API (requires p4d 2025.2+)"
    fi
}

# Kill daemon - we'll restart in foreground
pkill -f "p4d.*$P4PORT" 2>/dev/null || true
sleep 2

# Launch webserver in background
start_webserver &

# Print connection info
echo ""
echo "============================================"
echo "  Perforce Game Server (Production)"
if [ "$SSL" = "1" ]; then
echo "  Port:     ssl:$P4PORT"
else
echo "  Port:     $P4PORT"
fi
echo "  User:     $P4USER"
echo "  REST API: http://localhost:$P4REST_PORT"
echo "  Engine:   $ENGINE"
echo "  Typemap:  $TYPEMAP_STATUS"
echo "  Security: Level $SECURITY_LEVEL"
if [ "$TYPEMAP_STATUS" != "applied" ]; then
echo ""
echo "  *** TYPEMAP DID NOT APPLY. See the ERROR lines above. ***"
fi
echo ""
if [ "$SSL" = "1" ]; then
echo "  Connect:  p4 -p ssl:localhost:$P4PORT -u $P4USER"
echo "  Trust:    p4 -p ssl:localhost:$P4PORT trust -y"
else
echo "  Connect:  p4 -p localhost:$P4PORT -u $P4USER"
fi
echo "============================================"
echo ""

# Start p4d in FOREGROUND
exec p4d -r "$P4ROOT" -p "$P4_LISTEN" -L "$P4LOG" -J "$P4ROOT/journal"
