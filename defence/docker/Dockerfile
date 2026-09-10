# syntax=docker/dockerfile:1
#
# Siwang CTF privesc lab -- containerised build of the Stage 1-3 box.
#
#   Build context is defence/ , not defence/docker/ :
#       docker build -f docker/Dockerfile -t siwang-lab:1.0 .
#   or, preferably, use docker/docker-compose.yml which sets that up for you.
#
# THIS IMAGE IS DELIBERATELY VULNERABLE. Isolated lab networks only.
#
# Design notes
# ------------
# * ubuntu:24.04 is the base because the lab targets Ubuntu 24.04 LTS: that is
#   where PHP 8.3 (the version hardcoded in the vhosts and the FPM pool path)
#   and MariaDB 10.11 come from.
# * Apache, PHP-FPM and MariaDB share ONE container. The dev vhost routes PHP
#   through a unix socket -- /run/php/php8.3-fpm-siwang-dev.sock -- and the app
#   connects to the database on 127.0.0.1. Splitting them into three services
#   would mean rewriting those config lines, and those lines are the lab.
# * install.sh runs VERBATIM, via the systemctl stub in docker/systemctl, so
#   there is no second Docker-flavoured copy of the provisioning logic to keep
#   in sync. install.sh's own smoke test and verify.sh both run during build.

FROM ubuntu:24.04

LABEL org.opencontainers.image.title="Siwang CTF privesc lab (Stages 1-3)" \
      org.opencontainers.image.description="Deliberately vulnerable LAMP training box. Isolated lab networks only." \
      org.opencontainers.image.licenses="NOASSERTION"

ENV DEBIAN_FRONTEND=noninteractive \
    LANG=C.UTF-8

# Package maintainer scripts must not try to start services during the build;
# the stub systemctl below is for install.sh's calls, not apt's.
RUN printf '#!/bin/sh\nexit 101\n' > /usr/sbin/policy-rc.d \
 && chmod 0755 /usr/sbin/policy-rc.d

# Tools the lab scripts assume a real Ubuntu box already has but never install
# themselves -- sudo and `test -w` checks in verify.sh, getcap in verify.sh and
# lockdown.sh, ss in verify.sh -- plus what the container itself needs.
RUN apt-get update -qq \
 && apt-get install -y -qq --no-install-recommends \
        supervisor \
        sudo \
        libcap2-bin \
        iproute2 \
        procps \
        openssl \
        ca-certificates \
        curl \
 && rm -rf /var/lib/apt/lists/*

# 000-siwang-main.conf's :443 vhost points at a certbot path; without a
# certificate there Apache refuses to start and the whole build fails. Ship a
# self-signed one at exactly that path. To serve the real certificate, bind
# -mount your Let's Encrypt live directory over it (see docker-compose.yml).
RUN mkdir -p /etc/letsencrypt/live/siwang.duckdns.org \
 && openssl req -x509 -nodes -newkey rsa:2048 -days 3650 \
        -keyout /etc/letsencrypt/live/siwang.duckdns.org/privkey.pem \
        -out    /etc/letsencrypt/live/siwang.duckdns.org/fullchain.pem \
        -subj   "/CN=siwang.duckdns.org" \
        -addext "subjectAltName=DNS:siwang.duckdns.org,DNS:www.siwang.duckdns.org" \
        >/dev/null 2>&1 \
 && chmod 0600 /etc/letsencrypt/live/siwang.duckdns.org/privkey.pem

COPY docker/systemctl       /usr/local/bin/systemctl
COPY docker/entrypoint.sh   /usr/local/bin/siwang-entrypoint
COPY docker/supervisord.conf /etc/supervisor/conf.d/siwang.conf

COPY . /opt/siwang

# The repo is developed on Windows, where the working tree is checked out with
# CRLF (.gitattributes sets `* text=auto`). "#!/usr/bin/env bash\r" is not a
# valid interpreter on Linux, so a build from a Windows checkout dies on the
# first script. Normalising here reproduces exactly what a Linux checkout
# would have given us -- including the brochure's byte size, which Stage 1's
# `ffuf -fs` filter depends on being stable.
RUN find /opt/siwang -type f \( \
        -name '*.sh'   -o -name '*.php'  -o -name '*.sql' -o -name '*.conf' \
     -o -name '*.html' -o -name '*.css'  -o -name '*.js'  -o -name '*.md'   \
     -o -name '*.txt' \) -exec sed -i 's/\r$//' {} + \
 && chmod 0755 /usr/local/bin/systemctl /usr/local/bin/siwang-entrypoint \
               /opt/siwang/install/*.sh /opt/siwang/db/*.sh \
 && mkdir -p /var/log/supervisor

# Provision and self-test in ONE layer: processes do not survive between RUN
# instructions, and verify.sh needs the services install.sh started.
RUN set -eu; \
    /opt/siwang/install/install.sh; \
    echo "==> Running verify.sh against the freshly built box"; \
    /opt/siwang/install/verify.sh \
      || echo "!!! BUILD WARNING: verify.sh reported failures -- re-run it in the running container"; \
    systemctl stop apache2; \
    systemctl stop php8.3-fpm; \
    systemctl stop mariadb; \
    rm -rf /var/lib/apt/lists/* /run/apache2/*.pid /run/php/*.sock

# Stage 3 gives the student code execution as www-data. /opt/siwang holds the
# provisioning scripts and the pristine application source, including
# upload.php's filter and auth.php's cookie handling -- reading those is a
# shortcut past the puzzle. Root-only, matching how the VM build keeps the repo
# in an operator's home directory rather than under the docroot.
RUN chmod 0700 /opt/siwang

EXPOSE 80 443

HEALTHCHECK --interval=30s --timeout=5s --start-period=30s --retries=3 \
    CMD curl -fsS -H 'Host: dev.siwang.pineapple' http://127.0.0.1/login.php \
        | grep -q 'Sign in' || exit 1

ENTRYPOINT ["/usr/local/bin/siwang-entrypoint"]
