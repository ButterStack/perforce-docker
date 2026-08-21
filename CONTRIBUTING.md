# Contributing

Thanks for taking a look at this project. It is a small, focused image: a
Perforce (Helix Core) server tuned for game dev teams on Unreal Engine 5 and
Unity, with a dev profile and a hardened production profile.

## Reporting a bug

Please include:

- Which profile you ran: `dev` or `prod`.
- The exact command you ran, and what you expected versus what happened.
- `p4 -V` output from inside the container (`docker compose exec perforce p4 -V`),
  so we know which pinned `helix-p4d` version you are on.
- The relevant environment variables you set (`ENGINE`, `SSL`,
  `CASE_INSENSITIVE`, `UNICODE`, etc.).
- Container logs: `docker compose logs perforce`.

The issue template will prompt for these.

## Proposing a change

- Open an issue first for anything beyond a small fix, so we can agree on the
  approach before you put time into it.
- Test changes against both profiles where relevant: `cd dev && docker compose up -d`
  and `cd prod && P4PASSWD=... docker compose up -d`. A change that only
  works in one profile is usually incomplete.
- If you change `shared/setup-typemap.sh` or either `entrypoint.sh`, verify by
  actually running the container and checking `p4 typemap -o`, not just by
  reading the script. This repo's one previous production-breaking bug (the
  typemap silently failing to apply under SSL) would have been caught by
  that one check.
- Keep the dev and prod entrypoints in sync where the underlying logic is the
  same (account bootstrap, typemap application). They are separate files on
  purpose (different defaults, different security posture), not because the
  logic should diverge.

## What this project is not

This is a Docker image and typemap set, not a full CI system. CI trigger
examples live in `examples/ci-triggers/` as a starting point, not a
maintained integration.
