-- ============================================================================
--  Siwang Document Control (staging)  --  schema
--  Target: MySQL 8.0 / MariaDB 10.11 on Ubuntu 24.04
--
--  Loaded by db/setup.sh. Safe to re-run: it drops and recreates the schema.
--
--  Note there is no `sessions` table. The app uses PHP's native file-based
--  session handler (scoped by session.save_path in the FPM pool), so session
--  state never touches the database. The only cookie the app writes itself is
--  the deliberately vulnerable "remember me" cookie, which is self-contained.
-- ============================================================================

DROP DATABASE IF EXISTS siwang_dev;
CREATE DATABASE siwang_dev
    CHARACTER SET utf8mb4
    COLLATE utf8mb4_unicode_ci;

USE siwang_dev;

-- ----------------------------------------------------------------------------
-- users
--
-- `role` is an ENUM and is *never* written from request data. Registration
-- hardcodes 'user'; there is no code path anywhere in the app that promotes an
-- account. The Stage 2 escalation does not touch this table at all -- it forges
-- session state, so the attacker acts as an admin without ever becoming one in
-- the database. (Worth pointing out in the debrief: `SELECT * FROM users` after
-- a successful compromise shows nothing unusual.)
-- ----------------------------------------------------------------------------
CREATE TABLE users (
    id            INT UNSIGNED NOT NULL AUTO_INCREMENT,
    username      VARCHAR(32)  NOT NULL,
    email         VARCHAR(190) DEFAULT NULL,
    password_hash VARCHAR(255) NOT NULL,      -- bcrypt, via password_hash()
    role          ENUM('user','admin') NOT NULL DEFAULT 'user',
    created_at    DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    last_login_at DATETIME     DEFAULT NULL,
    PRIMARY KEY (id),
    UNIQUE KEY uq_users_username (username)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ----------------------------------------------------------------------------
-- documents
--
-- `stored_name` is the on-disk basename inside /var/www/dev/uploads and is what
-- admin.php renders as a link. That link is how a student learns the URL of the
-- file they just uploaded -- directory indexing is off, so without it they would
-- be guessing.
-- ----------------------------------------------------------------------------
CREATE TABLE documents (
    id            INT UNSIGNED NOT NULL AUTO_INCREMENT,
    owner_id      INT UNSIGNED NOT NULL,
    title         VARCHAR(190) NOT NULL,
    original_name VARCHAR(255) NOT NULL,
    stored_name   VARCHAR(255) NOT NULL,
    mime_reported VARCHAR(100) NOT NULL,      -- what the client claimed
    mime_detected VARCHAR(100) NOT NULL,      -- image type derived from the validated extension
    size_bytes    INT UNSIGNED NOT NULL,
    uploaded_at   DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (id),
    KEY idx_documents_owner (owner_id),
    KEY idx_documents_uploaded (uploaded_at),
    CONSTRAINT fk_documents_owner
        FOREIGN KEY (owner_id) REFERENCES users (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ----------------------------------------------------------------------------
-- diag_queue
--
-- Backs the "Network Diagnostics" rabbit hole (tools.php). Two jobs:
--
--   1. Rate limiting. The tool really does shell out to /usr/bin/ping, so it
--      needs a throttle -- otherwise a class of 30 students can trivially peg
--      the box, and the tool becomes a traffic-generation primitive.
--   2. Instructor telemetry. Every attempt is logged with `accepted` set to 0
--      or 1, so after a session you can run the query at the bottom of this
--      file and see exactly which injection payloads students tried. That is
--      genuinely the most useful artefact the box produces for a debrief.
-- ----------------------------------------------------------------------------
CREATE TABLE diag_queue (
    id         BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    user_id    INT UNSIGNED DEFAULT NULL,
    host_input VARCHAR(512) NOT NULL,         -- raw, exactly as submitted
    accepted   TINYINT(1)   NOT NULL DEFAULT 0,
    created_at DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (id),
    KEY idx_diag_user_time (user_id, created_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Instructor debrief query -- what did students throw at the ping box?
--
--   SELECT u.username, d.host_input, d.accepted, d.created_at
--     FROM diag_queue d LEFT JOIN users u ON u.id = d.user_id
--    WHERE d.accepted = 0
--    ORDER BY d.created_at DESC;
