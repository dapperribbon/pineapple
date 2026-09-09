# Breadcrumbs — the trail of hints

*Instructor reference. Every deliberate hint on the box, where it lives, and
what it is meant to make the student do. If a student is stuck, this tells you
which breadcrumb they missed.*

The design goal: a student who reads carefully is never truly stuck, and never
needs to guess. Each stage leaks the next.

---

## Stage 1 — discover the dev vhost

| # | Where | What it says | Leads to |
|---|---|---|---|
| 1 | Brochure footer, every page — "Internal → **Staging portal**" | links to `http://dev.siwang.pineapple/` | browser fails to resolve → student reads the URL → adds `/etc/hosts` |
| 2 | `assets/js/site.js`, `STAGING_API` constant | `http://dev.siwang.pineapple/api/status` + a `TODO (MWS-412)` comment about repointing it | same host, visible as a failed request in the Network tab / console |
| 3 | *(fallback, no explicit hint)* | unmatched Host headers fall through to the brochure at a **stable size** | `ffuf -H "Host: FUZZ.siwang.pineapple" -fs <size>` finds `dev` and `backup` |

`backup.siwang.pineapple` is intentionally **not** hinted anywhere. It is
findable only by fuzzing and holds nothing for Stages 1–3. It is the reserved
hook for the later privesc build.

## Stage 2 — register, then escalate to admin

| # | Where | What it says | Leads to |
|---|---|---|---|
| 4 | `/login.php` footer | "Staging accounts are self-service during UAT — create one" | `/register.php` |
| 5 | The "Keep me signed in" checkbox | it is the only control that sets a non-session cookie | student inspects `siwang_remember`, sees base64 |
| 6 | The decoded cookie | human-readable PHP serialization with `role";s:4:"user"` | flip to `admin` (fix the length prefix) |
| 7 | Post-forge nav | gains **Document Upload** + **Administration** | confirms the escalation; points at Stage 3 |
| 8 | `/profile.php` after forging | still shows role **user** (read from the DB) | teaching tell: where authz state should live |

If a student tampers with the cookie and nothing happens, they almost certainly
edited it while still logged in. The cookie IS re-read every request, so it
should work regardless — but tell them to sign out (or clear `PHPSESSID`) and
retry to remove doubt. See the note in `includes/auth.php`.

## Stage 3 — upload bypass to RCE

| # | Where | What it says | Leads to |
|---|---|---|---|
| 9  | Upload form help text | "Accepted: JPG, JPEG, GIF, PNG, BMP" | image extensions only — the payload must ride inside a real image |
| 10 | Rejection: "not a valid image" | fires on a bare-tag file | reveals a real decode (GD) check → must start from a genuine image |
| 11 | Rejection: "appears to contain server code" | fires on `<?php` | a *string* scan → what other PHP tag is there? (`<?=`) |
| 12 | Rejection: "filename is not permitted" | fires on any `.php` in the name | can't sneak an executable extension into the name |
| 13 | Upload success page **and** `/admin.php` list | render the file as a thumbnail `<img src="/uploads/<random>.<ext>">` — the path is **not** a label or link, it lives only in the page source / Network tab (the thumbnail renders broken, since the dir executes images) | reading view-source (or the Network tab) yields the exact randomised `/uploads/<name>` URL — a deliberately subtle breadcrumb; indexing is off |

---

## Rabbit-hole signposts (deliberate misdirection)

These are meant to *attract* attention and waste it. Track how long students
spend here; it is a good measure of how carefully they read.

| Where | Looks like | Why it's a dead end |
|---|---|---|
| `/tools.php` ping | command injection (it really runs `ping`!) | `\A…\z` allowlist + `escapeshellarg()`; every payload logged to `diag_queue` |
| `/dashboard.php?q=` | reflected SQLi | bound prepared statement, emulation off |
| `/dashboard.php?view=` | LFI / path traversal | fixed allowlist keyed by the param; request never reaches a path |
| `/backup-old/` (footer comment `MWS-407`) | forgotten backup dir | exists, empty, returns 403 |
| `svc_dms` account in `/admin.php` | crackable service creds | no password path in this box; pure set dressing |

## The pre-launch checklist (in the dev page footer HTML comment)

A single comment block ties the whole story together and doubles as signposting:

```
[ ] MWS-402  disable self-service registration   -> Stage 2a is open
[ ] MWS-407  purge /backup-old/                   -> rabbit hole
[ ] MWS-412  repoint status widget off staging    -> Stage 1 breadcrumb #2
[x] MWS-418  CSRF tokens on auth forms            -> why those forms are NOT a way in
```
