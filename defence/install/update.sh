#!/usr/bin/env bash
#
# Siwang CTF lab -- in-place corrective update for an ALREADY-installed box.
#
#   sudo ./update.sh
#   sudo CERT_DIR=/etc/letsencrypt/live/siwang.duckdns.org-0001 ./update.sh
#
# Run this on a box where install.sh has already succeeded once, to bring it up
# to date with changes made since. Unlike install.sh it does NOT touch apt and
# does NOT rebuild the database from scratch -- it is deliberately
# non-destructive:
#
#   * live config.php DB password is preserved (extracted and re-applied)
#   * student-registered accounts and uploaded files are left alone
#
# What it applies:
#   1. TLS: the new :443 vhost for siwang.duckdns.org + the direct-IP / HTTP
#      -> HTTPS redirects. Enables mod_ssl.
#   2. Latest application code (e.g. the upload.php DB-insert hardening).
#   3. The mika/emma account rename, applied in place with UPDATE so ids and
#      password hashes are preserved and document ownership stays valid.
#   4. Re-runs lockdown.sh (permissions + firewall, now including 443).
#
# Safe to run more than once.

set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"   # the defence/ dir
PHP_VER="8.3"
WWW_MAIN="/var/www/main"
WWW_DEV="/var/www/dev"
WWW_BACKUP="/var/www/backup"
CONFIG="${WWW_DEV}/includes/config.php"
MAIN_CONF="/etc/apache2/sites-available/000-siwang-main.conf"
CERT_DIR="${CERT_DIR:-/etc/letsencrypt/live/siwang.duckdns.org}"

if [[ $EUID -ne 0 ]]; then
    echo "error: run with sudo." >&2
    exit 1
fi

if [[ ! -d "${WWW_DEV}" || ! -f "${CONFIG}" ]]; then
    echo "error: ${CONFIG} not found -- this box does not look installed." >&2
    echo "       Run install/install.sh for a first-time build instead."    >&2
    exit 1
fi

echo "############################################################"
echo "#  Siwang lab in-place update"
echo "############################################################"

# ---------------------------------------------------------------------------
# 1. Preserve the live DB password before we redeploy the docroot over it.
# ---------------------------------------------------------------------------
echo "==> Reading the live database password from config.php"
DB_PASS="$(sed -n "s/.*const DB_PASS *= *'\([^']*\)'.*/\1/p" "${CONFIG}")"
if [[ -z "${DB_PASS}" || "${DB_PASS}" == "__DB_PASSWORD__" ]]; then
    echo "error: could not read a real DB password from ${CONFIG}." >&2
    echo "       Refusing to redeploy, as it would break the DB connection." >&2
    exit 1
fi
echo "    got it (kept out of the log)"

# ---------------------------------------------------------------------------
# 1b. Ensure the GD extension is present.
#
# The Stage 3 upload backend validates images with imagecreatefrom*(), which
# lives in php-gd. It is the one package this in-place update needs, so we make
# an exception to the "no apt" rule and install just it if it is missing.
# ---------------------------------------------------------------------------
if php -m 2>/dev/null | grep -qi '^gd$'; then
    echo "==> GD extension already present"
else
    echo "==> Installing php${PHP_VER}-gd (required by the image upload check)"
    DEBIAN_FRONTEND=noninteractive apt-get install -y -qq "php${PHP_VER}-gd" >/dev/null \
        || echo "    warning: could not install php${PHP_VER}-gd -- uploads will fail until it is present" >&2
fi

# ---------------------------------------------------------------------------
# 2. Apache: modules, vhosts, TLS cert wiring.
# ---------------------------------------------------------------------------
echo "==> Updating Apache modules and vhosts"
a2enmod proxy proxy_fcgi setenvif headers rewrite ssl >/dev/null 2>&1 || true

cp "${REPO}/apache/000-siwang-main.conf"   /etc/apache2/sites-available/
cp "${REPO}/apache/010-siwang-dev.conf"    /etc/apache2/sites-available/
cp "${REPO}/apache/020-siwang-backup.conf" /etc/apache2/sites-available/
cp "${REPO}/apache/hardening.conf"         /etc/apache2/conf-available/siwang-hardening.conf
cp "${REPO}/apache/php-fpm-siwang-dev.conf" "/etc/php/${PHP_VER}/fpm/pool.d/siwang-dev.conf"

a2ensite --quiet 000-siwang-main 010-siwang-dev 020-siwang-backup >/dev/null 2>&1 || true
a2enconf --quiet siwang-hardening >/dev/null 2>&1 || true

if [[ "${CERT_DIR}" != "/etc/letsencrypt/live/siwang.duckdns.org" ]]; then
    sed -i "s#/etc/letsencrypt/live/siwang.duckdns.org#${CERT_DIR}#g" "${MAIN_CONF}"
fi

if [[ -f "${CERT_DIR}/fullchain.pem" && -f "${CERT_DIR}/privkey.pem" ]]; then
    echo "    TLS certificate found at ${CERT_DIR} -- HTTPS enabled"
else
    echo "    WARNING: no certificate at ${CERT_DIR} -- the :443 vhost will not"   >&2
    echo "             start and the Apache restart below will fail. Place the"    >&2
    echo "             cert there (or pass CERT_DIR=...), or comment out the"       >&2
    echo "             <VirtualHost *:443> block in ${MAIN_CONF}." >&2
fi

# ---------------------------------------------------------------------------
# 3. Redeploy the document roots, preserving the DB password in config.php.
# ---------------------------------------------------------------------------
echo "==> Redeploying site content (uploads and config password preserved)"
# cp does not delete, so existing student uploads under dev/uploads survive.
cp -rT "${REPO}/site/main"   "${WWW_MAIN}"
cp -rT "${REPO}/site/backup" "${WWW_BACKUP}"
cp -rT "${REPO}/site/dev"    "${WWW_DEV}"
find "${WWW_MAIN}" "${WWW_DEV}" "${WWW_BACKUP}" -name '.gitkeep' -delete

# The copy above reset config.php to the committed placeholder; put the live
# password back.
sed -i "s|__DB_PASSWORD__|${DB_PASS}|" "${CONFIG}"
if grep -q '__DB_PASSWORD__' "${CONFIG}"; then
    echo "error: failed to restore the DB password into config.php." >&2
    exit 1
fi

# ---------------------------------------------------------------------------
# 4. Reconcile the seeded account names IN PLACE.
#
#    UPDATE, not re-seed: this preserves each account's id and password hash,
#    so the seeded documents' owner_id foreign keys stay valid and any cookie a
#    student already forged against an id still resolves. No-op if the box was
#    already seeded with the new names.
# ---------------------------------------------------------------------------
echo "==> Reconciling seeded account names (mchoo->mika, jtan->emma)"
if command -v mysql >/dev/null 2>&1; then
    mysql <<'SQL'
UPDATE siwang_dev.users
   SET username = 'mika',  email = 'mika@siwang-trading.example'
 WHERE username = 'mchoo';
UPDATE siwang_dev.users
   SET username = 'emma',  email = 'emma@siwang-trading.example'
 WHERE username = 'jtan';
SQL

    # If the document table never got seeded (e.g. the first install seeded
    # users AFTER the join ran), populate it now. Guarded so a populated table
    # is not duplicated.
    DOCS=$(mysql -N -B -e "SELECT COUNT(*) FROM siwang_dev.documents" 2>/dev/null || echo 0)
    if [[ "${DOCS}" == "0" ]]; then
        echo "    documents table empty -- seeding sample documents"
        mysql < "${REPO}/db/seed.sql" 2>/dev/null || \
            echo "    note: seed.sql did not load cleanly; check the account names" >&2
    else
        echo "    documents already present (${DOCS}) -- leaving them"
    fi

    echo "    accounts now:"
    mysql -N -B -e "SELECT CONCAT('      ', username, ' (', role, ')') FROM siwang_dev.users ORDER BY id"
else
    echo "    warning: mysql client not found -- skipped the account rename." >&2
fi

# ---------------------------------------------------------------------------
# 5. Permissions + firewall.
# ---------------------------------------------------------------------------
echo "==> Re-running lockdown (permissions, sweep, firewall incl. 443)"
bash "${REPO}/install/lockdown.sh"

# ---------------------------------------------------------------------------
# 6. Restart and smoke test.
# ---------------------------------------------------------------------------
echo "==> Restarting services"
systemctl restart "php${PHP_VER}-fpm"
apache2ctl configtest
systemctl restart apache2

echo "==> Smoke test"
sleep 1
IP_REDIR=$(curl -s -o /dev/null -w '%{http_code}' -H 'Host: 203.0.113.9' http://127.0.0.1/ || true)
FALLBACK=$(curl -s -H 'Host: nope.siwang.pineapple' http://127.0.0.1/ | wc -c)
echo "    direct-IP Host -> HTTP ${IP_REDIR} (expect 301)"
echo "    unmatched-host fallback size: ${FALLBACK} bytes (ffuf path intact)"

echo
echo "############################################################"
echo "#  Update complete."
echo "#    - HTTPS vhost + direct-IP/HTTP->HTTPS redirect deployed"
echo "#    - latest app code deployed (DB password preserved)"
echo "#    - accounts renamed to mika / emma in place"
echo "#  Run install/verify.sh to re-check all three stages."
echo "############################################################"
