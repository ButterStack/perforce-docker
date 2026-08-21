#!/bin/bash
# Example: Create a stream depot and development streams for a game project.
#
# Streams are Perforce's modern branching model - think Git branches but
# with explicit parent/child relationships and automatic merge direction.
#
# Usage: P4PORT=localhost:1666 P4USER=super ./setup-stream-depot.sh

set -e

P4PORT="${P4PORT:-localhost:1666}"
P4USER="${P4USER:-super}"
DEPOT_NAME="${1:-game}"

echo "Creating stream depot: $DEPOT_NAME"

# Create the stream depot
p4 -p "$P4PORT" -u "$P4USER" depot -o -t stream "$DEPOT_NAME" \
    | p4 -p "$P4PORT" -u "$P4USER" depot -i

echo "Creating mainline stream..."

# Create mainline stream (the trunk)
cat <<EOF | p4 -p "$P4PORT" -u "$P4USER" stream -i
Stream: //$DEPOT_NAME/main
Owner: $P4USER
Name: main
Parent: none
Type: mainline
Description: Main development line
Options: allsubmit unlocked notoparent nofromparent mergedown
Paths:
    share ...
EOF

echo "Creating development stream..."

# Create a development stream (branches from main)
cat <<EOF | p4 -p "$P4PORT" -u "$P4USER" stream -i
Stream: //$DEPOT_NAME/dev
Owner: $P4USER
Name: dev
Parent: //$DEPOT_NAME/main
Type: development
Description: Active development branch
Options: allsubmit unlocked toparent fromparent mergedown
Paths:
    share ...
EOF

echo "Creating release stream..."

# Create a release stream
cat <<EOF | p4 -p "$P4PORT" -u "$P4USER" stream -i
Stream: //$DEPOT_NAME/release
Owner: $P4USER
Name: release
Parent: //$DEPOT_NAME/main
Type: release
Description: Release stabilization branch
Options: allsubmit unlocked toparent fromparent mergedown
Paths:
    share ...
EOF

echo ""
echo "Stream depot '$DEPOT_NAME' created with streams:"
echo "  //$DEPOT_NAME/main      (mainline)"
echo "  //$DEPOT_NAME/dev       (development)"
echo "  //$DEPOT_NAME/release   (release)"
echo ""
echo "Create a workspace:"
echo "  p4 -p $P4PORT -u $P4USER client -S //$DEPOT_NAME/main -o my-workspace | p4 client -i"
echo "  p4 -p $P4PORT -u $P4USER -c my-workspace sync"
