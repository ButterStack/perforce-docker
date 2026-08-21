# Perforce Docker

**Run a production-ready Perforce server for game dev in 30 seconds.**

A Docker-based Perforce (Helix Core) server built specifically for game development teams using Unreal Engine 5 and Unity. Includes comprehensive typemaps, REST API, SSL support, and optional Helix Swarm - all with a single `docker compose up`.

Built by [ButterStack](https://butterstack.com).

## Quick Start

### Development (local, fast)

```bash
cd dev
docker compose up -d
```

Connect with any Perforce client:
```
Server:   localhost:1666
Username: super
Password: dev123
```

### Production (SSL, hardened)

```bash
cd prod
P4PASSWD=YourSecurePassword123% docker compose up -d
```

Connect:
```
Server:   ssl:localhost:1666
Username: super
Password: (your P4PASSWD)
```

Trust the self-signed certificate on first connect:
```bash
p4 -p ssl:localhost:1666 trust -y
```

## Features

### Game Engine Typemaps

The most comprehensive game dev typemaps available - applied automatically based on the `ENGINE` environment variable.

```bash
ENGINE=unreal  # Unreal Engine 5 (default)
ENGINE=unity   # Unity
ENGINE=common  # Base only (textures, audio, 3D, etc.)
ENGINE=none    # Skip typemap setup
```

Key typemap decisions:
- **`binary+lF`** for pre-compressed assets (PNG, JPG, MP3) - exclusive lock, no wasted recompression
- **`binary+l`** for raw binary assets (uasset, umap, FBX, PSD) - exclusive lock, server-compressed
- **`binary+S2w`** for executables - keep 2 revisions, save terabytes on large projects
- **`binary+Sw`** for debug symbols (PDB) - keep 1 revision only
- **`text`** for Unity `.meta` files - critical for preserving asset GUIDs

See [docs/TYPEMAP_GUIDE.md](docs/TYPEMAP_GUIDE.md) for the full deep-dive on every entry.

### REST API (p4d 2025.2)

The p4d REST API webserver starts automatically on port 8090:

```bash
# No auth needed
curl http://localhost:8090/api/version

# With auth (get ticket from /data/p4_rest_ticket in container)
curl -u super:TICKET http://localhost:8090/api/v0/depot
curl -u super:TICKET http://localhost:8090/api/v0/file/metadata?fileSpecs=//depot/...
```

Disable with `P4REST_PORT=0`.

### Dev vs Production

| Aspect | Dev | Prod |
|--------|-----|------|
| Security level | 0 (simple passwords) | 3 (strong passwords, tickets) |
| SSL/TLS | Off (`localhost:1666`) | On (`ssl:localhost:1666`) |
| Default credentials | `super` / `dev123` | Must set `P4PASSWD` (no defaults) |
| Password expiry | Disabled | Enforced |
| REST API | Open | Ticket-auth required |
| Protections | `super` full access, everyone else write-open (deliberately permissive for local dev) | Only `super` has access by default (see below) |
| Case sensitivity | Insensitive (configurable) | Insensitive (configurable) |
| Unicode | Enabled | Enabled |
| Startup | Fast | Slower (SSL cert generation, security hardening) |

**Protections in prod changed in this release.** Earlier versions granted every
user write access to every depot by default (`write user * * //...`), the same
wide-open table the dev profile intentionally uses, despite a comment claiming
otherwise. Prod now grants access to `$P4USER` only; everyone else has no
access until you explicitly grant it, for example:

```bash
p4 -p ssl:localhost:1666 -u super protect
# add a line like: write group developers * //depot/...
```

If you were relying on the old wide-open default, add an explicit grant like
the one above before your team's clients hit "no permission" errors.

### Optional: Helix Swarm

Code review for Perforce, included as an optional Docker Compose profile in the prod configuration:

```bash
cd prod
P4PASSWD=YourSecurePassword123% docker compose --profile swarm up -d
# Swarm UI at http://localhost:8080
```

Swarm connects to `ssl:perforce:1666` by default, matching prod's default
`SSL=1`. If you run prod with `SSL=0`, override the connect string:

```bash
SWARM_P4PORT=perforce:1666 P4PASSWD=... docker compose --profile swarm up -d
```

Swarm also needs to trust p4d's certificate before it can connect. With the
default self-signed certificate this requires a manual trust step inside the
Swarm container; using a real certificate via `SSL_CERT_DIR` avoids this.

## Configuration

### Environment Variables

```bash
# Credentials
P4USER=super                  # Admin username (default: super)
P4PASSWD=dev123               # Password (required in prod, default in dev)

# Engine typemap
ENGINE=unreal                 # unreal | unity | common | none

# Server options
CASE_INSENSITIVE=1            # Case insensitive (1=yes, default for game dev)
UNICODE=1                     # Unicode mode (1=yes, default)
P4REST_PORT=8090              # REST API port (0 to disable)
SSL=1                         # SSL (prod default: 1, dev default: 0)

# Port mapping (host-side)
P4_HOST_PORT=1666             # Host port for p4d
REST_HOST_PORT=8090           # Host port for REST API
```

### Custom Ports

Override host-side ports to avoid conflicts (e.g., if you already have p4d running on 1666):

```bash
P4_HOST_PORT=9166 REST_HOST_PORT=9090 docker compose up -d
# Connect: p4 -p localhost:9166 -u super
```

### Custom SSL Certificates

Mount your certificates in prod:

```bash
SSL_CERT_DIR=/path/to/certs docker compose up -d
# Expects: privatekey.txt and certificate.txt in the directory
```

This takes priority over the auto-generated self-signed certificate on every
startup, including restarts of a container that previously generated its own
certificate. `privatekey.txt` should be a PEM-format RSA private key with no
passphrase; `certificate.txt` the matching PEM-format certificate.

### p4d Version

The image pins `helix-p4d` to a specific version (`P4D_VERSION` build arg in
`dev/Dockerfile` and `prod/Dockerfile`, currently `2026.1`) rather than
floating on whatever the Perforce apt repository currently ships. This makes
builds reproducible and keeps the version an explicit, deliberate choice: an
unpinned build can pull a newer p4d on rebuild, and the entrypoint's schema
upgrade (`p4d -xu`) on existing data is one-way once it runs against a newer
major version.

## What makes this different

Most Perforce Docker images get you a running p4d. This one is tuned for a game
team's actual working set:

- **Unity `.meta` files typed as `text`** so asset GUIDs survive merges. Getting
  this wrong corrupts references across the whole project.
- **Revision limits on build output**: `binary+S2w` for executables, `binary+Sw`
  for PDBs. On a project shipping nightly builds this is the difference between
  a depot that grows linearly and one that grows without bound.
- **Separate dev and prod profiles**, so the fast local server and the hardened
  one are not the same config with a flag.
- **CI trigger examples** for webhooks, Jenkins, and GitHub Actions.
- **`AGENTS.md`** for wiring the server to the official Perforce P4 MCP server.

## Project Structure

```
perforce-docker/
├── dev/                     # Development configuration
│   ├── Dockerfile           # Fast, no SSL, security=0
│   ├── docker-compose.yml   # One-command dev setup
│   └── entrypoint.sh        # Dev entrypoint
├── prod/                    # Production configuration
│   ├── Dockerfile           # SSL, security=3, hardened
│   ├── docker-compose.yml   # Prod + optional Swarm
│   └── entrypoint.sh        # Prod entrypoint
├── shared/                  # Shared between dev and prod
│   ├── typemaps/
│   │   ├── game-dev-common.txt    # Base typemap (textures, audio, 3D, etc.)
│   │   ├── unreal-engine.txt      # UE5-specific overrides
│   │   └── unity.txt              # Unity-specific overrides
│   ├── p4ignore             # .p4ignore template (UE + Unity)
│   └── setup-typemap.sh     # Applies typemap based on ENGINE
├── examples/
│   ├── streams/             # Stream depot setup
│   └── ci-triggers/         # Webhook + Jenkins + GitHub Actions triggers
├── docs/
│   └── TYPEMAP_GUIDE.md     # Deep-dive on every typemap entry
├── AGENTS.md                # AI/LLM integration reference
├── LICENSE                  # MIT
└── README.md
```

## .p4ignore

Copy the included `.p4ignore` template to your workspace root:

```bash
cp shared/p4ignore /path/to/workspace/.p4ignore
p4 set P4IGNORE=.p4ignore
```

Covers Unreal Engine, Unity, IDE files, and OS artifacts.

## Examples

### Stream Depot Setup

```bash
# Create a stream depot with main/dev/release streams
./examples/streams/setup-stream-depot.sh game
```

### CI Triggers

See `examples/ci-triggers/` for ready-to-use trigger scripts:
- **webhook-trigger.sh** - Generic webhook on submit
- **jenkins-trigger.sh** - Jenkins build on `#ci` tag
- **github-actions-trigger.sh** - GitHub Actions dispatch on `#ci` tag

## AI Integration

Works with the official [Perforce P4 MCP Server](https://github.com/perforce/p4mcp-server) so AI coding assistants (Claude, Cursor, Copilot) can query files, manage changelists, and sync workspaces directly.

Create a dedicated `service` type user for MCP (no password expiry, revocable ticket), then add to your `.mcp.json`:

```json
{
  "mcpServers": {
    "p4-mcp": {
      "command": "docker",
      "args": [
        "run", "--rm", "-i", "--network", "host",
        "-e", "P4PORT=localhost:1666",
        "-e", "P4USER=mcp-agent",
        "-e", "P4PASSWD=<TICKET_HASH>",
        "-e", "P4CLIENT=mcp-workspace",
        "p4-mcp",
        "python", "-m", "src.main",
        "--allow-usage",
        "--toolsets", "files,changelists,shelves,workspaces,jobs"
      ]
    }
  }
}
```

See [AGENTS.md](AGENTS.md) for the full setup guide - creating the service account, generating tickets, Docker Compose networking, and an LLM-friendly command reference.

## License

MIT. See [LICENSE](LICENSE).

---

Built with battle-tested patterns from [ButterStack](https://butterstack.com) - the game dev pipeline platform.
