-- ============================================================================
--  Siwang lab -- FULLY MANUAL database build.
--
--  Use this when the shell installers (setup.sh / reinit.sh) are misbehaving
--  and you just want a working database. It is self-contained: schema, the
--  application user, grants, and seed data, in one paste.
--
--    sudo mysql < db/manual-setup.sql
--  or open `sudo mysql` and paste the whole file.
--
--  >>> BEFORE RUNNING <<<
--  1. Replace the password on the CREATE USER line below (search CHANGE_ME).
--  2. Put the SAME password into /var/www/dev/includes/config.php, replacing
--     the DB_PASS value ('__DB_PASSWORD__' if it was never substituted):
--        sudo sed -i "s/__DB_PASSWORD__/<your password>/" \
--             /var/www/dev/includes/config.php
--
--  Safe to re-run: it drops and rebuilds everything.
--
--  NOTE on the seeded accounts (mika / emma / svc_dms): their password_hash is
--  a placeholder, so you CANNOT log in as them -- and you never need to. No
--  intended path in this lab authenticates as a seeded user; they exist only to
--  populate the account list and own the sample documents. If you want a real,
--  loginnable password for one of them, generate a hash and UPDATE the row:
--     php -r 'echo password_hash("SomePassword", PASSWORD_BCRYPT), "\n";'
--     UPDATE siwang_dev.users SET password_hash='<paste>' WHERE username='mika';
-- ============================================================================

DROP DATABASE IF EXISTS siwang_dev;
CREATE DATABASE siwang_dev CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
USE siwang_dev;

-- ---- schema ----------------------------------------------------------------
CREATE TABLE users (
    id            INT UNSIGNED NOT NULL AUTO_INCREMENT,
    username      VARCHAR(32)  NOT NULL,
    email         VARCHAR(190) DEFAULT NULL,
    password_hash VARCHAR(255) NOT NULL,
    role          ENUM('user','admin') NOT NULL DEFAULT 'user',
    created_at    DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    last_login_at DATETIME     DEFAULT NULL,
    PRIMARY KEY (id),
    UNIQUE KEY uq_users_username (username)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE documents (
    id            INT UNSIGNED NOT NULL AUTO_INCREMENT,
    owner_id      INT UNSIGNED NOT NULL,
    title         VARCHAR(190) NOT NULL,
    original_name VARCHAR(255) NOT NULL,
    stored_name   VARCHAR(255) NOT NULL,
    mime_reported VARCHAR(100) NOT NULL,
    mime_detected VARCHAR(100) NOT NULL,
    size_bytes    INT UNSIGNED NOT NULL,
    uploaded_at   DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (id),
    KEY idx_documents_owner (owner_id),
    KEY idx_documents_uploaded (uploaded_at),
    CONSTRAINT fk_documents_owner
        FOREIGN KEY (owner_id) REFERENCES users (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE diag_queue (
    id         BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    user_id    INT UNSIGNED DEFAULT NULL,
    host_input VARCHAR(512) NOT NULL,
    accepted   TINYINT(1)   NOT NULL DEFAULT 0,
    created_at DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (id),
    KEY idx_diag_user_time (user_id, created_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ---- application database user ---------------------------------------------
-- Least privilege: SELECT/INSERT/UPDATE only, bound to loopback, no FILE (so no
-- SELECT ... INTO OUTFILE), no DELETE/DROP/ALTER.
--
--   >>> CHANGE_ME: set a password here, and match it in config.php <<<
DROP USER IF EXISTS 'siwang_app'@'127.0.0.1';
CREATE USER 'siwang_app'@'127.0.0.1' IDENTIFIED BY 'ChangeMe_SiwangApp_2026';
GRANT SELECT, INSERT, UPDATE ON siwang_dev.* TO 'siwang_app'@'127.0.0.1';
FLUSH PRIVILEGES;

-- ---- seeded accounts -------------------------------------------------------
-- Explicit ids so the document seed below can reference them without a join.
-- password_hash is a valid-format bcrypt placeholder; seeded logins are
-- disabled by design (see the note at the top of this file).
INSERT INTO users (id, username, email, password_hash, role, created_at) VALUES
  (1, 'mika',    'mika@siwang-trading.example', '$2y$10$abcdefghijklmnopqrstuvwxyz0123456789abcdefghijklmnopq', 'admin', '2024-09-15 08:30:00'),
  (2, 'emma',    'emma@siwang-trading.example', '$2y$10$abcdefghijklmnopqrstuvwxyz0123456789abcdefghijklmnopq', 'user',  '2024-09-15 08:41:00'),
  (3, 'svc_dms', NULL,                          '$2y$10$abcdefghijklmnopqrstuvwxyz0123456789abcdefghijklmnopq', 'user',  '2024-09-16 13:05:00');

-- ---- sample documents ------------------------------------------------------
INSERT INTO documents (owner_id, title, original_name, stored_name, mime_reported, mime_detected, size_bytes, uploaded_at) VALUES
  (1, 'Bill of Lading template v4',            'bol-template-v4.pdf',       'bol-template-v4.pdf',       'application/pdf', 'application/pdf', 184320, '2024-10-02 09:14:22'),
  (1, 'Port of Singapore - berth schedule Q4', 'psa-berth-q4.pdf',          'psa-berth-q4.pdf',          'application/pdf', 'application/pdf', 512004, '2024-10-11 16:40:07'),
  (1, 'Warehouse floor plan (Tuas)',           'tuas-floorplan.png',        'tuas-floorplan.png',        'image/png',       'image/png',       733112, '2024-10-18 11:02:55'),
  (2, 'Customs declaration - worked example',  'customs-decl-example.pdf',  'customs-decl-example.pdf',  'application/pdf', 'application/pdf',  96280, '2024-10-24 14:31:19'),
  (1, 'DMS migration runbook (DRAFT)',         'dms-migration-runbook.pdf', 'dms-migration-runbook.pdf', 'application/pdf', 'application/pdf', 271455, '2024-11-08 17:55:41'),
  (2, 'Scanned delivery note 88214',           'dn-88214.jpg',              'dn-88214.jpg',              'image/jpeg',      'image/jpeg',      421900, '2024-11-19 08:22:03');

-- ---- diagnostics history ---------------------------------------------------
INSERT INTO diag_queue (user_id, host_input, accepted, created_at) VALUES
  (1, '10.20.0.14',           1, '2024-11-21 10:03:11'),
  (1, 'psa-edi.example.com',  1, '2024-11-21 10:03:48'),
  (1, '10.20.0.1',            1, '2024-11-21 10:05:02'),
  (2, 'dms-staging.internal', 1, '2024-11-22 09:41:37');

-- ---- confirmation ----------------------------------------------------------
SELECT 'users' AS tbl, COUNT(*) AS rows_ FROM users
UNION ALL SELECT 'documents', COUNT(*) FROM documents
UNION ALL SELECT 'diag_queue', COUNT(*) FROM diag_queue;
