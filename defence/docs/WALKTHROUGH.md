# Instructor walkthrough — Stages 1–3

The full intended solution, with the "why" behind each step so you can teach it,
not just demo it. Student-facing exploitation commands live in
`exploit/USAGE.md`; this document is the annotated version.

---

## Stage 1 — vhost discovery

**Intended:** the student browses `http://siwang.duckdns.org/`, reads it, and
finds `dev.siwang.pineapple` in two places — the footer "Staging portal" link
and the `STAGING_API` constant in `assets/js/site.js`. The browser cannot
resolve it, so they add it to `/etc/hosts` and get the staging login page.

**Backup path:** vhost fuzzing. Unmatched Host headers fall through to the
brochure (it is the first vhost loaded, `000-`), and the brochure is engineered
to return a **byte-identical** body regardless of the Host — no version banner,
no echoed hostname (`UseCanonicalName Off`), no timestamps. So:

```bash
curl -s -H 'Host: x.siwang.pineapple' http://<ip>/ | wc -c    # brochure size
ffuf -w subs.txt -u http://<ip>/ -H 'Host: FUZZ.siwang.pineapple' -fs <size>
```

surfaces `dev` and `backup`, which differ in size.

**Teaching point:** virtual-host routing is not a security boundary. "Not in
DNS" is not "not reachable." The same Host-header trick that fuzzes here is how
real internal apps get found behind a shared IP.

---

## Stage 2 — normal user to admin (PHP object injection)

**2a.** Registration is open (`MWS-402`, never disabled). The student makes an
account and signs in with **Keep me signed in** ticked. That sets
`siwang_remember`, which is `base64(serialize($user))`.

**2b.** The cookie decodes to readable PHP:

```
O:4:"User":3:{s:2:"id";i:7;s:8:"username";s:8:"uat_9f21";s:4:"role";s:4:"user";}
```

The app trusts `role` straight out of the cookie (`includes/auth.php`,
`restore_from_remember_cookie()`). Flip `s:4:"user"` → `s:5:"admin"`, re-encode,
replace the cookie, reload. Admin nav appears.

**The teaching points, in order of importance:**

1. **This is not "just cookie tampering" — it is `unserialize()` on untrusted
   input.** The distinction matters. The code uses
   `unserialize($raw, ['allowed_classes' => ['User']])`, which is the PHP 7+
   hardening advice for object injection. It works: it stops POP gadget chains,
   which is why there is no shortcut from here to file write or RCE. **But it
   does not make the operation safe**, because the *contents* of the permitted
   `User` object are still fully attacker-controlled. `allowed_classes`
   constrains *which* classes; it does nothing about *what is in them*. That gap
   is the entire lesson.

2. **Authorization state was stored client-side.** The fix is not "sign the
   cookie" (though that would stop this specific attack) — it is "never trust
   the client for the role." Note the deliberate tell: `/profile.php` reads the
   role from the *database* and still says `user` after a successful forge,
   while the nav (driven by the session) says `admin`. Ask students which one is
   right, and where the check on `/upload.php` should really look.

3. **Length prefixes.** Students who try this by hand in Burp will forget to
   change `s:4` to `s:5` and get a silent failure. `unserialize()` returns
   `false`, the `instanceof` check fails, nothing happens. This is a good,
   low-stakes lesson in how the serialization format actually works.

**Why the flow is smooth:** `restore_from_remember_cookie()` runs on *every*
request, not only when the session is empty, so the swap takes effect
immediately. If it only fired on an empty session, tampering while logged in
would do nothing — a dead end with no feedback. (Signing out also works and is
the "cleanest" mental model; both are fine.)

---

## Stage 3 — admin upload to RCE (real image + short-echo tag)

The upload has **five** checks, all in `upload.php`, and the payload has to beat
all of them at once:

| # | Check | Code | Bypass |
|---|---|---|---|
| 1 | extension allowlist | `in_array($ext, ['jpg','jpeg','gif','png','bmp'])` | name it `.gif` |
| 2 | size cap (500 KB) | `$file['size'] > UPLOAD_MAX` | keep it small |
| 3 | no `.php` in the name | `stripos($name, '.php') !== false` | `shell.gif` has none |
| 4 | must decode as an image | `imagecreatefrom*()` (GD) | start from a **real image** |
| 5 | no `<?php` in contents | `strpos($data, '<?php')` | use the short-echo tag **`<?=`** |

Final payload — a genuine GIF with the tag appended after the image data:

```
<47 49 46 38 39 61 …real 1x1 GIF bytes… 3B>
<?= system($_GET['c']); ?>
```

uploaded as `shell.gif`. The stored file keeps its image extension, and the
vhost maps image extensions to PHP-FPM **inside `/uploads/` only**, so fetching
`/uploads/<name>.gif?c=id` executes it as `www-data`. (The stored name is
server-randomised and never printed as a link; students recover the URL from the
`src` of the broken `<img>` thumbnail on the upload confirmation / `/admin.php`
— i.e. from view-source or the Network tab.)

**Teaching points:**

1. **A decode check is not a sanitiser.** `imagecreatefromgif()` proves the file
   *contains* a valid image — it does not remove anything, and here the decoded
   image is thrown away and the original bytes are stored. Real defence
   *re-encodes* the image and writes the re-encoded output, which drops trailing
   payload data. (That's the one-line fix: save `imagegif($im, …)`, not the
   upload.)
2. **String blocklists miss siblings.** Blocking `<?php` does nothing about
   `<?=` (always enabled, independent of `short_open_tag`); historically
   `<script language="php">` was another. Allowlisting *what a template may
   contain* is not how you keep code out of an upload — keeping the upload dir
   non-executable is.
3. **Extension allowlist + a permissive execution mapping still lose.** The
   allowlist correctly forces an image extension — but the deployment then maps
   image extensions to PHP in the upload dir. The allowlist was sound; the
   server config defeated it. Uploads should live somewhere with no interpreter.
4. **Distinct error messages are an oracle.** Each of the five layers has its own
   rejection string, so an attacker peels them one at a time. Verbose,
   layer-specific validation errors are themselves a (minor) finding.

**Blue-team half:** on the server, `file /var/www/dev/uploads/<name>.gif` reports
a real GIF image, and the stored row looks like an ordinary image upload — yet it
executes. The lesson: MIME/type logging won't catch this; *"an upload directory
is executing code"* is the detection. A rule that flags PHP tags (`<?`) inside
files under an upload path, or simply an alert that the upload dir has a PHP
handler at all, is what catches it.

### Optional difficulty bump

Two independent ways to make Stage 3 harder:
- **Re-encode instead of decode-and-discard** (the real fix, used as a partial
  mitigation): save `imagegif($im, $target)` so trailing bytes are dropped —
  then students must embed the payload *inside* image data that survives a
  re-encode (e.g. in a text chunk GD preserves), a much harder exercise.
- **Tighten the content scan** to also reject `<?` (catching `<?=`). Then the
  only route left is a metadata/EXIF field the interpreter still runs — steeply
  harder. Do either only if the class found the base version too quick.

---

## After Stage 3

The student has a shell as `www-data` inside the `siwang` container.
`open_basedir` is scoped to `/var/www/dev` but does not apply to
`system()`-spawned children, so a reverse shell escapes it cleanly. That is the
end of initial access.

The chain continues — `www-data → cracked mail cred → host user → root on the
host` — in **Stages 4–8 below** (built). The old `backup` vhost hook is retired;
it stays inert set-dressing.

---

## Common ways students get stuck (and the nudge)

| Symptom | Cause | Nudge |
|---|---|---|
| Can't find dev vhost | didn't read the brochure | "What's in the footer? What does the JS try to load?" |
| Cookie edit does nothing | forgot the length prefix | "How does PHP know how long the string is?" |
| Cookie edit does nothing (2) | edited while logged in, doubts it | "Sign out, set the cookie, reload." |
| Upload always rejected | only beat one of the five checks | "Read the exact error. Which check is talking?" |
| "not a valid image" | uploaded a bare `<?= … ?>` file, no image data | "It has to decode as a real image — start from one." |
| "contains server code" | used `<?php` | "What other PHP open tag is there?" (→ `<?=`) |
| Uploads OK but never executes | fetching a legit image, or named `.php`-ish | "The stored URL is in the page source (the thumbnail's img src). Payload must be in a real image, named `.gif`." |
| Ping tool eating all their time | working as intended | let them; it's the lesson. Show them `diag_queue` afterwards. |
| Ping tool eating all their time | working as intended | let them; it's the lesson. Show them `diag_queue` afterwards. |

---

## Stages 4–8 — www-data to root on the host (BUILT)

Full annotated build/teardown is in `docs/PRIVESC-TODO.md`; student-facing
commands are in `exploit/USAGE.md`. The teaching arc:

**Stage 4 (loot).** `www-data` reads `config.php` (it must — the app needs the
DB password, and `open_basedir` includes the docroot) and dumps `users`. Point
to make: an RCE foothold turns "the app can read its own config" into "the
attacker can read every stored hash." The `siwang_app` grant is least-privilege
(`SELECT/INSERT/UPDATE`, no `FILE`) — enough to *read* the hashes, not to write
a shell via `INTO OUTFILE`. Least-privilege limited the blast radius; it didn't
stop the loot.

**Stage 5 (crack).** Exactly one hash cracks — `chrysanta` → `dylan`. The others
are long/random on purpose. Teaching point: the crack is trivial; the finding is
**password reuse**, not bcrypt. Ask why a cracked *non-admin* web password is
worth anything — it's the reuse on another service that matters.

**Stage 6 (pivot + reuse).** The mail host is on an internal-only docker network
with no published port, so students must reach it *through* the RCE'd box. Two
lessons: (1) network segmentation as seen from a foothold — "internal only" is a
speed-bump once you own something on the segment; (2) credential reuse — the web
password opens the mailbox. Then it's a needle-in-haystack read: ~12 decoy
emails, one reset notice. Watching students grep vs. read-every-message is a
good observation moment.

**Stage 7 (SSH to the host).** The reset email leaks chrysanta's *host* shell
password. This is the deliberate "leave the container" step: the escape is a
**credential found in the estate**, not a Docker breakout (see
`UNINTENDED-PATHS.md` §10 for why an unintended runtime escape is closed off).

**Stage 8 (SUID PATH hijack).** `find / -perm -4000` surfaces `opsbackup`;
`strings` shows it runs `backup-check` by bare name after `setuid(0)`. Prepend a
writable dir to `$PATH` → root. Teaching point: SUID + a relative command name +
inherited `$PATH` is the whole bug; the fix is an absolute path and a sanitised
environment (or dropping the SUID bit entirely).

### Operational notes for the instructor

- Provision the host stage yourself: `sudo install/privesc-host.sh --confirm`
  (it refuses without the flag; `--dry-run` shows exactly what it changes; undo
  with `--uninstall`). It creates a password SSH account and a SUID binary on the
  **host** — isolated, disposable lab boxes only, and firewall `:22` to the class.
- Credentials to keep in sync if you change them: `db/seed_users.php`
  (`chrysanta`/`dylan`) and `docker/smtp/seed-mail.sh` + `install/privesc-host.sh`
  (`BenMyG0AT`).
- The mailbox re-seeds on every mail-container restart (fresh tmpfs), so a
  `docker compose restart smtp` resets Stage 6 between cohorts.

| Symptom | Cause | Nudge |
|---|---|---|
| Can't reach the mail host | it's internal-only | "Where can that hostname resolve from? You already have a foothold that can." |
| Cracks nothing | ran the admin/other hashes | "Which account looks ordinary? Try that one." |
| Read the reset email, stuck | logged into mail, not the host | "The email is about a *shell* account. What service is that?" |
| SUID found, now what | didn't inspect it | "`strings` it. What does it run, and how does it find it?" |
