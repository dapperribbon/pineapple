# Siwang CTF privesc lab — `defence/`

A deliberately vulnerable training box (Ubuntu 24.04 LTS, LAMP) with **exactly
one intended path** through initial access:

```
vhost discovery  →  file-upload RCE  →  www-data
   (Stage 1)         (Stages 2–3)        (foothold)
```

`www-data → local user → root` is a **separate, later build** and is not
included here — see [`docs/PRIVESC-TODO.md`](docs/PRIVESC-TODO.md).

> **This box is intentionally insecure.** Deploy it only on an isolated lab
> network. Never expose it to the internet or run it on a machine you care
> about. The `duckdns.org` name is how students reach it; the `.pineapple`
> vhosts are meant to be added to `/etc/hosts` by hand and must not be put in
> public DNS.

---

## The intended path

| Stage | Vulnerability | Student does | Gets |
|---|---|---|---|
| 1 | vhost routing / hidden staging host | reads the brochure, finds `dev.siwang.pineapple`, adds a hosts entry (or fuzzes Host headers) | the staging login page |
| 2 | `unserialize()` of an unsigned "remember me" cookie | registers, ticks "keep me signed in", flips `role` in the serialized cookie | an admin session |
| 3 | upload filter: spoofable type + magic-byte sniff + one-entry extension blacklist | uploads `GIF89a`-prefixed PHP as `.phtml` with `Content-Type: image/gif` | RCE as `www-data` |

Everything else on the box is either genuinely secure or a deliberate dead end.
See [`docs/UNINTENDED-PATHS.md`](docs/UNINTENDED-PATHS.md) for how every shortcut
is closed.

---

## Layout

```
defence/
  apache/        vhosts, global hardening, PHP-FPM pool
  db/            schema, seed data, provisioning (bcrypt hashes generated at install)
  site/
    main/        static brochure   -> /var/www/main   (clean, byte-stable fallback)
    dev/         the vulnerable PHP app -> /var/www/dev
    backup/      stub vhost        -> /var/www/backup  (reserved privesc hook)
  exploit/       forge_cookie.py, make_payload.py, payload.phtml, exploit.py, USAGE.md
  install/       install.sh, lockdown.sh, verify.sh, hosts-entries.txt
  docs/          STORY, BREADCRUMBS, WALKTHROUGH, UNINTENDED-PATHS, PRIVESC-TODO
```

---

## Build a box

On a clean **Ubuntu 24.04 LTS** VM, as root:

```bash
git clone <this repo> && cd pineapple/defence
sudo install/install.sh      # packages, vhosts, FPM pool, DB, docroots, lockdown
sudo install/verify.sh       # confirm all three stages + unintended-path checks
```

`install.sh` generates a random DB password and writes it into
`site/dev`'s deployed `config.php` — no secrets are committed. It provisions
Stages 1–3 only; it does **not** create a local login user or any sudo rule.

Point DuckDNS (`siwang.duckdns.org`) at the box's public IP. The `.pineapple`
vhosts resolve only via the client's hosts file — see
[`install/hosts-entries.txt`](install/hosts-entries.txt).

### Reset between cohorts

```bash
sudo install/lockdown.sh --reset   # empties uploads, re-seeds DB, drops student accounts
```

---

## Solve it

Students get [`docs/STORY.md`](docs/STORY.md) (the spoiler-free brief) and the
box IP. The reference solution and copy-paste commands are in
[`exploit/USAGE.md`](exploit/USAGE.md); the annotated instructor version with the
teaching points is [`docs/WALKTHROUGH.md`](docs/WALKTHROUGH.md).

```bash
# full chain, unattended
python3 exploit/exploit.py --target http://dev.siwang.pineapple --cmd id
```

---

## The two planted flaws, precisely

**Stage 2 — object injection (`site/dev/includes/auth.php`).** The remember-me
cookie is `base64(serialize($user))` with no signature, and the app trusts the
`role` inside it. `unserialize()` is called with
`allowed_classes => ['User']`, and `User` has no magic methods and there is no
autoloader — so there is deliberately **no** gadget chain, no shortcut to RCE
here. The lesson is that `allowed_classes` stops gadgets but does **not** make
deserializing untrusted input safe, because the object's *contents* are still
attacker-controlled.

**Stage 3 — upload (`site/dev/upload.php`).** Three checks, each individually
bypassable: a client-supplied `Content-Type` (spoof it), a real `finfo` content
sniff (defeated by a 6-byte `GIF89a` prefix, because libmagic reads only the
signature), and a one-entry `.php` extension blacklist (use `.phtml`). The dev
vhost maps `.php .phtml .php5 .php7 .phar` to FPM including under `/uploads`.

---

## Reminder for maintainers

If you change the app, re-read [`docs/UNINTENDED-PATHS.md`](docs/UNINTENDED-PATHS.md)
and re-run `verify.sh`. The most fragile invariants are: the `\A…\z` anchors in
the ping validator, the absence of magic methods / an autoloader around the
`unserialize()` call, and `www-data` being unable to write anything but
`uploads/`.
