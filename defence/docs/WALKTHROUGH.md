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

## Stage 3 — admin upload to RCE (magic bytes + extension)

The upload has **three** checks, all in `upload.php`, and the payload has to
beat all three simultaneously:

| Layer | Code | Bypass |
|---|---|---|
| declared type | `in_array($_FILES['doc']['type'], [...])` | spoof `Content-Type: image/gif` |
| **content sniff** | `finfo_file()` on the temp file | prefix bytes `GIF89a` |
| extension | `pathinfo(...) === 'php'` (one entry) | name it `.phtml` |

Final payload:

```
GIF89a;
<?php system($_GET['cmd']); ?>
```

uploaded as `shell.phtml`, `Content-Type: image/gif`. The vhost maps
`.php .phtml .php5 .php7 .phar` to PHP-FPM **including under `/uploads`**, so
fetching `/uploads/shell.phtml?cmd=id` executes it as `www-data`.

**Teaching points:**

1. **libmagic reads signatures, not whole files.** A GIF is recognised from
   `GIF87a`/`GIF89a` at offset 0 and nothing else. A content sniff is stronger
   than a header check and *still* trivially defeated if it only reads the
   magic. This is why real image validation re-encodes the image rather than
   sniffing it.
2. **Blacklists lose.** One-entry (`.php`) or hundred-entry, a blacklist of
   dangerous extensions is a losing game against `.phtml`, `.phar`, case tricks,
   and whatever the web server happens to map. The fix is an allowlist bound to
   what the server will execute — and, better, storing uploads outside the web
   root or on a host with no interpreter.
3. **Distinct error messages are an oracle.** The two different rejection
   strings let the attacker peel the layers one at a time. Verbose, layer-
   specific validation errors are themselves a (minor) finding.

**Blue-team half:** on `/admin.php`, the uploaded row shows `image/gif` for both
declared and detected type while the stored filename ends in `.phtml`. `file`
on the server agrees it is a GIF. Point out that content-type logging did not
catch this and *filename plus execution mapping* is what mattered. A good
detection is "executable extension in an upload directory," not MIME.

### Optional difficulty bump

Swap `finfo_file()` for `getimagesize()` in `upload.php`. `getimagesize()`
parses the logical screen descriptor, so a bare 6-byte prefix is rejected and
students must build a structurally valid GIF header (width/height/flags) around
the payload, or append the PHP after a real image. Everything else in the chain
is unchanged. Do this only if the class found the base version too quick.

---

## After Stage 3

The student has a shell as `www-data`. `open_basedir` is scoped to
`/var/www/dev` but does not apply to `system()`-spawned children, so a reverse
shell escapes it cleanly. That is the end of initial access.

`www-data → user → root` is deliberately not built yet. See
`docs/PRIVESC-TODO.md` for the reserved hooks (the `backup` vhost, a nightly
backup job) so the follow-up build starts from a known place.

---

## Common ways students get stuck (and the nudge)

| Symptom | Cause | Nudge |
|---|---|---|
| Can't find dev vhost | didn't read the brochure | "What's in the footer? What does the JS try to load?" |
| Cookie edit does nothing | forgot the length prefix | "How does PHP know how long the string is?" |
| Cookie edit does nothing (2) | edited while logged in, doubts it | "Sign out, set the cookie, reload." |
| Upload always rejected | only spoofed one of three checks | "Read the exact error. Which check is talking?" |
| `.phtml` uploads but 404/downloads | fetching wrong path, or FPM not mapped | "The admin list links the real URL. If it still won't run, verify the vhost." |
| Ping tool eating all their time | working as intended | let them; it's the lesson. Show them `diag_queue` afterwards. |
