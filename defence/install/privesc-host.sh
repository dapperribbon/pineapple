#!/usr/bin/env bash
#
# Siwang CTF lab -- Stage 7-8 HOST provisioning.
#
# This is the ONLY part of the lab that touches the real host rather than a
# container. It creates:
#
#   * a local shell user `chrysanta` (password: BenMyG0AT) that a student
#     reaches over SSH once they have recovered the password from chrysanta's
#     mailbox on the smtp container (Stage 6);
#   * an sshd drop-in permitting password login for that one user;
#   * a SUID-root helper (/usr/local/bin/opsbackup) that invokes a command by
#     RELATIVE name, so `chrysanta` escalates to root by hijacking $PATH
#     (Stage 8).
#
# The credentials MUST match the seeded email in docker/smtp/seed-mail.sh.
#
# ============================================================================
# THIS DELIBERATELY WEAKENS THE HOST: a password-login SSH account and a
# SUID-root PATH-hijack. Run it ONLY on an isolated, disposable lab host, and
# firewall SSH to the class. It refuses to run without --confirm. Undo it with
# `--uninstall` (also wired into install/uninstall.sh --purge).
# ============================================================================
#
# Usage:
#   sudo ./privesc-host.sh --confirm        # install
#   sudo ./privesc-host.sh --uninstall      # remove everything it created
#   sudo ./privesc-host.sh --confirm --dry-run
#
set -euo pipefail

PRIVESC_USER="${PRIVESC_USER:-chrysanta}"
PRIVESC_PASS="${PRIVESC_PASS:-BenMyG0AT}"
SUID_BIN="/usr/local/bin/opsbackup"
HIJACK_NAME="backup-check"                       # the relative command opsbackup runs
SSHD_DROPIN="/etc/ssh/sshd_config.d/60-siwang-lab.conf"
MARKER="# siwang-lab privesc (Stage 7-8) -- remove with privesc-host.sh --uninstall"

MODE=""
DRYRUN=no

for arg in "$@"; do
    case "$arg" in
        --confirm)   MODE="install" ;;
        --uninstall) MODE="uninstall" ;;
        --dry-run)   DRYRUN=yes ;;
        *) echo "unknown argument: $arg" >&2; exit 2 ;;
    esac
done

if [[ -z "$MODE" ]]; then
    echo "refusing to act without --confirm (install) or --uninstall." >&2
    echo "see the header of this script -- it weakens the HOST on purpose." >&2
    exit 1
fi

if [[ $EUID -ne 0 ]]; then
    echo "must run as root (it creates a user and a SUID binary)." >&2
    exit 1
fi

run() {
    if [[ "$DRYRUN" == yes ]]; then
        echo "  [dry-run] $*"
    else
        eval "$*"
    fi
}

restart_ssh() {
    # The service is named ssh on Debian/Ubuntu, sshd on some others.
    run "systemctl reload ssh 2>/dev/null || systemctl reload sshd 2>/dev/null || \
         systemctl restart ssh 2>/dev/null || systemctl restart sshd 2>/dev/null || true"
}

# ---------------------------------------------------------------------------
do_uninstall() {
    echo "==> Removing Stage 7-8 host material"
    run "rm -f '${SUID_BIN}'"
    run "rm -f '${SSHD_DROPIN}'"
    if id "${PRIVESC_USER}" >/dev/null 2>&1; then
        run "pkill -u '${PRIVESC_USER}' 2>/dev/null || true"
        run "userdel -r '${PRIVESC_USER}' 2>/dev/null || true"
    fi
    restart_ssh
    echo "==> Done. ${PRIVESC_USER}, ${SUID_BIN} and ${SSHD_DROPIN} are gone."
}

do_install() {
    echo "==> Provisioning Stage 7-8 host material"
    echo "    user=${PRIVESC_USER}  suid=${SUID_BIN}  sshd-dropin=${SSHD_DROPIN}"

    # 1. The shell user the mailbox email points at.
    if id "${PRIVESC_USER}" >/dev/null 2>&1; then
        echo "    user ${PRIVESC_USER} already exists -- leaving it, resetting password"
    else
        run "useradd -m -s /bin/bash -c 'Chrysanta (ops)' '${PRIVESC_USER}'"
    fi
    run "echo '${PRIVESC_USER}:${PRIVESC_PASS}' | chpasswd"

    # 2. Let that one user log in with a password, without flipping the global
    #    policy (many hardened hosts have PasswordAuthentication no by default).
    run "install -d -m 0755 /etc/ssh/sshd_config.d"
    if [[ "$DRYRUN" == yes ]]; then
        echo "  [dry-run] write ${SSHD_DROPIN} (Match User ${PRIVESC_USER} / PasswordAuthentication yes)"
    else
        cat > "${SSHD_DROPIN}" <<EOF
${MARKER}
Match User ${PRIVESC_USER}
    PasswordAuthentication yes
    KbdInteractiveAuthentication yes
EOF
        chmod 0644 "${SSHD_DROPIN}"
    fi
    restart_ssh

    # 3. The SUID-root PATH-hijack helper.
    #    It resets to a full root identity and then runs the health-check helper
    #    BY NAME, trusting whatever $PATH hands it -- the whole bug.
    local src cc
    src="$(mktemp /tmp/opsbackup.XXXXXX.c)"
    cat > "${src}" <<EOF
/* Siwang ops -- nightly backup health check (SUID wrapper).
 * LAB VULN (Stage 8): runs "${HIJACK_NAME}" by relative name as root, so any
 * user who can run this binary can win root by putting their own
 * "${HIJACK_NAME}" earlier in \$PATH. Fix would be an absolute path + a
 * sanitised environment. */
#include <stdlib.h>
#include <unistd.h>
#include <stdio.h>
int main(void) {
    setgid(0); setuid(0);
    fprintf(stderr, "[opsbackup] running backup health check...\n");
    execlp("${HIJACK_NAME}", "${HIJACK_NAME}", (char *)NULL);
    perror("[opsbackup] ${HIJACK_NAME}");
    return 127;
}
EOF

    cc="$(command -v cc || command -v gcc || true)"
    if [[ -z "$cc" ]]; then
        if [[ "$DRYRUN" == yes ]]; then
            echo "  [dry-run] NOTE: no C compiler found; a real run needs cc/gcc (apt-get install -y gcc)"
            cc="cc"
        else
            echo "error: need a C compiler (cc/gcc) to build ${SUID_BIN}." >&2
            echo "       install one (apt-get install -y gcc) and re-run." >&2
            rm -f "${src}"
            exit 1
        fi
    fi

    if [[ "$DRYRUN" == yes ]]; then
        echo "  [dry-run] ${cc} ${src} -o ${SUID_BIN}; chown root:root; chmod 4755"
    else
        "${cc}" "${src}" -o "${SUID_BIN}"
        chown root:root "${SUID_BIN}"
        chmod 4755 "${SUID_BIN}"
    fi
    rm -f "${src}"

    echo "==> Done."
    echo "    Stage 7: ssh ${PRIVESC_USER}@<host>   (password: ${PRIVESC_PASS})"
    echo "    Stage 8: find / -perm -4000  ->  ${SUID_BIN}  ->  PATH-hijack '${HIJACK_NAME}'"
    echo
    echo "    Remember to firewall SSH (:22) to the class source range."
}

case "$MODE" in
    install)   do_install ;;
    uninstall) do_uninstall ;;
esac
