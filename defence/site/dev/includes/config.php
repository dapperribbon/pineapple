<?php
/**
 * Siwang Document Control — staging configuration
 *
 * Built for Siwang Trading Co. by Meridian Web Solutions Pte Ltd.
 * Statement of work MWS-2024-118. Contract concluded 2024-11-30.
 *
 * This is the staging deployment. It was stood up during UAT and was never
 * torn down.
 */

declare(strict_types=1);

// --- Database ---------------------------------------------------------------
// DB_PASS is substituted by install/install.sh at provisioning time; the
// literal placeholder below should never survive a real deployment.
const DB_HOST = '127.0.0.1';
const DB_NAME = 'siwang_dev';
const DB_USER = 'siwang_app';
const DB_PASS = '__DB_PASSWORD__';

// --- Application ------------------------------------------------------------
const APP_NAME    = 'Siwang Document Control';
const APP_ENV     = 'staging';
const APP_RELEASE = '0.9.4-rc2';

// --- Uploads ----------------------------------------------------------------
const UPLOAD_DIR  = '/var/www/dev/uploads';
const UPLOAD_URL  = '/uploads';
const UPLOAD_MAX  = 2097152;   // 2 MiB, matched to the FPM pool's limits

/**
 * Accepted document types.
 *
 * The rollout only ever needed scans and diagrams, so the DMS accepts images
 * and PDFs. PDFs are checked but currently rejected by the content sniff on
 * some scanner output, so operations were told to upload page images instead.
 */
const UPLOAD_ALLOWED_MIME = ['image/gif', 'image/png', 'image/jpeg'];

// --- Diagnostics tool -------------------------------------------------------
const DIAG_PING_BIN       = '/usr/bin/ping';
const DIAG_PING_COUNT     = 3;
const DIAG_PING_TIMEOUT   = 2;    // seconds, per probe
const DIAG_RATE_SECONDS   = 3;    // minimum gap between runs, per account
const DIAG_MAX_HOST_LEN   = 253;  // RFC 1035 maximum FQDN length
