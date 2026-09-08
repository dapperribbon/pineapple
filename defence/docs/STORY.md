# Engagement brief — Siwang Trading Co.

*Hand this to students as the scenario. It contains no spoilers.*

---

## Client

**Siwang Trading Co. (Pte) Ltd** is a freight-forwarding and customs-brokerage
firm in Singapore — thirty-one staff, thirty years in business, one office. They
move sea and air cargo and handle the customs paperwork that goes with it.

After a warehouse fire in 2011 destroyed part of their paper archive, the
company became unusually serious about document management. They are currently
part-way through a project to move roughly 1.4 million scanned pages into a
single **document-control system (DMS)**, built for them by an external
contractor, **Meridian Web Solutions**.

## Why we were called

Siwang's public website is `siwang.duckdns.org`. During a light-touch external
review, the DMS project came up: the contractor stood up a **staging portal**
for it during user-acceptance testing, and nobody is entirely sure it was ever
locked down. The Meridian contract concluded at the end of November 2024 with
several hardening items still open.

You have been asked to assess the externally reachable footprint of the DMS
rollout and determine whether an outside attacker could reach or manipulate the
company's documents.

## Scope

- **In scope:** the web presence on the lab box and anything reachable from it.
- **Goal:** demonstrate initial access — show that an outside attacker can go
  from the public website to command execution on the server.
- Privilege escalation beyond that initial foothold is the subject of a
  follow-up engagement and is out of scope for this exercise.

## Rules of engagement

- Work only against the lab box you were given.
- The public brochure site is a normal marketing site. Assume it is in scope to
  *read* but do not expect it to be the way in by itself.
- Automated scanning is fine. Be aware the client's junior staff use this box,
  so a couple of the tools on it are real and do real things — do not assume
  everything that looks dangerous is a way in.

## What you are handed

- The box's IP address.
- Nothing else. No credentials, no hostnames beyond the public one.

## What "done" looks like

A shell on the box, and a short write-up of the path you took to get it: how you
found the application, how you got administrative access to it, and how you
turned that into code execution. Note any dead ends you burned time on — the
client will want to know which of their half-finished features look more
dangerous than they are.
