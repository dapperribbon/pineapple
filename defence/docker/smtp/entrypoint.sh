#!/bin/sh
# Siwang CTF lab -- mail host entrypoint.
#
# /data is a fresh tmpfs on every start (see docker-compose.yml), so the mailbox
# is provisioned from scratch each boot. That is intentional: recreating the
# container is the lab's reset-between-cohorts mechanism, exactly as for the
# siwang box.

set -eu

DATA=/data
CONF="${DATA}/maddy.conf"
ACCT="${MAIL_USER:-chrysanta@siwang-trading.example}"
PASS="${MAIL_PASS:-dylan}"

echo "==> Installing maddy config into ${DATA}"
cp /opt/lab/maddy.conf "${CONF}"

if [ ! -f "${DATA}/.provisioned" ]; then
    echo "==> Creating credentials + IMAP account for ${ACCT}"
    /bin/maddy --config "${CONF}" creds create -p "${PASS}" --hash bcrypt "${ACCT}"
    /bin/maddy --config "${CONF}" imap-acct create "${ACCT}"

    echo "==> Seeding mailbox"
    /opt/lab/seed-mail.sh "${CONF}" "${ACCT}"

    touch "${DATA}/.provisioned"
fi

echo "==> Starting maddy"
exec /bin/maddy --config "${CONF}" run
