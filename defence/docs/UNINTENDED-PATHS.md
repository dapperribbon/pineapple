# Threat model — unintended paths and how each is closed

*Instructor / maintainer reference. The box is only a good teaching tool if the
intended path is the ONLY path. This is the list of every shortcut we
considered and what stops it. If you modify the box, re-check this list.*

The `install/verify.sh` script mechanically checks the items marked **[verify]**.

---

## 1. Reaching one docroot from another

- Three separate document roots: `/var/www/main`, `/var/www/dev`,
  `/var/www/backup`. No shared parent inside the web tree.
- `open_basedir = /var/www/dev/:/tmp/:/var/tmp/:<sessiondir>` on the dev pool,
  so PHP file functions in the dev app cannot read the other two roots.
- The stored filename is **server-generated** (`bin2hex(random_bytes(8))` + the
  validated image extension); the client-supplied name never reaches the path,
  so there is no traversal or overwrite of app files. **[verify]** (`www-data`
  cannot write app code)

## 2. PHP executing where it shouldn't

- Only the dev vhost has an FPM handler. The brochure and backup vhosts have
  **no** PHP handler at all, and additionally deny PHP-ish extensions with a
  `FilesMatch … Require all denied`. A `.php` dropped on the brochure is served
  as… nothing (403), never as source, never executed. **[verify]**
- On the dev vhost, the global handler runs **only `.php`**. Image extensions
  are handed to PHP-FPM by a handler scoped to `<Directory /var/www/dev/uploads>`
  **only** — that is the Stage 3 misconfiguration, and it does not apply
  anywhere else in the docroot. **[verify]** (an image dropped at the docroot
  root does not execute)
- `security.limit_extensions` in the FPM pool lists the image extensions so FPM
  will run them; it is pool-global, but only the uploads-dir handler *routes*
  images to FPM, so execution stays confined to that directory. Nothing else in
  the app maps an image to FPM.
- `AllowOverride None` everywhere, so an uploaded `.htaccess` is inert and
  cannot add a handler or re-enable indexing.

## 3. Object-injection shortcut past Stage 3

The big one. `unserialize()` on attacker input is a code-execution primitive if
a usable gadget exists. Closed by:

- `unserialize($raw, ['allowed_classes' => ['User']])` — only `User` may be
  instantiated; anything else becomes `__PHP_Incomplete_Class` and fails the
  `instanceof` check.
- `User` has **no magic methods** (`__wakeup`, `__destruct`, `__toString`, …),
  so even the permitted class is not a gadget.
- **No autoloader.** `bootstrap.php` `require_once`s a fixed, small set of
  files. No other class is defined in the process when the cookie is
  deserialized, so the gadget pool is empty by construction.

If you add a class to the app, confirm it is not reachable at deserialization
time, or add it to a deny consideration here.

## 4. Skipping Stage 2 (going straight to upload)

- `/upload.php` and `/admin.php` both call `require_admin()` at the top, which
  checks the session role **server-side on every request** and renders a 403
  otherwise. The hidden nav item is cosmetic; the gate is real. **[verify]**

## 5. SQL injection as an alternate entry / data path

- Every query is a PDO prepared statement with `ATTR_EMULATE_PREPARES = false`
  (server-side binding). The dashboard search adds `%`/`_` wildcards in PHP and
  escapes the user's literal wildcards, so even `LIKE` is not injectable.
- The app DB user has `SELECT, INSERT, UPDATE` on `siwang_dev` only — no
  `DELETE`, `DROP`, `ALTER`, and crucially **no `FILE`**, so `SELECT … INTO
  OUTFILE` cannot be used to write a webshell even if an injection existed.
- DB user bound to `127.0.0.1`; MariaDB stays on loopback. **[verify]**

## 6. Command injection via the diagnostics tool

This tool *really executes* `ping`, so it is the highest-risk component and gets
the most scrutiny:

- Input must match an `\A…\z`-anchored IP/hostname allowlist. The anchors are
  the point: `^…$` would accept `127.0.0.1\n; id` because PHP's `$` matches
  before a trailing newline. `\z` does not.
- `escapeshellarg()` wraps the argument regardless, as a second layer.
- The command line uses a fixed argument vector and a `--` end-of-options
  marker; a leading `-` also fails the regex, so option injection (`-f`, `-w`
  to hang) is impossible.
- Bounded `-c`/`-W`/`-w` so it can't hang an FPM worker; per-account rate limit
  so it can't be a traffic generator.
- Output is HTML-escaped, and `-n` disables the rDNS lookup, so a hostile PTR
  record can't land stored XSS.
- **[verify]** confirms `ping` keeps `cap_net_raw` so this stays convincing.

The injection battery to re-run if you touch this file:
`127.0.0.1; id` · `127.0.0.1 && id` · `127.0.0.1|id` · `$(id)` · `` `id` `` ·
`127.0.0.1%0aid` · `-f 127.0.0.1` · a 300-char host ·
`127.0.0.1<newline>; id`. All must return "Invalid host."

## 7. Information disclosure

- `expose_php = off`, `ServerTokens Prod`, `ServerSignature Off` — no version
  banners (also required for the stable-size fallback).
- `display_errors = off`; DB connection failure is caught and logged, not
  printed. A leaked PDO exception would hand out the DB DSN.
- `includes/` and `partials/` denied over HTTP, so `config.php` (DB password)
  can't be read as source even if FPM were down. **[verify]**
- `lockdown.sh` sweeps `.git`, `*.bak`, `*.sql`, editor swap files, etc. from
  the deployed roots.
- `config.php` is `root:www-data 0640` — readable by the app, not world.

## 8. Tampering with the box's own files via the webshell

Even after legitimate Stage 3 RCE, `www-data` should not be able to rewrite the
lab:

- All served files are `root:www-data`, dirs `0750`, files `0640` — readable by
  the web group, writable by none of it.
- The single exception is `/var/www/dev/uploads` (`www-data:www-data 0755`),
  the intended payload landing zone. **[verify]**
- So a student cannot, e.g., edit `upload.php` to remove the filter, or replace
  the brochure. **[verify]**

## 9. Network surface

- `ufw`: only 22/tcp, 80/tcp and 443/tcp inbound. No 3306, no direct FPM socket
  exposure (it is a unix socket). **[verify]**
- Public domain is served over TLS (Let's Encrypt, `siwang.duckdns.org`); plain
  HTTP to the domain and any direct-IP visit 301-redirect to the HTTPS domain.
  The internal `*.siwang.pineapple` vhosts are HTTP-only by design (no valid
  cert is possible for names absent from public DNS). Each now also has a
  dedicated `*:443` vhost whose only job is to **301 an https:// attempt back to
  http://** on the same host -- without it, an https://dev.siwang.pineapple
  request has no matching `:443` vhost and silently falls through to the default
  one (the brochure), which is wrong. The TLS handshake for those names still
  presents the brochure's `siwang.duckdns.org` certificate, so a browser shows a
  name-mismatch warning before the redirect -- expected and unavoidable for a
  name that cannot hold a valid certificate. The IP redirect keys on the Host
  *header*, so `ffuf -H "Host: FUZZ.siwang.pineapple"` is unaffected and the
  Stage 1 fallback still works. An *unmatched* https Host still lands on the
  brochure's `:443` vhost, which is fine.

---

## Explicitly-accepted, intended "weaknesses"

These look like findings but are load-bearing parts of the lab. Do not "fix"
them:

- Empty `disable_functions` (Stage 3 needs `system`/`exec`).
- Loose `open_basedir` including `/tmp` (per brief; and a `system()` child
  escapes it anyway — that's a lesson, not a leak of the box).
- Image extensions mapped to FPM **inside `uploads/`**, plus those extensions in
  `security.limit_extensions` (the Stage 3 misconfiguration itself).
- The upload decodes an image but stores the **original** bytes rather than a
  re-encoded copy, so an appended payload survives (the Stage 3 flaw). "Fixing"
  it means writing `imagegif($im, …)` output instead.
- Self-service registration enabled (Stage 2a entry).
- The persistent remember-me cookie surviving in the browser (Stage 2b).
- No CSRF token on `upload.php` / `tools.php` (keeps them scriptable; in-world,
  added-late screens that missed the review).

**Image rendering / the breadcrumb.** Because `uploads/` runs image extensions
through PHP, every image there — including the `<img>` thumbnails on the admin
and upload pages — is executed by FPM and comes back as `text/html`, so it
renders broken instead of displaying. This is intentional: the path is never
printed as a label or link, only as the `src` of those thumbnails, so it is
exposed in the page source / Network tab (a deliberately subtle breadcrumb) but
not handed to the student directly. There is no image-viewer/streamer endpoint
(an earlier `view.php` was removed) — nothing reads a client-named file back out
of `uploads/`, so there is no anonymous or traversal file-read surface. Fetching
`/uploads/<name>.<ext>` directly is the Stage 3 execution vector, as intended.

---

## 10. Container isolation and the Stages 4–8 additions

Stages 4–8 add a second container (`smtp`) and move the endgame onto the host.
The intended "escape" from the containers is by **credential** (crack → mail →
host SSH), not a runtime breakout. This section records what stops an
*unintended* container→host escape, and how the new pieces must not regress it.

**Closed:**
- No `privileged: true`, no `docker.sock`, no host PID/net/IPC namespaces, no
  writable host bind-mounts on either service.
- `cap_drop: ALL` on both, with a minimal add-back. The siwang box keeps only
  CHOWN, DAC_OVERRIDE, FOWNER, SETUID, SETGID, KILL, NET_BIND_SERVICE, NET_RAW,
  SETFCAP; the mail box keeps only NET_BIND_SERVICE. No SYS_ADMIN / SYS_PTRACE /
  SYS_MODULE, so the classic cgroup `release_agent` / `core_pattern` breakouts
  are unavailable.
- The letsencrypt mount is narrowed to the siwang cert's `live` symlinks + the
  single `archive/siwang.duckdns.org` subdir (read-only). It no longer exposes
  every host certificate's private key. **[verify: mail ports not on host]**
- The mail box is `read_only: true` with tmpfs `/data` + `/tmp` and
  `security_opt: no-new-privileges` — it has no shell user, no sshd, no SUID, no
  file-capability binaries, so it is a pure read target.
- The attacker is `www-data`, never container-root by the intended path; every
  cap-based escape needs container-root first.

**Deliberately NOT set:** `no-new-privileges` on the **siwang** box. It would
make the kernel ignore ping's `cap_net_raw` file capability and break the
diagnostics rabbit hole (verify.sh would fail). Hardening is per-container for
this reason — do not "helpfully" add it to siwang.

**Residual (accepted):**
- Shared host kernel: a kernel LPE run as container-root would be host root.
  Inherent to plain containers; mitigated by patching + the default seccomp /
  AppArmor profiles (left on). The intended path never grants container-root.
- No userns-remap, so container-root maps to host-root uid. Harmless while no
  writable host mount / abusable cap exists (none), but it means any future
  misconfig (a socket, a writable mount, `privileged`) is an instant host
  takeover — keep them out.

**Network:** `labnet` is `internal: true` and the `smtp` service publishes no
ports, so the mail host is reachable only from the siwang container — students
must pivot through the Stage 3 RCE. The siwang box sits additionally on `edge`
(a normal bridge) for its published 80/443 and for reverse-shell egress.

**Host (Stages 7–8):** `install/privesc-host.sh` intentionally weakens the host
(a password-login SSH account `chrysanta` + a SUID PATH-hijack `opsbackup`). It
is gated behind `--confirm`, is reversible (`--uninstall`, and via
`uninstall.sh --purge`), and must only be run on an isolated, disposable lab
host with SSH `:22` firewalled to the class. `BenMyG0AT` is a burned password.
