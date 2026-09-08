#!/usr/bin/env bash
#
# Siwang lab -- database provisioning.
#
#   sudo ./setup.sh [app-password]
#
# Idempotent: drops and rebuilds siwang_dev from scratch every run, so it is
# safe to re-run while iterating on the box or to reset the lab between classes.
#
# If no password is supplied one is generated and printed. install.sh calls this
# with a password it generated itself so it can substitute the same value into
# the application's config.php.

set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

DB_NAME="siwang_dev"
DB_USER="siwang_app"
DB_HOST="127.0.0.1"

if [[ $EUID -ne 0 ]]; then
    echo "error: must run as root (MySQL root auth here is via the unix socket)." >&2
    exit 1
fi

APP_PASS="${1:-}"
if [[ -z "$APP_PASS" ]]; then
    # Alphanumeric only: this value gets embedded in a PHP single-quoted string
    # and passed through a shell argument, and quoting bugs in a lab installer
    # are not worth the entropy.
    APP_PASS="$(tr -dc 'A-Za-z0-9' < /dev/urandom | head -c 28)"
fi

command -v mysql >/dev/null 2>&1 || { echo "error: mysql client not found." >&2; exit 1; }
command -v php   >/dev/null 2>&1 || { echo "error: php cli not found."      >&2; exit 1; }

echo "==> Building schema"
mysql < "${HERE}/schema.sql"

echo "==> Creating application database user"
# Least privilege on purpose. Three things are deliberately NOT granted:
#
#   FILE       - a global privilege, so `GRANT ... ON siwang_dev.*` could never
#                confer it anyway, but it is worth stating: without FILE there
#                is no SELECT ... INTO OUTFILE, which would otherwise be an
#                alternate route to writing a webshell and would bypass the
#                entire Stage 3 upload puzzle.
#   DROP/ALTER - nothing in the app performs DDL.
#   DELETE     - nothing in the app deletes rows. Withholding it means even a
#                hypothetical injection could not destroy the lab's state.
#
# The account is bound to 127.0.0.1 rather than '%' so it is not reachable from
# off-box even if MySQL is ever mistakenly bound to a public interface.
mysql <<SQL
DROP USER IF EXISTS '${DB_USER}'@'${DB_HOST}';
CREATE USER '${DB_USER}'@'${DB_HOST}' IDENTIFIED BY '${APP_PASS}';
GRANT SELECT, INSERT, UPDATE ON ${DB_NAME}.* TO '${DB_USER}'@'${DB_HOST}';
FLUSH PRIVILEGES;
SQL

echo "==> Seeding accounts (bcrypt hashes generated now, not hardcoded)"
php "${HERE}/seed_users.php" "${DB_USER}" "${APP_PASS}" "${DB_HOST}"

echo "==> Seeding documents and diagnostics history"
mysql < "${HERE}/seed.sql"

echo "==> Verifying"
mysql -N -B -e "
    SELECT CONCAT('    users:      ', COUNT(*)) FROM ${DB_NAME}.users;
    SELECT CONCAT('    documents:  ', COUNT(*)) FROM ${DB_NAME}.documents;
    SELECT CONCAT('    diag_queue: ', COUNT(*)) FROM ${DB_NAME}.diag_queue;
"

# Confirm the app user really can authenticate with the password we just set --
# catching this here is much better than discovering it as a white page later.
if ! mysql -h "${DB_HOST}" -u "${DB_USER}" -p"${APP_PASS}" -e "SELECT 1" "${DB_NAME}" >/dev/null 2>&1; then
    echo "error: application DB user cannot authenticate. Aborting." >&2
    exit 1
fi
echo "    app user login: OK"

echo
echo "Database ready."
echo "  DB_USER=${DB_USER}"
echo "  DB_PASS=${APP_PASS}"
echo
echo "If you ran this directly rather than via install/install.sh, put that"
echo "password into /var/www/dev/includes/config.php (the DB_PASS constant)."
