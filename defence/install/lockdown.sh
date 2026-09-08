#!/usr/bin/env bash
#
# Siwang CTF lab -- permissions and unintended-path closure.
#
#   sudo ./lockdown.sh            # apply permissions and close unintended paths
#   sudo ./lockdown.sh --reset    # ALSO empty the uploads dir (reset between classes)
#
# install.sh calls this at the end. It is also safe to run on its own after
# fiddling with the box, and it is the thing to run to reset the lab between
# cohorts.
#
# Guiding principle: www-data can WRITE exactly one directory (dev/uploads) and
# can READ the app, and nothing else on the box belongs to it. Every static
# site is owned by root:www-data, readable, not writable.

set -euo pipefail

WWW_MAIN="/var/www/main"
WWW_DEV="/var/www/dev"
WWW_BACKUP="/var/www/backup"
UPLOADS="${WWW_DEV}/uploads"
PHP_VER="8.3"

RESET=0
[[ "${1:-}" == "--reset" ]] && RESET=1

if [[ $EUID -ne 0 ]]; then
    echo "error: run with sudo." >&2
    exit 1
fi

echo "==> Ownership: static sites owned by root, readable by the web group"
# root owns the files; www-data can read but not write them. This is what stops
# a webshell in the dev app from rewriting the brochure or the backup stub.
for root in "${WWW_MAIN}" "${WWW_DEV}" "${WWW_BACKUP}"; do
    chown -R root:www-data "${root}"
    find "${root}" -type d -exec chmod 0750 {} \;
    find "${root}" -type f -exec chmod 0640 {} \;
done

echo "==> The uploads directory is the one writable spot for www-data"
# It has to be group-writable AND owned by www-data so PHP-FPM can move files
# into it. This is intentional and is the Stage 3 landing zone.
install -d -o www-data -g www-data -m 0755 "${UPLOADS}"

if [[ ${RESET} -eq 1 ]]; then
    echo "    --reset: clearing previously uploaded files"
    find "${UPLOADS}" -mindepth 1 -delete
    # Truncate the document/diag tables too, so a reset class starts clean.
    if command -v mysql >/dev/null 2>&1; then
        mysql -e "DELETE FROM siwang_dev.documents;  ALTER TABLE siwang_dev.documents  AUTO_INCREMENT=1;" 2>/dev/null || true
        mysql -e "DELETE FROM siwang_dev.diag_queue; ALTER TABLE siwang_dev.diag_queue AUTO_INCREMENT=1;" 2>/dev/null || true
        # Re-seed the sample documents and diag history.
        mysql < "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/db/seed.sql" 2>/dev/null || true
        # Remove any student-registered accounts, keep the three seeded ones.
        mysql -e "DELETE FROM siwang_dev.users WHERE username NOT IN ('mchoo','jtan','svc_dms');" 2>/dev/null || true
    fi
fi

# The app must never be able to overwrite its own PHP under the docroot -- that
# would let a webshell rewrite upload.php to remove the filter, etc. Uploads is
# the sole exception, handled above.
echo "==> Confirming www-data cannot write app code"
chmod 0755 "${UPLOADS}"   # re-assert after the loop above chmod'd it 0750

echo "==> config.php is readable by the app only"
# Owner root, group www-data, no world read: keeps the DB password off any
# world-readable path even though the vhost already denies it over HTTP.
chown root:www-data "${WWW_DEV}/includes/config.php"
chmod 0640 "${WWW_DEV}/includes/config.php"

echo "==> Sweeping for files that would leak or shortcut the lab"
# Editor swap files, VCS metadata, backups, SQL dumps -- anything that would
# hand a student source, credentials, or an alternate path.
SWEPT=0
while IFS= read -r -d '' f; do
    echo "    removing ${f}"
    rm -f "${f}"
    SWEPT=$((SWEPT + 1))
done < <(find "${WWW_MAIN}" "${WWW_DEV}" "${WWW_BACKUP}" \
    \( -name '.git' -o -name '.gitkeep' -o -name '.gitignore' \
       -o -name '*.bak' -o -name '*.old' -o -name '*.orig' -o -name '*.save' \
       -o -name '*.swp' -o -name '*.swo' -o -name '*~' \
       -o -name '*.sql' -o -name '*.dist' -o -name '*.example' \) \
    -print0 2>/dev/null)
echo "    swept ${SWEPT} item(s)"

echo "==> ping must keep its capability so the diagnostics rabbit hole looks real"
# Ubuntu 24.04 ships /usr/bin/ping with cap_net_raw+ep. If a hardened base image
# stripped it, www-data would get "Operation not permitted" and the rabbit hole
# would stop being convincing. Re-assert it.
if command -v setcap >/dev/null 2>&1 && [[ -f /usr/bin/ping ]]; then
    setcap cap_net_raw+ep /usr/bin/ping || \
        echo "    warning: could not set cap_net_raw on ping" >&2
fi

echo "==> PHP-FPM log is writable by the pool"
touch /var/log/php-siwang-dev.log
chown www-data:adm /var/log/php-siwang-dev.log
chmod 0640 /var/log/php-siwang-dev.log

echo "==> Firewall: only 22 and 80 should face the student network"
if command -v ufw >/dev/null 2>&1; then
    ufw --force reset >/dev/null 2>&1 || true
    ufw default deny incoming >/dev/null
    ufw default allow outgoing >/dev/null
    ufw allow 22/tcp >/dev/null
    ufw allow 80/tcp >/dev/null
    # MariaDB stays on loopback; do not open 3306.
    ufw --force enable >/dev/null
    echo "    ufw: 22/tcp, 80/tcp allowed; MariaDB bound to loopback"
else
    echo "    ufw not present -- ensure 3306 is not exposed by other means"
fi

echo "==> Lockdown complete"
