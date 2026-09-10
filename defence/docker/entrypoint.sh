#!/bin/bash
#
# Siwang CTF lab -- container entrypoint.
#
# The image ships a fully provisioned box: install.sh already ran at build
# time, so the vhosts, the FPM pool, the docroots, the seeded database and the
# lockdown permissions are all baked in. This script only does the things that
# cannot be baked into a layer:
#
#   1. rebuild /run (tmpfs, or stale files from the build)
#   2. re-assert the file capability on ping
#   3. re-provision the database IF someone mounted an empty volume over
#      /var/lib/mysql
#
# Then it hands over to supervisord.

set -euo pipefail

REPO=/opt/siwang
CONFIG=/var/www/dev/includes/config.php

echo "==> Preparing runtime directories"
install -d -m 0755 /run/php /run/apache2 /var/log/supervisor
install -d -o mysql -g mysql -m 0755 /run/mysqld
# Harmless when /run is a tmpfs; essential when it is not, because the build
# left pid files and a dead socket behind and Apache refuses to start over them.
rm -f /run/apache2/*.pid /run/php/*.sock /run/mysqld/*.pid /run/mysqld/*.sock

# lockdown.sh explains why this matters: without cap_net_raw the diagnostics
# rabbit hole returns "Operation not permitted" and stops being convincing.
# Docker grants SETFCAP and NET_RAW by default, so this normally succeeds.
if [[ -f /usr/bin/ping ]]; then
    setcap cap_net_raw+ep /usr/bin/ping 2>/dev/null \
        || echo "    warning: could not set cap_net_raw on ping" >&2
fi

# ---------------------------------------------------------------------------
# Fresh-volume path.
#
# By default the database lives in the image and a `docker compose down && up`
# gives a clean lab -- which is the reset behaviour the lab wants anyway. If a
# named volume was mounted at /var/lib/mysql and Docker did not pre-populate
# it, the baked database is hidden and has to be rebuilt here.
# ---------------------------------------------------------------------------
if [[ ! -d /var/lib/mysql/mysql ]]; then
    echo "==> /var/lib/mysql is empty -- provisioning a fresh database"
    mariadb-install-db --user=mysql --skip-test-db >/dev/null
    mariadbd --user=mysql >/var/log/siwang-init-mariadb.log 2>&1 &
    boot_pid=$!

    for _ in $(seq 1 60); do
        mysql -e 'SELECT 1' >/dev/null 2>&1 && break
        sleep 1
    done
    if ! mysql -e 'SELECT 1' >/dev/null 2>&1; then
        echo "error: MariaDB did not start; see /var/log/siwang-init-mariadb.log" >&2
        cat /var/log/siwang-init-mariadb.log >&2
        exit 1
    fi

    # Alphanumeric only, for the same reason db/setup.sh gives: the value ends
    # up inside a PHP single-quoted string and a sed replacement.
    DB_PASS="${SIWANG_DB_PASS:-$(tr -dc 'A-Za-z0-9' </dev/urandom | head -c 28)}"
    bash "${REPO}/db/setup.sh" "${DB_PASS}"

    echo "==> Re-syncing config.php with the new database password"
    sed -i "s|const DB_PASS = '[^']*';|const DB_PASS = '${DB_PASS}';|" "${CONFIG}"
    grep -q "const DB_PASS = '${DB_PASS}';" "${CONFIG}" \
        || { echo "error: could not write the DB password into ${CONFIG}." >&2; exit 1; }
    chown root:www-data "${CONFIG}"
    chmod 0640 "${CONFIG}"

    mysqladmin shutdown >/dev/null 2>&1 || true
    wait "${boot_pid}" 2>/dev/null || true
    echo "    database ready"
fi

echo "==> Starting mariadb, php-fpm and apache2 under supervisord"
exec /usr/bin/supervisord -c /etc/supervisor/conf.d/siwang.conf
