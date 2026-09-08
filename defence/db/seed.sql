-- ============================================================================
--  Siwang Document Control (staging)  --  seed data
--
--  Loaded by db/setup.sh AFTER seed_users.php has created the accounts.
--  This file deliberately contains no password material: bcrypt hashes cannot
--  be written by hand, and a wrong hash fails as a silent "invalid password"
--  that is miserable to debug. See db/seed_users.php.
-- ============================================================================

USE siwang_dev;

-- ----------------------------------------------------------------------------
-- Documents already "in the system", so a freshly registered low-privilege
-- student sees a populated dashboard rather than an empty app that looks
-- broken. All of these are inert: the rows exist, the files do not, and
-- download links for them are not rendered.
--
-- The filenames carry the in-world story -- a freight forwarder mid-way
-- through a document-control rollout -- and one of them (the migration
-- runbook) quietly justifies why a staging box has production-shaped data.
-- ----------------------------------------------------------------------------
INSERT INTO documents
    (owner_id, title, original_name, stored_name, mime_reported, mime_detected, size_bytes, uploaded_at)
SELECT u.id, x.title, x.original_name, x.stored_name, x.mime_reported, x.mime_detected, x.size_bytes, x.uploaded_at
FROM (
    SELECT 'Bill of Lading template v4'        AS title,
           'bol-template-v4.pdf'               AS original_name,
           'bol-template-v4.pdf'               AS stored_name,
           'application/pdf'                   AS mime_reported,
           'application/pdf'                   AS mime_detected,
           184320                              AS size_bytes,
           '2024-10-02 09:14:22'               AS uploaded_at,
           'mika'                             AS owner
    UNION ALL SELECT 'Port of Singapore - berth schedule Q4', 'psa-berth-q4.pdf', 'psa-berth-q4.pdf',
           'application/pdf','application/pdf', 512004, '2024-10-11 16:40:07', 'mika'
    UNION ALL SELECT 'Warehouse floor plan (Tuas)', 'tuas-floorplan.png', 'tuas-floorplan.png',
           'image/png','image/png', 733112, '2024-10-18 11:02:55', 'mika'
    UNION ALL SELECT 'Customs declaration - worked example', 'customs-decl-example.pdf', 'customs-decl-example.pdf',
           'application/pdf','application/pdf', 96280, '2024-10-24 14:31:19', 'emma'
    UNION ALL SELECT 'DMS migration runbook (DRAFT)', 'dms-migration-runbook.pdf', 'dms-migration-runbook.pdf',
           'application/pdf','application/pdf', 271455, '2024-11-08 17:55:41', 'mika'
    UNION ALL SELECT 'Scanned delivery note 88214', 'dn-88214.jpg', 'dn-88214.jpg',
           'image/jpeg','image/jpeg', 421900, '2024-11-19 08:22:03', 'emma'
) AS x
JOIN users u ON u.username = x.owner;

-- ----------------------------------------------------------------------------
-- A little history in the diagnostics log, so the tool looks like something
-- that was actually used during UAT rather than a page bolted on for the CTF.
-- All accepted, all boring.
-- ----------------------------------------------------------------------------
INSERT INTO diag_queue (user_id, host_input, accepted, created_at)
SELECT u.id, x.host_input, 1, x.created_at
FROM (
    SELECT '10.20.0.14'          AS host_input, '2024-11-21 10:03:11' AS created_at, 'mika' AS owner
    UNION ALL SELECT 'psa-edi.example.com', '2024-11-21 10:03:48', 'mika'
    UNION ALL SELECT '10.20.0.1',           '2024-11-21 10:05:02', 'mika'
    UNION ALL SELECT 'dms-staging.internal','2024-11-22 09:41:37', 'emma'
) AS x
JOIN users u ON u.username = x.owner;
