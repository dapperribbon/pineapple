#!/usr/bin/env bash
#
# Siwang lab -- reinitialise the database on an installed box.
#
#   sudo ./reinit.sh
#
# Use this when the app shows "Service temporarily unavailable." and MariaDB has
# no siwang_dev database (i.e. the DB step of the original install did not
# complete). It DROPS and rebuilds siwang_dev from schema.sql + the seed files.
#
# The key trick: it reuses the DB password already baked into the deployed
# config.php, and provisions the siwang_app user with THAT password -- so the
# database and the app agree afterwards and config.php needs no editing. If
# config.php still holds the un-substituted placeholder (install aborted early),
# it generates a fresh password and writes it into config.php instead.
#
# Safe to re-run.

set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"     # the db/ dir
CONFIG="/var/www/dev/includes/config.php"
DB_NAME="siwang_dev"

if [[ $EUID -ne 0 ]]; then
    echo "error: run with sudo (MariaDB root here authenticates via the unix socket)." >&2
    exit 1
fi

command -v mysql >/dev/null 2>&1 || { echo "error: mysql client not found." >&2; exit 1; }

# --- MariaDB reachable as root over the socket? ----------------------------
if ! mysql -e "SELECT 1" >/dev/null 2>&1; then
    echo "error: cannot connect to MariaDB as root over the unix socket." >&2
    echo "       Is it running?   systemctl status mariadb" >&2
    echo "       If root has a password set instead of socket auth, run:" >&2
    echo "         sudo mysql -e \"ALTER USER 'root'@'localhost' IDENTIFIED VIA unix_socket; FLUSH PRIVILEGES;\"" >&2
    exit 1
fi

# --- Work out which password to use ----------------------------------------
if [[ ! -f "${CONFIG}" ]]; then
    echo "error: ${CONFIG} not found. Deploy the app first (install.sh)." >&2
    exit 1
fi

DB_PASS="$(sed -n "s/.*const DB_PASS *= *'\([^']*\)'.*/\1/p" "${CONFIG}")"
WRITE_BACK=0

if [[ -z "${DB_PASS}" || "${DB_PASS}" == "__DB_PASSWORD__" ]]; then
    echo "==> config.php has no real password yet; generating a new one"
    DB_PASS="$(tr -dc 'A-Za-z0-9' < /dev/urandom | head -c 28)"
    WRITE_BACK=1
else
    echo "==> Reusing the DB password already in config.php"
fi

# --- Rebuild the database (setup.sh drops and recreates) -------------------
echo "==> Rebuilding ${DB_NAME}"
bash "${HERE}/setup.sh" "${DB_PASS}"

# --- Keep config.php in sync if we minted a new password -------------------
if [[ ${WRITE_BACK} -eq 1 ]]; then
    echo "==> Writing the new password into config.php"
    sed -i "s|__DB_PASSWORD__|${DB_PASS}|" "${CONFIG}"
    if grep -q '__DB_PASSWORD__' "${CONFIG}"; then
        echo "error: failed to substitute the password into config.php." >&2
        exit 1
    fi
    # config.php must stay app-readable only.
    chown root:www-data "${CONFIG}" 2>/dev/null || true
    chmod 0640 "${CONFIG}" 2>/dev/null || true
fi

# --- Prove the app's own credentials work ----------------------------------
echo "==> Verifying the app can connect with config.php's credentials"
if mysql -h 127.0.0.1 -u siwang_app -p"${DB_PASS}" -e "SELECT COUNT(*) FROM users" "${DB_NAME}" >/dev/null 2>&1; then
    echo "    OK -- siwang_app can read ${DB_NAME}"
else
    echo "error: siwang_app still cannot connect. Check ${CONFIG} DB_PASS vs the DB user." >&2
    exit 1
fi

echo
echo "Database reinitialised. Reload http://dev.siwang.pineapple/register.php"
echo "(no service restart needed -- PHP opens a new DB connection per request)."
