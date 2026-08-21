---
name: Bug report
about: Something in the dev or prod profile is not working as documented
title: ""
labels: bug
assignees: ""
---

**Profile**
dev or prod?

**What happened**
A clear description of what you ran and what happened.

**What you expected**
What you expected to happen instead.

**p4d version**
Output of `docker compose exec perforce p4 -V`

**Environment variables**
Any non-default values for `ENGINE`, `SSL`, `CASE_INSENSITIVE`, `UNICODE`,
`P4REST_PORT`, `SSL_CERT_DIR`, etc.

**Container logs**
Relevant output of `docker compose logs perforce`. Redact any real
credentials or hostnames before pasting.

**Additional context**
Anything else that seems relevant (host OS, Docker version, Apple Silicon vs
Intel, whether this is a fresh volume or existing data).
