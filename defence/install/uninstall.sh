#!/usr/bin/env bash
#
# Siwang CTF lab -- decommission a native (VM) install.
#
#   sudo ./uninstall.sh                    # stop the lab, free 80/443. Reversible.
#   sudo ./uninstall.sh --purge            # ...and delete configs, docroots, DB, logs
#   sudo ./uninstall.sh --purge --packages # ...and apt-purge apache/php/mariadb
#   sudo ./uninstall.sh --purge --dry-run  # show what would happen, change nothing
#   sudo ./uninstall.sh --purge --yes      # no confirmation prompt
#
# Written for the migration to docker/: the native Apache owns :80 and :443, so
# the container cannot publish them until this has run. The default (no flags)
# does exactly that much and nothing else -- `systemctl enable --now mariadb
# php8.3-fpm apache2` puts the box back.
#
# NEVER TOUCHED, whatever flags you pass:
#   /etc/letsencrypt   the real certificate -- the container can reuse it
#   /var/lib/mysql     other databases may live there; --packages purges the
#                      server but deliberately leaves the datadir alone
#   ufw rules, sshd    you still need to be able to reach the box
#
# This is a teardown, so every step is best-effort: a failure is reported and
# the script carries on rather than leaving the box half-dismantled.

set -uo pipefail

PHP_VER="8.3"
SERVICES=("apache2" "php${PHP_VER}-fpm" "mariadb")

WWW_MAIN="/var/www/main"
WWW_DEV="/var/www/dev"
WWW_BACKUP="/var/www/backup"
SESSION_DIR="/var/lib/php/siwang-dev-sessions"
FPM_POOL="/etc/php/${PHP_VER}/fpm/pool.d/siwang-dev.conf"

PURGE=0
PACKAGES=0
DRYRUN=0
ASSUME_YES=0

for arg in "$@"; do
    case "$arg" in
        --purge)    PURGE=1 ;;
        --packages) PACKAGES=1; PURGE=1 ;;
        --dry-run)  DRYRUN=1 ;;
        --yes|-y)   ASSUME_YES=1 ;;
        -h|--help)  sed -n '3,23p' "$0" | cut -c3-; exit 0 ;;
        *) echo "unknown option: $arg (try --help)" >&2; exit 1 ;;
    esac
done

# A dry run only reads and prints, so let anyone preview the teardown.
if [[ $EUID -ne 0 && $DRYRUN -eq 0 ]]; then
    echo "error: run with sudo (or add --dry-run to preview)." >&2
    exit 1
fi

FAILED=0
run() {
    if [[ $DRYRUN -eq 1 ]]; then
        echo "    [dry-run] $*"
        return 0
    fi
    echo "    running: $*"
    if ! "$@"; then
        echo "      (failed -- continuing)" >&2
        FAILED=$((FAILED + 1))
    fi
}

echo "############################################################"
echo "#  Siwang lab decommission"
echo "#    mode:     $([[ $PURGE -eq 1 ]] && echo purge || echo stop-only)"
echo "#    packages: $([[ $PACKAGES -eq 1 ]] && echo apt-purge || echo keep)"
echo "#    dry-run:  $([[ $DRYRUN -eq 1 ]] && echo yes || echo no)"
echo "############################################################"

if [[ $PURGE -eq 1 && $DRYRUN -eq 0 && $ASSUME_YES -eq 0 ]]; then
    echo
    echo "This will DELETE:"
    echo "    ${WWW_MAIN}, ${WWW_DEV}, ${WWW_BACKUP}   (including student uploads)"
    echo "    the siwang_dev database and the siwang_app user"
    echo "    the lab's Apache vhosts, hardening conf and FPM pool"
    if [[ $PACKAGES -eq 1 ]]; then
        echo "    apache2, php${PHP_VER}-*, mariadb-server   (apt purge)"
    fi
    echo
    read -r -p "Type 'yes' to continue: " reply
    if [[ "$reply" != "yes" ]]; then echo "aborted."; exit 1; fi
fi

# ---------------------------------------------------------------------------
# 1. Database -- BEFORE stopping MariaDB, or there is nothing to talk to.
# ---------------------------------------------------------------------------
if [[ $PURGE -eq 1 ]]; then
    echo "==> Dropping the lab database"
    DROP_SQL="DROP DATABASE IF EXISTS siwang_dev; DROP USER IF EXISTS 'siwang_app'@'127.0.0.1'; FLUSH PRIVILEGES;"
    if command -v mysql >/dev/null 2>&1 && mysql -e 'SELECT 1' >/dev/null 2>&1; then
        if [[ $DRYRUN -eq 1 ]]; then
            echo "    [dry-run] mysql -e \"${DROP_SQL}\""
        elif mysql -e "${DROP_SQL}"; then
            echo "    dropped siwang_dev and siwang_app"
        else
            echo "    warning: drop failed" >&2
            FAILED=$((FAILED + 1))
        fi
    else
        echo "    MariaDB not reachable as root -- skipping (already down, or never installed)"
    fi
fi

# ---------------------------------------------------------------------------
# 2. Stop and disable the services. This is what frees :80 and :443.
# ---------------------------------------------------------------------------
echo "==> Stopping and disabling services"
for svc in "${SERVICES[@]}"; do
    if systemctl cat "${svc}.service" >/dev/null 2>&1; then
        run systemctl disable --now "${svc}"
    else
        echo "    ${svc}: not installed, skipping"
    fi
done

# ---------------------------------------------------------------------------
# 3. Apache and PHP-FPM configuration.
# ---------------------------------------------------------------------------
if [[ $PURGE -eq 1 ]]; then
    echo "==> Removing the lab's Apache configuration"
    if command -v a2dissite >/dev/null 2>&1; then
        run a2dissite --quiet 000-siwang-main 010-siwang-dev 020-siwang-backup
        run a2disconf --quiet siwang-hardening
        # install.sh disabled the stock vhost so ours would sort first. Put it
        # back, or a later `apt install apache2` on this box serves nothing.
        run a2ensite --quiet 000-default
    fi
    run rm -f /etc/apache2/sites-available/000-siwang-main.conf \
              /etc/apache2/sites-available/010-siwang-dev.conf \
              /etc/apache2/sites-available/020-siwang-backup.conf \
              /etc/apache2/conf-available/siwang-hardening.conf
    run rm -f "${FPM_POOL}"
fi

# ---------------------------------------------------------------------------
# 4. Docroots, sessions, logs.
# ---------------------------------------------------------------------------
if [[ $PURGE -eq 1 ]]; then
    echo "==> Removing document roots and lab state"
    run rm -rf "${WWW_MAIN}" "${WWW_DEV}" "${WWW_BACKUP}" "${SESSION_DIR}"
    run rm -f /var/log/php-siwang-dev.log
    if [[ $DRYRUN -eq 1 ]]; then
        echo "    [dry-run] rm -f /var/log/apache2/siwang-*.log"
    else
        echo "    running: rm -f /var/log/apache2/siwang-*.log"
        rm -f /var/log/apache2/siwang-*.log 2>/dev/null
    fi
fi

# ---------------------------------------------------------------------------
# 5. Packages.
# ---------------------------------------------------------------------------
if [[ $PACKAGES -eq 1 ]]; then
    echo "==> Purging packages"
    export DEBIAN_FRONTEND=noninteractive
    run apt-get purge -y -qq \
        apache2 apache2-utils apache2-bin libapache2-mod-fcgid \
        "php${PHP_VER}-fpm" "php${PHP_VER}-mysql" "php${PHP_VER}-cli" "php${PHP_VER}-gd" \
        mariadb-server mariadb-client
    run apt-get autoremove -y --purge -qq
    echo "    note: /var/lib/mysql was left in place. If this box held no other"
    echo "          databases you can remove it by hand: sudo rm -rf /var/lib/mysql"
fi

# ---------------------------------------------------------------------------
# 5b. Remove Stage 7-8 host material (the SSH user + SUID PATH-hijack that
#     privesc-host.sh installs on the host, if it was ever run here).
# ---------------------------------------------------------------------------
if [[ $PURGE -eq 1 ]]; then
    echo "==> Removing Stage 7-8 host material (if present)"
    PRIVESC="$(dirname "$0")/privesc-host.sh"
    if [[ -f "$PRIVESC" ]]; then
        if [[ $DRYRUN -eq 1 ]]; then
            echo "    [dry-run] bash ${PRIVESC} --uninstall"
        else
            bash "$PRIVESC" --uninstall || echo "    privesc-host.sh --uninstall reported a problem (continuing)"
        fi
    else
        # Fall back to removing the known artifacts directly.
        run rm -f /usr/local/bin/opsbackup /etc/ssh/sshd_config.d/60-siwang-lab.conf
        if id chrysanta >/dev/null 2>&1; then
            run userdel -r chrysanta
        fi
    fi
fi

# ---------------------------------------------------------------------------
# 6. Verify the ports the container needs are actually free.
# ---------------------------------------------------------------------------
echo "==> Checking that :80 and :443 are free"
if [[ $DRYRUN -eq 1 ]]; then
    echo "    [dry-run] ss -ltnpH | awk '\$4 ~ /:(80|443)\$/'"
elif command -v ss >/dev/null 2>&1; then
    BUSY="$(ss -ltnpH 2>/dev/null | awk '$4 ~ /:(80|443)$/')"
    if [[ -n "${BUSY}" ]]; then
        echo "    STILL LISTENING -- the container will fail to publish its ports:" >&2
        echo "${BUSY}" | sed 's/^/      /' >&2
        FAILED=$((FAILED + 1))
    else
        echo "    :80 and :443 are free"
    fi
else
    echo "    ss not available -- check by hand: sudo lsof -i :80 -i :443"
fi

echo
echo "############################################################"
if [[ $FAILED -gt 0 ]]; then
    echo "#  Done, with ${FAILED} step(s) reporting errors -- read the log above."
else
    echo "#  Done."
fi
echo "#"
if [[ $PURGE -eq 0 ]]; then
    echo "#  Nothing was deleted. To put the native lab back:"
    echo "#      sudo systemctl enable --now mariadb php${PHP_VER}-fpm apache2"
else
    echo "#  The native lab is gone. /etc/letsencrypt was left untouched."
fi
echo "#"
echo "#  Next:  cd ../docker && docker compose up -d --build"
echo "############################################################"
