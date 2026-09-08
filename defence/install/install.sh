#!/usr/bin/env bash
#
# Siwang CTF lab -- provisioner for a clean Ubuntu 24.04 LTS box.
#
#   sudo ./install.sh
#
# Idempotent enough to re-run: it re-copies docroots, rewrites the config with a
# fresh DB password, and reloads services. It does NOT wipe uploaded files on
# re-run (use lockdown.sh --reset for that).
#
# This provisions Stages 1-3 only. The www-data -> user -> root chain is a
# separate, later build; nothing here creates the local `siwang` user or any
# sudo rule.

set -euo pipefail

# ---------------------------------------------------------------------------
# Paths and constants
# ---------------------------------------------------------------------------
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"   # the defence/ dir
PHP_VER="8.3"
FPM_POOL_DST="/etc/php/${PHP_VER}/fpm/pool.d/siwang-dev.conf"
FPM_SOCK="/run/php/php${PHP_VER}-fpm-siwang-dev.sock"
SESSION_DIR="/var/lib/php/siwang-dev-sessions"

WWW_MAIN="/var/www/main"
WWW_DEV="/var/www/dev"
WWW_BACKUP="/var/www/backup"

if [[ $EUID -ne 0 ]]; then
    echo "error: run with sudo." >&2
    exit 1
fi

echo "############################################################"
echo "#  Siwang lab installer  (Stages 1-3)"
echo "############################################################"

# ---------------------------------------------------------------------------
# 1. Packages
# ---------------------------------------------------------------------------
echo "==> Installing packages"
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq \
    apache2 \
    "php${PHP_VER}-fpm" "php${PHP_VER}-mysql" "php${PHP_VER}-cli" \
    mariadb-server \
    libapache2-mod-fcgid \
    iputils-ping \
    curl ca-certificates >/dev/null

# ---------------------------------------------------------------------------
# 2. Apache modules and vhosts
# ---------------------------------------------------------------------------
echo "==> Configuring Apache"
a2enmod proxy proxy_fcgi setenvif headers rewrite >/dev/null 2>&1 || true
a2dismod --quiet php"${PHP_VER}" mpm_prefork >/dev/null 2>&1 || true
a2enmod --quiet mpm_event >/dev/null 2>&1 || true

# Ship our vhosts, disable the stock default so ours is genuinely first.
cp "${REPO}/apache/000-siwang-main.conf"   /etc/apache2/sites-available/
cp "${REPO}/apache/010-siwang-dev.conf"    /etc/apache2/sites-available/
cp "${REPO}/apache/020-siwang-backup.conf" /etc/apache2/sites-available/
cp "${REPO}/apache/hardening.conf"         /etc/apache2/conf-available/siwang-hardening.conf

a2dissite --quiet 000-default default-ssl >/dev/null 2>&1 || true
a2ensite  --quiet 000-siwang-main 010-siwang-dev 020-siwang-backup >/dev/null
a2enconf  --quiet siwang-hardening >/dev/null

# ---------------------------------------------------------------------------
# 3. PHP-FPM pool
# ---------------------------------------------------------------------------
echo "==> Installing PHP-FPM pool for the dev vhost"
cp "${REPO}/apache/php-fpm-siwang-dev.conf" "${FPM_POOL_DST}"

install -d -o www-data -g www-data -m 0700 "${SESSION_DIR}"

# ---------------------------------------------------------------------------
# 4. Docroots
# ---------------------------------------------------------------------------
echo "==> Deploying document roots"
install -d "${WWW_MAIN}" "${WWW_DEV}" "${WWW_BACKUP}"

# Static content is world-readable but NOT owned by www-data: the web user must
# not be able to modify the sites it serves.
cp -rT "${REPO}/site/main"   "${WWW_MAIN}"
cp -rT "${REPO}/site/backup" "${WWW_BACKUP}"
cp -rT "${REPO}/site/dev"    "${WWW_DEV}"

# Drop the lab's .gitkeep breadcrumbs from the deployed tree.
find "${WWW_MAIN}" "${WWW_DEV}" "${WWW_BACKUP}" -name '.gitkeep' -delete

# ---------------------------------------------------------------------------
# 5. Database
# ---------------------------------------------------------------------------
echo "==> Provisioning database"
systemctl enable --now mariadb >/dev/null 2>&1 || systemctl start mariadb
DB_PASS="$(tr -dc 'A-Za-z0-9' < /dev/urandom | head -c 28)"
bash "${REPO}/db/setup.sh" "${DB_PASS}"

# ---------------------------------------------------------------------------
# 6. Wire the DB password into the app config
# ---------------------------------------------------------------------------
echo "==> Writing application configuration"
CONFIG="${WWW_DEV}/includes/config.php"
# Use a non-/ delimiter so a slash in the password would not break sed; the
# password is alphanumeric anyway.
sed -i "s|__DB_PASSWORD__|${DB_PASS}|" "${CONFIG}"

if grep -q '__DB_PASSWORD__' "${CONFIG}"; then
    echo "error: DB password placeholder was not substituted." >&2
    exit 1
fi

# ---------------------------------------------------------------------------
# 7. Ownership and permissions
# ---------------------------------------------------------------------------
echo "==> Setting permissions (delegating to lockdown.sh)"
bash "${REPO}/install/lockdown.sh"

# ---------------------------------------------------------------------------
# 8. Restart services
# ---------------------------------------------------------------------------
echo "==> Restarting services"
systemctl restart "php${PHP_VER}-fpm"
apache2ctl configtest
systemctl restart apache2

# ---------------------------------------------------------------------------
# 9. Smoke test
# ---------------------------------------------------------------------------
echo "==> Smoke test"
sleep 1
BROCHURE_BYTES=$(curl -s -H 'Host: nope.siwang.pineapple' http://127.0.0.1/ | wc -c)
DEV_HAS_LOGIN=$(curl -s -H 'Host: dev.siwang.pineapple' http://127.0.0.1/login.php | grep -c 'Sign in' || true)

echo "    brochure fallback size: ${BROCHURE_BYTES} bytes"
echo "    dev login page present: $([[ ${DEV_HAS_LOGIN} -gt 0 ]] && echo yes || echo NO)"

if [[ ${DEV_HAS_LOGIN} -eq 0 ]]; then
    echo "warning: dev login page did not render -- check /var/log/php-siwang-dev.log" >&2
fi

echo
echo "############################################################"
echo "#  Done."
echo "#"
echo "#  Public:  http://siwang.duckdns.org/   (also the fallback vhost)"
echo "#  Dev:     http://dev.siwang.pineapple/ (add to /etc/hosts)"
echo "#  Backup:  http://backup.siwang.pineapple/ (stub, privesc hook)"
echo "#"
echo "#  DB app password was generated and written to config.php."
echo "#  Run install/verify.sh to check all three stages."
echo "############################################################"
