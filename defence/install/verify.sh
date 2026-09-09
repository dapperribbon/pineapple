#!/usr/bin/env bash
#
# Siwang CTF lab -- self-test for Stages 1-3.
#
#   sudo ./verify.sh            # run against 127.0.0.1 using Host headers
#
# Confirms the intended path works and the main unintended paths are closed.
# Run it on the box after install.sh. Every check prints PASS or FAIL; the
# script exits non-zero if anything failed.

set -uo pipefail

DEV="dev.siwang.pineapple"
BROCHURE_HOST="siwang.duckdns.org"
BASE="http://127.0.0.1"
PASS=0
FAIL=0

ok()   { echo "  PASS  $1"; PASS=$((PASS+1)); }
bad()  { echo "  FAIL  $1"; FAIL=$((FAIL+1)); }

# hget HOST PATH   -> body ; hcode HOST PATH -> status code
hget()  { curl -s  -H "Host: $1" "${BASE}$2"; }
hcode() { curl -s -o /dev/null -w '%{http_code}' -H "Host: $1" "${BASE}$2"; }

echo "== Stage 1: vhosts and fallback =="

apache2ctl configtest >/dev/null 2>&1 && ok "apache configtest" || bad "apache configtest"

s1=$(hget nope1.siwang.pineapple / | wc -c)
s2=$(hget nope2-longer-name.siwang.pineapple / | wc -c)
[[ "$s1" == "$s2" && "$s1" -gt 0 ]] \
    && ok "unmatched Host -> stable-size brochure ($s1 bytes)" \
    || bad "brochure fallback not byte-stable ($s1 vs $s2)"

hget "$BROCHURE_HOST" / | grep -q 'dev.siwang.pineapple' \
    && ok "brochure leaks the dev hostname" \
    || bad "brochure breadcrumb missing"

hget "$DEV" /login.php | grep -q 'Sign in' \
    && ok "dev vhost serves the login page" \
    || bad "dev login page missing"

# PHP must NOT execute on the brochure vhost.
echo '<?php echo 1234; ?>' > /var/www/main/__probe.php 2>/dev/null || true
body=$(hget "$BROCHURE_HOST" /__probe.php)
code=$(hcode "$BROCHURE_HOST" /__probe.php)
echo "$body" | grep -q '1234' && bad "PHP executed on brochure vhost!" || ok "brochure vhost does not execute PHP (HTTP $code)"
rm -f /var/www/main/__probe.php

echo "== Stage 2: escalation and rabbit holes =="

# No local PHP-side asserts here; those are exercised by exploit.py. Check the
# gate: a plain GET of upload.php (no session) must be a redirect or 403/40x,
# never a 200 upload form.
ucode=$(hcode "$DEV" /upload.php)
[[ "$ucode" == "302" || "$ucode" == "403" ]] \
    && ok "upload.php gated for anonymous (HTTP $ucode)" \
    || bad "upload.php returned $ucode for anonymous user"

# tools.php reachability check requires a session, so just assert the file is
# not served as source (would mean FPM is not wired).
hget "$DEV" /tools.php | grep -q '<?php' \
    && bad "tools.php served as source -- FPM handler not applied" \
    || ok "PHP is handled (tools.php not served as source)"

# ping capability -- the rabbit hole must actually work as www-data.
if command -v getcap >/dev/null 2>&1; then
    getcap /usr/bin/ping | grep -q 'cap_net_raw' \
        && ok "ping has cap_net_raw (diagnostics tool will work)" \
        || bad "ping lacks cap_net_raw -- diagnostics rabbit hole will look broken"
fi

echo "== Stage 3: image execution and scope =="

# GD must be present or the upload's image-decode check dies.
php -m 2>/dev/null | grep -qi '^gd$' \
    && ok "php-gd present (image upload check will run)" \
    || bad "php-gd missing -- uploads will fail the decode step"

# A genuine 1x1 GIF with a "<?=" payload appended: this is exactly the Stage 3
# payload. Drop it in /uploads (as www-data would) and confirm it EXECUTES.
#
# IMPORTANT: the payload builds the marker by CONCATENATION -- '<?= "AB"."CD" ?>'
# -- so the contiguous marker string exists ONLY in executed output, never in
# the raw file source. Grepping for a marker that also appears literally in the
# file would match a statically-served file too (a false positive), which is
# exactly the trap to avoid here.
GIF89A_1PX="\x47\x49\x46\x38\x39\x61\x01\x00\x01\x00\x80\x00\x00\x00\x00\x00\xff\xff\xff\x21\xf9\x04\x01\x00\x00\x00\x00\x2c\x00\x00\x00\x00\x01\x00\x01\x00\x00\x02\x02\x44\x01\x00\x3b"
PROBE="/var/www/dev/uploads/__verify_$$.gif"
printf "${GIF89A_1PX}\n<?= 'RCE' . 'PROOF' . $$; ?>" > "$PROBE"
chown www-data:www-data "$PROBE"; chmod 0644 "$PROBE"
resp=$(hget "$DEV" "/uploads/$(basename "$PROBE")")
echo "$resp" | grep -q "RCEPROOF$$" \
    && ok "image (.gif + <?=) executes inside /uploads (Stage 3 landing zone live)" \
    || bad "image did NOT execute in /uploads -- check the vhost handler + FPM security.limit_extensions"

# SCOPE: the same file at the docroot ROOT must NOT execute -- image execution
# is confined to the uploads directory. Same concatenation trick, so a
# statically-served file cannot produce the contiguous marker.
SCOPE="/var/www/dev/__verify_scope_$$.gif"
printf "${GIF89A_1PX}\n<?= 'SCOPE' . 'LEAK' . $$; ?>" > "$SCOPE"
chown www-data:www-data "$SCOPE"; chmod 0644 "$SCOPE"
resp=$(hget "$DEV" "/$(basename "$SCOPE")")
echo "$resp" | grep -q "SCOPELEAK$$" \
    && bad "image executed OUTSIDE /uploads -- handler is not scoped!" \
    || ok "images do not execute outside /uploads (handler correctly scoped)"
rm -f "$PROBE" "$SCOPE"

# The app's own pages must still run (global .php handler intact).
hget "$DEV" /login.php | grep -q 'Sign in' \
    && ok "app .php pages still execute (login renders)" \
    || bad "app pages not executing -- global .php handler / FPM issue"

echo "== Unintended-path spot checks =="

# www-data must not be able to write the brochure or the app code.
sudo -u www-data test -w /var/www/main/index.html \
    && bad "www-data can write the brochure!" \
    || ok "www-data cannot write the brochure"
sudo -u www-data test -w /var/www/dev/upload.php \
    && bad "www-data can write app code!" \
    || ok "www-data cannot overwrite app code"
sudo -u www-data test -w /var/www/dev/uploads \
    && ok "www-data can write the uploads dir (required)" \
    || bad "www-data cannot write uploads -- Stage 3 will fail"

# includes/ and partials/ denied over HTTP.
for p in /includes/config.php /includes/auth.php /partials/home.php; do
    c=$(hcode "$DEV" "$p")
    [[ "$c" == "403" || "$c" == "404" ]] \
        && ok "denied over HTTP: $p (HTTP $c)" \
        || bad "$p returned $c -- should be denied"
done

# backup-old dead end.
c=$(hcode "$DEV" /backup-old/)
[[ "$c" == "403" ]] && ok "/backup-old/ is a 403 dead end" || bad "/backup-old/ returned $c"

# 3306 must not be listening on anything but loopback.
if command -v ss >/dev/null 2>&1; then
    ss -ltn | awk '{print $4}' | grep -qE '(0\.0\.0\.0|\*|\[::\]):3306' \
        && bad "MariaDB is listening on a public interface!" \
        || ok "MariaDB is not publicly bound"
fi

echo
echo "==============================="
echo "  PASS: $PASS   FAIL: $FAIL"
echo "==============================="
[[ $FAIL -eq 0 ]] || exit 1
