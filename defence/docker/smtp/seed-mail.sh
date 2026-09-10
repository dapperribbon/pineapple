#!/bin/sh
# Siwang CTF lab -- seed chrysanta's mailbox.
#
# Usage: seed-mail.sh <maddy.conf> <account>
#
# Drops a pile of ordinary staff email into the INBOX (and a couple into Sent)
# so the ONE message that matters -- an IT "password reset" notice leaking the
# SSH password for her shell account on the operations host -- is a needle in a
# realistic haystack. Every message is marked \Seen so the needle is not simply
# "the only unread mail".
#
# The reset password (BenMyG0AT) and the shell username (chrysanta) must match
# what install/privesc-host.sh provisions on the HOST. Keep them in sync.

set -eu

CONF="$1"
ACCT="$2"
MADDY="/bin/maddy --config ${CONF}"

# add <mailbox> <internal-date> <<'EOF' ... EOF   (message read from stdin)
add() {
    _box="$1"; _date="$2"
    ${MADDY} imap-msgs add -f Seen -d "${_date}" "${ACCT}" "${_box}" >/dev/null
}

# ---------------------------------------------------------------------------
add INBOX 2024-09-18T08:05:00Z <<'EOF'
From: HR Announcements <hr@siwang-trading.example>
To: all-staff@siwang-trading.example
Subject: Welcome to the new document control portal (staging)
Date: Wed, 18 Sep 2024 08:05:00 +0800
Message-ID: <hr-0918-portal@siwang-trading.example>

Hi everyone,

IT are trialling the new Document Control portal this quarter. Please do not
upload live customer paperwork to the staging site yet -- it is for testing
only. Training slots will be circulated next week.

Regards,
Priya (HR)
EOF

add INBOX 2024-09-20T14:22:00Z <<'EOF'
From: Operations <ops@siwang-trading.example>
To: chrysanta@siwang-trading.example
Subject: Berth allocation - MV Tuas Harmony (job 44120)
Date: Fri, 20 Sep 2024 14:22:00 +0800
Message-ID: <ops-44120-berth@siwang-trading.example>

Chrys,

MV Tuas Harmony is now confirmed for Berth 12 on the 24th, 06:00 window. Can
you get the bill of lading scanned into the register before then? The agent
wants the reference by end of week.

Thanks,
Boon
EOF

add INBOX 2024-09-23T09:41:00Z <<'EOF'
From: Finance <finance@siwang-trading.example>
To: chrysanta@siwang-trading.example
Subject: Invoice INV-2024-0912 pending your approval
Date: Mon, 23 Sep 2024 09:41:00 +0800
Message-ID: <fin-0912-approve@siwang-trading.example>

Hi Chrysanta,

Invoice INV-2024-0912 (haulage, Tuas) is sitting in your approval queue. It is
due on the 30th -- please review when you have a moment.

Finance
EOF

add INBOX 2024-09-25T12:15:00Z <<'EOF'
From: Social Committee <social@siwang-trading.example>
To: all-staff@siwang-trading.example
Subject: Lunch & learn Friday - bubble tea on the company
Date: Wed, 25 Sep 2024 12:15:00 +0800
Message-ID: <social-0925-lunch@siwang-trading.example>

Friday 12:30, level 3 pantry. RSVP so we order enough. Bubble tea sponsored by
the ops team who (finally) closed the Q3 backlog. See you there!
EOF

add INBOX 2024-09-27T16:48:00Z <<'EOF'
From: IT Service Desk <helpdesk@siwang-trading.example>
To: all-staff@siwang-trading.example
Subject: Scheduled maintenance - file server reboot Sunday 02:00
Date: Fri, 27 Sep 2024 16:48:00 +0800
Message-ID: <it-0927-maint@siwang-trading.example>

Planned maintenance this Sunday 02:00-03:00. The operations host and file
shares will be briefly unavailable. No action needed on your side.

IT Service Desk
EOF

add INBOX 2024-09-30T10:03:00Z <<'EOF'
From: Boon Hwee <boon@siwang-trading.example>
To: chrysanta@siwang-trading.example
Subject: Re: Berth allocation - MV Tuas Harmony (job 44120)
Date: Mon, 30 Sep 2024 10:03:00 +0800
In-Reply-To: <ops-44120-berth@siwang-trading.example>
References: <ops-44120-berth@siwang-trading.example>
Message-ID: <ops-44120-berth-2@siwang-trading.example>

Got the scan, thanks. Agent has the reference now. Closing the job.
EOF

add INBOX 2024-10-01T11:20:00Z <<'EOF'
From: Meridian Web Solutions <support@meridian-web.example>
To: chrysanta@siwang-trading.example
Subject: Your support ticket MWS-2211 has been updated
Date: Tue, 01 Oct 2024 11:20:00 +0800
Message-ID: <mws-2211-update@siwang-trading.example>

Ticket MWS-2211 ("staging portal shows admin nav to some users") has been
updated by our engineer. Status: investigating. We will follow up.
EOF

add INBOX 2024-10-01T15:37:00Z <<'EOF'
From: Newsletter <news@portwatch.example>
To: chrysanta@siwang-trading.example
Subject: PortWatch Weekly - Singapore throughput up 4.1%
Date: Tue, 01 Oct 2024 15:37:00 +0800
Message-ID: <portwatch-1001@siwang-trading.example>

This week: container throughput up 4.1% YoY, new reefer capacity at Tuas, and
why bunker prices are wobbling. Read online. Unsubscribe any time.
EOF

# --- The needle -------------------------------------------------------------
add INBOX 2024-10-02T09:18:00Z <<'EOF'
From: IT Service Desk <helpdesk@siwang-trading.example>
To: chrysanta@siwang-trading.example
Subject: [Action required] Your shell account password has been reset
Date: Wed, 02 Oct 2024 09:18:00 +0800
Message-ID: <it-1002-reset@siwang-trading.example>

Hi Chrysanta,

As requested, we have reset the password for your Unix login on the operations
host (SSH). Your account name is unchanged:

    login:    chrysanta
    password: BenMyG0AT

Please sign in over SSH and change it at your earliest convenience -- this is a
temporary password and company policy requires you to rotate it on first use.
If you did not request this reset, contact the service desk immediately.

Regards,
Nathan
IT Service Desk
EOF

add INBOX 2024-10-02T09:52:00Z <<'EOF'
From: IT Service Desk <helpdesk@siwang-trading.example>
To: all-staff@siwang-trading.example
Subject: Reminder - password policy and phishing awareness
Date: Wed, 02 Oct 2024 09:52:00 +0800
Message-ID: <it-1002-policy@siwang-trading.example>

A reminder that passwords must be at least 12 characters and rotated every 90
days. Never reuse your corporate password on external sites. If in doubt about
an email asking for credentials, forward it to the service desk.
EOF

add INBOX 2024-10-03T08:30:00Z <<'EOF'
From: Operations <ops@siwang-trading.example>
To: chrysanta@siwang-trading.example
Subject: Weekly vessel schedule - week 41
Date: Thu, 03 Oct 2024 08:30:00 +0800
Message-ID: <ops-w41-sched@siwang-trading.example>

Attached below (paste): week 41 vessel schedule. Three arrivals, one sailing.
Nothing needs document control until the 8th. Enjoy the quiet week.
EOF

add INBOX 2024-10-03T13:11:00Z <<'EOF'
From: Facilities <facilities@siwang-trading.example>
To: all-staff@siwang-trading.example
Subject: Aircon servicing level 3 - Thursday afternoon
Date: Thu, 03 Oct 2024 13:11:00 +0800
Message-ID: <fac-1003-aircon@siwang-trading.example>

Aircon on level 3 will be serviced Thursday 14:00. It may get warm. Hot-desk on
level 2 if needed.
EOF

# --- A couple of Sent items so the account looks lived-in -------------------
add Sent 2024-09-30T10:10:00Z <<'EOF'
From: chrysanta@siwang-trading.example
To: boon@siwang-trading.example
Subject: Re: Berth allocation - MV Tuas Harmony (job 44120)
Date: Mon, 30 Sep 2024 10:10:00 +0800
In-Reply-To: <ops-44120-berth-2@siwang-trading.example>
References: <ops-44120-berth@siwang-trading.example> <ops-44120-berth-2@siwang-trading.example>
Message-ID: <chrys-44120-reply@siwang-trading.example>

Great, thanks Boon. Scan is DOC-00042 in the register if anyone needs it.
EOF

add Sent 2024-10-02T09:40:00Z <<'EOF'
From: chrysanta@siwang-trading.example
To: helpdesk@siwang-trading.example
Subject: Re: [Action required] Your shell account password has been reset
Date: Wed, 02 Oct 2024 09:40:00 +0800
In-Reply-To: <it-1002-reset@siwang-trading.example>
References: <it-1002-reset@siwang-trading.example>
Message-ID: <chrys-reset-ack@siwang-trading.example>

Thanks Nathan, got it. Will log in and change it after the week 41 schedule is
out.
EOF

echo "==> seeded $(printf '%s' "$ACCT") mailbox (INBOX + Sent)"
