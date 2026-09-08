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
- Upload filename is run through `basename()` and rejected if it starts with a
  dot or contains a NUL, so a traversal filename cannot escape `uploads/`.
  **[verify]** (`www-data` cannot write app code)

## 2. PHP executing where it shouldn't

- Only the dev vhost has an FPM handler. The brochure and backup vhosts have
  **no** PHP handler at all, and additionally deny PHP-ish extensions with a
  `FilesMatch … Require all denied`. A `.php` dropped on the brochure is served
  as… nothing (403), never as source, never executed. **[verify]**
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
  The internal `*.siwang.pineapple` vhosts stay on HTTP by design (no valid cert
  is possible for names absent from public DNS). The IP redirect keys on the
  Host *header*, so `ffuf -H "Host: FUZZ.siwang.pineapple"` is unaffected and
  the Stage 1 fallback still works.

---

## Explicitly-accepted, intended "weaknesses"

These look like findings but are load-bearing parts of the lab. Do not "fix"
them:

- Empty `disable_functions` (Stage 3 needs `system`/`exec`).
- Loose `open_basedir` including `/tmp` (per brief; and a `system()` child
  escapes it anyway — that's a lesson, not a leak of the box).
- FPM mapping applies inside `uploads/` (the Stage 3 misconfiguration itself).
- Self-service registration enabled (Stage 2a entry).
- The persistent remember-me cookie surviving in the browser (Stage 2b).
- No CSRF token on `upload.php` / `tools.php` (keeps them scriptable; in-world,
  added-late screens that missed the review).
