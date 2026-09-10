# Containerised Siwang lab

A `docker compose up` build of the same Stage 1–3 box `install/install.sh`
produces on an Ubuntu 24.04 VM.

> **The container is deliberately vulnerable.** Stage 3 ends in code execution
> as `www-data` by design. Isolated lab networks only. The published ports
> default to `127.0.0.1` for exactly this reason.

---

## Run it

```bash
cd defence/docker
docker compose up -d --build          # ~3–5 min on a first build
docker compose exec siwang /opt/siwang/install/verify.sh
```

`verify.sh` should print `PASS: 20  FAIL: 0`. It also runs during the build, so
a broken image usually announces itself before you ever start it.

Then point the vhost names at the box. Bound to loopback, that means your own
hosts file:

```
127.0.0.1   siwang.duckdns.org
127.0.0.1   dev.siwang.pineapple
127.0.0.1   backup.siwang.pineapple
```

(`install/hosts-entries.txt` has the same list with the paths for each OS.)
Then <http://dev.siwang.pineapple/> is the staging portal and
<http://siwang.duckdns.org/> is the brochure.

For a classroom, publish on the lab NIC instead and have students point their
hosts entries at that address:

```bash
SIWANG_BIND=0.0.0.0 docker compose up -d
```

## Everyday commands

| Task | Command |
|---|---|
| Reset between cohorts | `docker compose exec siwang /opt/siwang/install/lockdown.sh --reset` |
| Full wipe (DB, uploads, accounts) | `docker compose down && docker compose up -d` |
| Re-check all three stages | `docker compose exec siwang /opt/siwang/install/verify.sh` |
| Watch the dev vhost | `docker compose exec siwang tail -f /var/log/apache2/siwang-dev-access.log` |
| PHP errors | `docker compose exec siwang tail -f /var/log/php-siwang-dev.log` |
| Shell on the box | `docker compose exec siwang bash` |
| Shell as the web user | `docker compose exec -u www-data siwang bash` |
| Database | `docker compose exec siwang mysql siwang_dev` |
| Seeded passwords | `docker compose exec siwang grep -A4 "'username'" /opt/siwang/db/seed_users.php` |

Run the exploit from the **host**, not from inside the container:

```bash
python3 ../exploit/exploit.py --target http://dev.siwang.pineapple --cmd id
```

## How it differs from the VM build

The application, the vhosts, the FPM pool and both planted flaws are byte-identical
to the VM build — `install.sh` runs verbatim inside the image. What changes is
the plumbing around it:

| | VM (`install/install.sh`) | Container |
|---|---|---|
| Process supervision | systemd | supervisord (`docker/supervisord.conf`) |
| `systemctl` calls | real | `docker/systemctl` stub, build-time only |
| Firewall | `ufw` allows 22/80/443 | Docker publishes 80/443; nothing else is reachable. `lockdown.sh` skips its ufw block on its own (`command -v ufw`) |
| TLS | Let's Encrypt via certbot | self-signed cert at the same certbot path; bind-mount the real one to override |
| SSH | port 22 open | none — use `docker compose exec` |
| Repo location | operator's home directory | `/opt/siwang`, mode `0700` |
| Reset | `lockdown.sh --reset` | that, or just recreate the container |

Two things are worth knowing about:

**`docker/systemctl` is a real stub, not a no-op.** `install.sh` calls
`systemctl enable --now mariadb` and `systemctl restart apache2`, and a
container has no init system. Rather than fork `install.sh` into a
Docker-specific copy that drifts from the original, the stub genuinely starts
and stops the three services using the same binaries systemd would. That is
what lets the image be built by the unmodified installer — and it means
`install.sh`'s smoke test and `verify.sh` both run for real during
`docker build`.

**`docs/` and `exploit/` are excluded from the image** (see
`defence/.dockerignore`), and `/opt/siwang` is `0700`. A student who reaches
Stage 3 has code execution as `www-data` on this box; `WALKTHROUGH.md` or the
pristine `upload.php` sitting somewhere readable would be a shortcut straight
past the puzzle.

## Notes

**CRLF.** The repo is developed on Windows and `.gitattributes` uses
`* text=auto`, so the working tree there has CRLF endings — and
`#!/usr/bin/env bash\r` is not a valid interpreter on Linux. The Dockerfile
normalises every text file it copies, so the build works from a Windows or a
Linux checkout and produces the same bytes either way (which Stage 1's
`ffuf -fs` filter depends on). If you also rsync this repo to a VM from
Windows, add `*.sh text eol=lf` to `.gitattributes`.

**No `privileged: true`.** Nothing in Stages 1–3 needs it: Docker's default
capability set already includes `NET_RAW` (the ping rabbit hole) and `SETFCAP`
(`lockdown.sh`'s `setcap` call). When the deferred `www-data → user → root`
stages land, they should be won inside the box, not handed over by the
container runtime.

**Changing the app.** Rebuild rather than bind-mounting the docroot — a bind
mount arrives with the host's uid/gid and defeats `lockdown.sh`'s ownership
rules, which is how `www-data` ends up able to rewrite `upload.php`. If you do
mount it while developing, re-run `lockdown.sh` afterwards and re-read
`docs/UNINTENDED-PATHS.md`.

---

## Migrating a box that already ran `install.sh`

The native Apache owns `:80` and `:443`, so the container cannot publish them
until the VM install is decommissioned. [`install/uninstall.sh`](../install/uninstall.sh)
does that.

If the box is a disposable lab VM, **rolling back to a clean Ubuntu 24.04
snapshot is still the tidiest option** — the lab is designed to be rebuilt, and
you skip every question below. `uninstall.sh` is for when you want to keep the
box (its DNS, its certificate, its SSH keys).

```bash
cd defence

# 1. See exactly what would happen. Needs no root.
./install/uninstall.sh --purge --dry-run

# 2. Free :80 and :443 but delete nothing. Fully reversible.
sudo ./install/uninstall.sh

# 3. Or remove the lab properly: vhosts, FPM pool, docroots, DB, logs.
sudo ./install/uninstall.sh --purge

# 4. Add --packages to apt-purge apache2 / php8.3-* / mariadb-server as well.
sudo ./install/uninstall.sh --purge --packages
```

It drops the database *before* stopping MariaDB, puts Apache's stock
`000-default` vhost back (install.sh disabled it so the lab's would sort
first), and ends by checking that nothing still listens on 80 or 443. Every
step is best-effort — a failure is reported and the run continues rather than
leaving the box half-dismantled.

Left alone whatever flags you pass: `/etc/letsencrypt`, `/var/lib/mysql`, the
ufw rules, and sshd.

Then install Docker and bring the container up:

```bash
curl -fsSL https://get.docker.com | sudo sh
cd docker && sudo docker compose up -d --build
```

### ufw no longer protects the lab

This is the one thing worth pausing on. `lockdown.sh` configured ufw to allow
only 22, 80 and 443, and that was the box's real perimeter. **Docker publishes
ports by writing its own iptables rules in the `DOCKER` chain, which is
traversed before ufw's** — so a published port is reachable regardless of what
`ufw status` claims. Nothing in `uninstall.sh` changes that; it is how Docker
works.

On this stack the perimeter is therefore the bind address, not the firewall:

```bash
SIWANG_BIND=0.0.0.0        # reachable from anywhere that can route to the box
SIWANG_BIND=10.0.0.5       # reachable on the lab NIC only
SIWANG_BIND=127.0.0.1      # the default: this host only
```

Pick it deliberately, and keep ufw enabled anyway — it still guards SSH and
anything else not published through Docker.

### Reusing the real certificate

`uninstall.sh` never touches `/etc/letsencrypt`, so the Let's Encrypt
certificate survives. Uncomment the TLS bind mount in `docker-compose.yml` to
serve it instead of the image's self-signed one — the container expects it at
the same certbot path the vhost already names, so no config changes.

Renewal does change. Certbot's apache and webroot authenticators both depended
on the native Apache and `/var/www/main`, which are now gone. Switch to
standalone and let it borrow the port:

```bash
sudo certbot renew --standalone \
  --pre-hook  "docker compose -f /full/path/defence/docker/docker-compose.yml stop siwang" \
  --post-hook "docker compose -f /full/path/defence/docker/docker-compose.yml start siwang"
```

The post-hook restart is also what makes the container pick up the new
certificate — Apache reads it at startup.
