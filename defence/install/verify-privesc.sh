#!/usr/bin/env bash
#
# Siwang CTF lab -- Stage 4-8 verification, run from the HOST after
# `docker compose up -d --build`. (The Stage 1-3 checks live in verify.sh and
# run inside the siwang container; these span two containers + the host, so they
# cannot.)
#
#   sudo ./verify-privesc.sh
#
set -uo pipefail

PASS=0; FAIL=0
ok()  { echo "  PASS  $1"; PASS=$((PASS+1)); }
bad() { echo "  FAIL  $1"; FAIL=$((FAIL+1)); }

DOCKER="docker"
command -v docker >/dev/null || { echo "docker not found" >&2; exit 1; }
[[ $EUID -eq 0 ]] || DOCKER="sudo docker"

APP=siwang-lab
MAIL=siwang-mail

echo "== Stage 4: DB loot surface =="
roles="$($DOCKER exec "$APP" mysql siwang_dev -N -e \
    "SELECT username,role FROM users ORDER BY id" 2>/dev/null)"
echo "$roles" | grep -q '^chrysanta	user$' \
    && ok "chrysanta present and non-admin" \
    || bad "chrysanta missing or not role=user"
echo "$roles" | grep -q '^mika	admin$' \
    && ok "mika still the (uncrackable) admin" || bad "mika/admin row changed"

echo "== Stage 5: exactly one crackable password =="
H="$($DOCKER exec "$APP" mysql siwang_dev -N -e \
    "SELECT password_hash FROM users WHERE username='chrysanta'" 2>/dev/null)"
$DOCKER exec "$APP" php -r "exit(password_verify('dylan', \$argv[1]) ? 0 : 1);" "$H" 2>/dev/null \
    && ok "chrysanta's hash verifies as 'dylan'" \
    || bad "chrysanta's hash is not 'dylan'"

echo "== Stage 6: internal mail host =="
if ss -ltnH 2>/dev/null | awk '{print $4}' | grep -qE ':(25|143|465|587|993)$'; then
    bad "a mail port is published on the host (must be internal-only)"
else
    ok "no mail port published on the host"
fi

needle="$($DOCKER exec -i "$APP" python3 - <<'PY' 2>/dev/null
import imaplib
try:
    M=imaplib.IMAP4("mail",143)
    M.login("chrysanta@siwang-trading.example","dylan")
    M.select("INBOX",readonly=True)
    _,d=M.search(None,"BODY","BenMyG0AT")
    n=d[0].split()[0]
    _,d=M.fetch(n,"(BODY.PEEK[TEXT])")
    print("OK" if b"BenMyG0AT" in d[0][1] else "NOFIND")
except Exception as e:
    print("ERR",e)
PY
)"
[[ "$needle" == OK ]] \
    && ok "pivot: IMAP login as chrysanta/dylan finds the reset email" \
    || bad "pivot/IMAP check failed ($needle)"

# wrong password must be rejected
rej="$($DOCKER exec -i "$APP" python3 - <<'PY' 2>/dev/null
import imaplib
try:
    imaplib.IMAP4("mail",143).login("chrysanta@siwang-trading.example","wrong"); print("BAD")
except Exception: print("REJECTED")
PY
)"
[[ "$rej" == REJECTED ]] && ok "mail rejects the wrong password" || bad "mail accepted a wrong password"

echo "== Hardening =="
$DOCKER inspect -f '{{.HostConfig.Privileged}}' "$APP" 2>/dev/null | grep -q false \
    && ok "siwang not privileged" || bad "siwang privileged!"
$DOCKER inspect -f '{{.HostConfig.ReadonlyRootfs}}' "$MAIL" 2>/dev/null | grep -q true \
    && ok "mail rootfs read-only" || bad "mail rootfs not read-only"
$DOCKER inspect -f '{{range .HostConfig.SecurityOpt}}{{println .}}{{end}}' "$MAIL" 2>/dev/null \
    | grep -q 'no-new-privileges:true' \
    && ok "mail no-new-privileges" || bad "mail missing no-new-privileges"
$DOCKER inspect -f '{{json .HostConfig.CapDrop}}' "$APP" 2>/dev/null | grep -qi 'ALL' \
    && ok "siwang drops ALL caps (then adds back a minimal set)" \
    || bad "siwang does not cap_drop ALL"

echo "== Stage 7-8: host material (informational; needs privesc-host.sh) =="
if id chrysanta >/dev/null 2>&1; then
    ok "host user 'chrysanta' exists"
    [[ -u /usr/local/bin/opsbackup ]] \
        && ok "SUID opsbackup present" || bad "opsbackup missing or not SUID"
else
    echo "  ....  host not provisioned yet (run: sudo ./privesc-host.sh --confirm)"
fi

echo
echo "==============================="
echo "  PASS: ${PASS}   FAIL: ${FAIL}"
echo "==============================="
[[ $FAIL -eq 0 ]]
