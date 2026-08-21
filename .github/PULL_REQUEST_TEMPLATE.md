## What changed and why

## How you tested it

- [ ] Ran `dev` profile: `cd dev && docker compose up -d`
- [ ] Ran `prod` profile: `cd prod && P4PASSWD=... docker compose up -d`
- [ ] Checked `p4 typemap -o` if the typemap or entrypoint scripts changed
- [ ] Checked `docker compose logs perforce` for errors or warnings

## Checklist

- [ ] Dev and prod entrypoints stayed in sync where the logic should match
- [ ] README updated if behavior or defaults changed
