# syntax=docker/dockerfile:1
#
# Siwang CTF lab -- internal mail host (Stage 6 pivot target).
#
# Build context is defence/ (same as the siwang image), so COPY paths are
# docker/smtp/... :
#     docker compose build smtp
#
# THIS IMAGE IS PART OF A DELIBERATELY VULNERABLE LAB. It runs plaintext mail
# with a wordlist-reused password on an internal-only network. Isolated lab
# networks only.
#
# It is a PURE READ TARGET: no sshd, no shell user, no SUID. The student
# authenticates with the password cracked in Stage 5 (reused here) and reads
# one seeded email. The SSH-to-host and root stages live on the HOST, not here.

FROM foxcpp/maddy:0.7

LABEL org.opencontainers.image.title="Siwang CTF lab -- mail host" \
      org.opencontainers.image.description="Internal lab IMAP/SMTP host (maddy). Isolated lab networks only." \
      org.opencontainers.image.licenses="NOASSERTION"

ENV MADDY_HOSTNAME=mail.siwang-trading.example \
    MADDY_DOMAIN=siwang-trading.example \
    MAIL_USER=chrysanta@siwang-trading.example \
    MAIL_PASS=dylan

COPY docker/smtp/maddy.conf    /opt/lab/maddy.conf
COPY docker/smtp/seed-mail.sh  /opt/lab/seed-mail.sh
COPY docker/smtp/entrypoint.sh /opt/lab/entrypoint.sh

# The repo is developed on Windows; strip CR so busybox sh does not choke on the
# scripts (same reasoning as the siwang Dockerfile).
RUN sed -i 's/\r$//' /opt/lab/maddy.conf /opt/lab/seed-mail.sh /opt/lab/entrypoint.sh \
 && chmod 0755 /opt/lab/seed-mail.sh /opt/lab/entrypoint.sh

EXPOSE 143 587

HEALTHCHECK --interval=30s --timeout=5s --start-period=15s --retries=3 \
    CMD nc -z 127.0.0.1 143 || exit 1

ENTRYPOINT ["/opt/lab/entrypoint.sh"]
