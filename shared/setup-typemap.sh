#!/bin/bash
# setup-typemap.sh - Applies the correct typemap based on the ENGINE environment variable.
#
# Usage: ENGINE=unreal ./setup-typemap.sh
#   ENGINE=unreal  → game-dev-common.txt + unreal-engine.txt
#   ENGINE=unity   → game-dev-common.txt + unity.txt
#   ENGINE=common  → game-dev-common.txt only
#   ENGINE=none    → skip typemap setup entirely
#
# This script is called by the entrypoint after p4d is running.

set -e

TYPEMAP_DIR="${TYPEMAP_DIR:-/shared/typemaps}"
ENGINE="${ENGINE:-unreal}"
P4USER="${P4USER:-super}"
P4PORT="${P4PORT:-1666}"
# Honor an explicit connect string. The prod entrypoint passes P4_CONNECT
# (e.g. ssl:localhost:1666) because p4d listens on an SSL prefix there and
# a plain "localhost:$P4PORT" connect string cannot reach it.
P4_CONNECT="${P4_CONNECT:-localhost:$P4PORT}"

if [ "$ENGINE" = "none" ]; then
    echo "ENGINE=none - skipping typemap setup."
    exit 0
fi

echo "Setting up typemap for ENGINE=$ENGINE..."

# Build combined typemap from base + engine-specific
COMBINED_TYPEMAP=""

# Always include the common base
if [ -f "$TYPEMAP_DIR/game-dev-common.txt" ]; then
    COMBINED_TYPEMAP=$(cat "$TYPEMAP_DIR/game-dev-common.txt")
    echo "  Loaded: game-dev-common.txt"
fi

# Layer engine-specific typemap on top
case "$ENGINE" in
    unreal)
        ENGINE_FILE="$TYPEMAP_DIR/unreal-engine.txt"
        ;;
    unity)
        ENGINE_FILE="$TYPEMAP_DIR/unity.txt"
        ;;
    common)
        ENGINE_FILE=""
        ;;
    *)
        echo "WARNING: Unknown ENGINE=$ENGINE. Using common typemap only."
        ENGINE_FILE=""
        ;;
esac

if [ -n "$ENGINE_FILE" ] && [ -f "$ENGINE_FILE" ]; then
    # Extract just the mapping lines from the engine file (skip the TypeMap: header and comments)
    ENGINE_MAPPINGS=$(grep -E '^\s+(binary|text|unicode|utf16|symlink)' "$ENGINE_FILE" || true)
    if [ -n "$ENGINE_MAPPINGS" ]; then
        # Append engine mappings to the combined typemap (after the base TypeMap: block)
        COMBINED_TYPEMAP=$(echo "$COMBINED_TYPEMAP"; echo "$ENGINE_MAPPINGS")
        echo "  Loaded: $(basename "$ENGINE_FILE")"
    fi
fi

# Apply the combined typemap
if [ -n "$COMBINED_TYPEMAP" ]; then
    echo "$COMBINED_TYPEMAP" | p4 -u "$P4USER" -p "$P4_CONNECT" typemap -i
    echo "Typemap applied successfully."
    echo "  Verify with: p4 -p \"$P4_CONNECT\" typemap -o"
else
    echo "WARNING: No typemap files found in $TYPEMAP_DIR"
fi
