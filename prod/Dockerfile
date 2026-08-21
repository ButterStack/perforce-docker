# Perforce Game Server - Production
# SSL enabled, security level 3, no default credentials.
# Built by ButterStack - https://butterstack.com

FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive

# Install base utilities + openssl for certificate generation
RUN apt-get update \
 && apt-get -y install curl gosu software-properties-common openssl \
 && rm -rf /var/lib/apt/lists/*

# Add Perforce official APT repository
RUN curl -fsSL https://package.perforce.com/perforce.pubkey \
      | gpg --dearmor -o /etc/apt/trusted.gpg.d/perforce.gpg \
 && apt-add-repository -y "deb http://package.perforce.com/apt/ubuntu noble release" \
 && rm -rf /var/lib/apt/lists/*

# Install helix-p4d (includes p4d, p4 CLI, p4dctl), pinned to a known version.
# Perforce's own "helix-p4d" apt package has no version constraint by
# default, so an unpinned build is not reproducible: two people running this
# quickstart a month apart get different p4d builds, and a rebuild on
# existing data can trigger an irreversible schema upgrade to a p4d version
# nobody chose. Bump P4D_VERSION deliberately, not by drifting with apt.
ARG P4D_VERSION=2026.1
RUN apt-get update \
 && apt-get -y install helix-p4d="${P4D_VERSION}"-* \
 && rm -rf /var/lib/apt/lists/*

# Environment defaults (prod-safe: no default password)
ENV P4PORT=1666
ENV P4USER=super
ENV P4ROOT=/data/p4depot/root
ENV P4LOG=/data/p4depot/logs/log
ENV P4REST_PORT=8090
ENV ENGINE=unreal
ENV CASE_INSENSITIVE=1
ENV UNICODE=1
ENV SSL=1
ENV P4SSLDIR=/data/ssl

# Copy shared typemaps and setup script
COPY --from=shared typemaps /shared/typemaps
COPY --from=shared setup-typemap.sh /usr/local/bin/setup-typemap.sh
RUN chmod +x /usr/local/bin/setup-typemap.sh

# Copy entrypoint
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

# p4d on 1666 (ssl), REST API on 8090
EXPOSE 1666 8090

# Shell "A || B && C" is (A || B) && C, not "A, else B then C": with SSL=0
# the previous single-line form still ran the SSL branch and failed, marking
# a healthy plaintext server unhealthy. Branch explicitly on $SSL instead,
# and use $P4PORT rather than a hardcoded 1666 so a container-side port
# override does not break the healthcheck too.
HEALTHCHECK --interval=30s --timeout=10s --start-period=45s --retries=5 \
    CMD sh -c 'if [ "$SSL" = "1" ]; then p4 -p ssl:localhost:$P4PORT info; else p4 -p localhost:$P4PORT info; fi'

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
