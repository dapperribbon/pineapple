# Privilege escalation — reserved for the next build (Stages 4–5)

*Not built yet. This box currently ends at a `www-data` shell. This file records
the design intent so the follow-up build starts from a known position and does
not disturb Stages 1–3.*

The chain to be built: **`www-data` → local user `siwang` → `root`.**

## Why it is deferred

The user chose to lock down and validate initial access (Stages 1–3) first, and
plan privesc as a separate round. Building it now would mean guessing at
decisions (which local user, which root vector) that are better made
deliberately.

## The reserved hook: `backup.siwang.pineapple`

The `backup` vhost already exists and is deliberately empty. It was built into
Stage 1 precisely so this phase has somewhere to live **without touching the
Stage 1–3 Apache/PHP/DB config**. The in-world story already supports it: the
brochure and the dev app both mention "nightly snapshots written to the
operations backup host," and the backup stub page talks about restores.

## Candidate `www-data → siwang` vectors (decide next round)

1. **Backup archive + credential reuse** *(front-runner in planning).*
   A stale site/DB backup readable by `www-data` under the backup docroot (or
   `/opt/backups`) containing the DB password; the local user `siwang` reuses
   that password, so `su siwang` works. Reinforce with a crackable hash. Ties
   the otherwise-inert backup vhost into the chain.
2. **Readable SSH key** — passphrase-protected `id_rsa` left in the backup area,
   crack with `ssh2john`. Requires SSH exposed to the student.
3. **World-writable script consumed by a user cron** — faster but timing makes
   the box feel flaky in class.

## Candidate `siwang → root` vectors

1. **`sudo` NOPASSWD backup script + `tar` wildcard injection** *(front-runner).*
   `sudo -l` reveals `siwang` may run `/opt/backup/site-backup.sh` as root; the
   script `tar`s a user-writable dir with a wildcard, so `--checkpoint-action`
   injection yields a root shell. Continues the backup narrative, no timing
   dependency, discoverable via `sudo -l`.
2. **SUID binary with PATH hijack** — needs a compiled artifact in the build.
3. **`sudo` on a GTFOBins binary** — reliable but a one-liner lookup, not much
   of an exercise.

## Guardrails to preserve when building this

- Do not weaken any Stage 1–3 control listed in `UNINTENDED-PATHS.md`.
- The `siwang` local user and any sudo rule are created by a **new** installer
  step, not by the current `install.sh`.
- Keep "exactly one path": if the backup archive is the intended
  `www-data→user` route, make sure the DB password isn't *also* trivially
  readable somewhere else that skips it.
- Re-run `verify.sh` plus new privesc checks after building.
