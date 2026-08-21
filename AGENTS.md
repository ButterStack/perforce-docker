# AGENTS.md - AI Integration Reference

This file helps AI coding assistants (Claude, Cursor, Copilot, etc.) work with the Perforce game server. Add this to your AI's context for productive Perforce operations.

## Connection

### Development Server
```
Host:     localhost:1666
User:     super
Password: dev123
```

```bash
# Set environment (saves typing)
export P4PORT=localhost:1666
export P4USER=super

# Login
echo "dev123" | p4 login

# Verify connection
p4 info
```

### Production Server
```
Host:     ssl:localhost:1666
User:     super
Password: (set via P4PASSWD env var, no default)
```

```bash
# Trust SSL certificate (first time only)
p4 -p ssl:localhost:1666 trust -y

# Login
p4 -p ssl:localhost:1666 -u super login
# (enter password when prompted)
```

## Common Commands

### Server Status
```bash
p4 info                    # Server info, version, root
p4 depots                  # List all depots
p4 users                   # List all users
p4 clients                 # List all workspaces
p4 counters                # Server counters (changelist number, etc.)
```

### Create a Depot
```bash
# Classic depot
p4 depot -o my-depot | p4 depot -i

# Stream depot (recommended for game dev)
p4 depot -o -t stream my-game | p4 depot -i
```

### Create a Workspace (Client)
```bash
# For classic depot
p4 client -o my-workspace | p4 client -i

# For stream depot
p4 client -S //my-game/main -o my-workspace | p4 client -i
```

### File Operations
```bash
# Sync files to workspace
p4 -c my-workspace sync

# Add new files
p4 -c my-workspace add path/to/file.txt

# Edit existing files (opens for edit, required before modifying)
p4 -c my-workspace edit path/to/file.txt

# Delete files
p4 -c my-workspace delete path/to/file.txt

# Submit changes
p4 -c my-workspace submit -d "Description of changes"

# View pending changes
p4 -c my-workspace opened

# Revert uncommitted changes
p4 -c my-workspace revert path/to/file.txt
```

### Changelists
```bash
# List recent changelists
p4 changes -m 10

# Describe a specific changelist
p4 describe -s 42

# Create a numbered pending changelist
p4 change -o | p4 change -i
```

### Streams
```bash
# Create mainline stream
cat <<EOF | p4 stream -i
Stream: //game/main
Owner: super
Name: main
Parent: none
Type: mainline
Options: allsubmit unlocked notoparent nofromparent mergedown
Paths:
    share ...
EOF

# Create development stream
cat <<EOF | p4 stream -i
Stream: //game/dev
Owner: super
Name: dev
Parent: //game/main
Type: development
Options: allsubmit unlocked toparent fromparent mergedown
Paths:
    share ...
EOF

# List streams
p4 streams //game/...

# Switch workspace to a different stream
p4 client -s -S //game/dev my-workspace
```

### Typemap
```bash
# View current typemap
p4 typemap -o

# Apply typemap from file
p4 typemap -i < typemap.txt

# The server auto-applies typemap on startup based on ENGINE env var:
#   ENGINE=unreal  → UE5 + common typemaps
#   ENGINE=unity   → Unity + common typemaps
#   ENGINE=common  → Common only (textures, audio, 3D, etc.)
```

## REST API

The p4d REST API (2025.2+) runs on port 8090 by default.

### Authentication

```bash
# Get a REST API ticket (must specify -h restapi)
TICKET=$(echo "dev123" | p4 -u super login -h restapi -p 2>/dev/null | tail -1)

# Or read saved ticket from container
TICKET=$(docker compose exec -T perforce cat /data/p4_rest_ticket 2>/dev/null)

# Use in requests
curl -u super:$TICKET http://localhost:8090/api/v0/depot
```

### Endpoints

```bash
# API version (no auth required)
curl http://localhost:8090/api/version

# Server info
curl -u super:$TICKET http://localhost:8090/api/v0/server/info

# List depots
curl -u super:$TICKET -H "Accept: application/jsonl" http://localhost:8090/api/v0/depot

# File metadata
curl -u super:$TICKET -H "Accept: application/jsonl" \
  "http://localhost:8090/api/v0/file/metadata?fileSpecs=//depot/..."

# File contents (text)
curl -u super:$TICKET -H "Accept: text/plain" \
  "http://localhost:8090/api/v0/file/contents?fileSpec=//depot/file.txt"

# File contents (binary - save to file)
curl -u super:$TICKET -o output.png \
  "http://localhost:8090/api/v0/file/contents?fileSpec=//depot/texture.png"

# Changelist info
curl -u super:$TICKET http://localhost:8090/api/v0/changelist/1
```

## Docker Operations

```bash
# Start dev server
cd dev && docker compose up -d

# Start prod server
cd prod && P4PASSWD=YourPassword123% docker compose up -d

# Start prod with Helix Swarm (code review)
cd prod && P4PASSWD=YourPassword123% docker compose --profile swarm up -d

# View logs
docker compose logs -f perforce

# Shell into container
docker compose exec perforce bash

# Run p4 commands inside container
docker compose exec perforce p4 info
docker compose exec perforce p4 depots

# Stop
docker compose down

# Stop and remove data (DESTRUCTIVE)
docker compose down -v

# Custom ports (avoid conflict with existing p4d)
P4_HOST_PORT=9166 REST_HOST_PORT=9090 docker compose up -d
```

## Typemap Modifiers Reference

| Type | Meaning | Example use |
|------|---------|------------|
| `binary+l` | Exclusive lock, server-compressed | `.uasset`, `.fbx`, `.blend` |
| `binary+lF` | Exclusive lock, no recompression | `.png`, `.jpg`, `.mp3`, `.mp4` |
| `binary+S2w` | Keep 2 revisions, writable | `.exe`, `.dll` |
| `binary+Sw` | Keep 1 revision, writable | `.pdb` (debug symbols) |
| `text` | Text, mergeable, newline translation | `.cpp`, `.cs`, `.ini`, `.meta` |
| `text+w` | Text, always writable | `.csproj`, `.sln` (engine-generated) |
| `text+x` | Text, executable bit | `.sh`, `.bat` |

## Troubleshooting

### "Password has expired"
The dev entrypoint handles this automatically. For manual fix:
```bash
# Change to temp password
printf 'old\nnew\nnew\n' | p4 passwd
p4 login  # with new password
p4 configure set security=0
# Change back
printf 'new\noriginal\noriginal\n' | p4 passwd
```

### "Case sensitivity mismatch"
Server initialized with `-C1` (case insensitive, default). If your client OS is case-sensitive and you see warnings, this is usually fine for game dev - UE and Unity expect case-insensitive behavior on Windows.

### "Unicode mode mismatch"
Server runs in Unicode mode by default. Set `P4CHARSET=utf8` on the client if you get charset errors:
```bash
p4 set P4CHARSET=utf8
```

### "SSL certificate not trusted"
```bash
p4 -p ssl:localhost:1666 trust -y
```

### REST API not responding
```bash
# Check if webserver started (look for "REST API available" in logs)
docker compose logs perforce | grep -i "rest\|webserver"

# Manually start webserver
docker compose exec perforce p4 -u super webserver start -p 8090

# Verify
curl http://localhost:8090/api/version
```

### Container won't start
```bash
# Check logs
docker compose logs perforce

# Common issue: port already in use
# Solution: use custom ports
P4_HOST_PORT=9166 REST_HOST_PORT=9090 docker compose up -d
```

## MCP Integration

The official [Perforce P4 MCP Server](https://github.com/perforce/p4mcp-server) lets AI coding assistants (Claude, Cursor, Copilot, etc.) interact with Perforce directly via tool calls - querying files, managing changelists, syncing workspaces, and more.

### Setup

#### 1. Build the MCP server image

```bash
git clone https://github.com/perforce/p4mcp-server.git
cd p4mcp-server
docker build -t p4-mcp .
```

#### 2. Create a dedicated MCP service account

Don't use `super` for MCP. Create a `background` type user with a long-lived ticket:

```bash
# Create the mcp-agent user (background type = no password expiry, no interactive login)
p4 user -o mcp-agent | sed 's/Type: standard/Type: service/' | p4 user -i -f

# Set a password
printf 'McpAgent123%%\nMcpAgent123%%\n' | p4 -u mcp-agent passwd

# Generate a long-lived ticket (persists across restarts)
printf 'McpAgent123%%\n' | p4 -u mcp-agent login -p -a
# Save the ticket hash output - this is what goes in your MCP config
```

#### 3. Configure your AI assistant

Use the **ticket hash** (not the password) in the `P4PASSWD` field. Perforce accepts tickets anywhere passwords are accepted.

**Claude Code** (`.mcp.json`):
```json
{
  "mcpServers": {
    "p4-mcp": {
      "command": "docker",
      "args": [
        "run", "--rm", "-i",
        "--network", "host",
        "-e", "P4PORT=localhost:1666",
        "-e", "P4USER=mcp-agent",
        "-e", "P4PASSWD=<TICKET_HASH>",
        "-e", "P4CLIENT=mcp-workspace",
        "p4-mcp",
        "python", "-m", "src.main",
        "--allow-usage",
        "--toolsets", "files,changelists,shelves,workspaces,jobs"
      ],
      "env": {}
    }
  }
}
```

**Claude Desktop** (`~/Library/Application Support/Claude/claude_desktop_config.json` on macOS):
```json
{
  "mcpServers": {
    "p4-mcp": {
      "command": "docker",
      "args": [
        "run", "--rm", "-i",
        "--network", "host",
        "-e", "P4PORT=localhost:1666",
        "-e", "P4USER=mcp-agent",
        "-e", "P4PASSWD=<TICKET_HASH>",
        "-e", "P4CLIENT=mcp-workspace",
        "p4-mcp",
        "python", "-m", "src.main",
        "--allow-usage",
        "--toolsets", "files,changelists,shelves,workspaces,jobs"
      ],
      "env": {}
    }
  }
}
```

> **Why a service account?** The `service` user type doesn't expire tickets, can't log in interactively, and can be given scoped permissions via the protect table. If the ticket leaks, revoke it with `p4 logout -a mcp-agent` - no password change needed.

### Docker Compose Networking

If your Perforce server runs via Docker Compose, use the Compose network instead of `--network host`:

```bash
# Replace --network host with:
--network perforce-docker_default

# And use the service name for P4PORT:
-e P4PORT=perforce:1666
```

### Available Toolsets

| Toolset | What it does |
|---------|-------------|
| `files` | List, read, add, edit, delete files in depots |
| `changelists` | Create, describe, submit changelists |
| `shelves` | Shelve/unshelve pending changes |
| `workspaces` | Create and manage client workspaces |
| `jobs` | Query and manage Perforce jobs |

### Verify MCP Connection

Once configured, your AI assistant should be able to run commands like:
- "List all depots on the Perforce server"
- "Show me the files in //depot/..."
- "Create a new changelist with description 'Update textures'"
- "What's in changelist 42?"
