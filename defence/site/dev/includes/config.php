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
const UPLOAD_MAX  = 500000;   // 500 KB -- page scans are small

/**
 * Accepted document extensions.
 *
 * The rollout only ever needed page scans and diagrams, so the DMS accepts
 * raster image formats. Validation is by extension allowlist, plus a real
 * image-decode check (GD) and a content scan -- see upload.php.
 */
const UPLOAD_ALLOWED_EXT = ['jpg', 'jpeg', 'gif', 'png', 'bmp'];

// --- Diagnostics tool -------------------------------------------------------
const DIAG_PING_BIN       = '/usr/bin/ping';
const DIAG_PING_COUNT     = 3;
const DIAG_PING_TIMEOUT   = 2;    // seconds, per probe
const DIAG_RATE_SECONDS   = 3;    // minimum gap between runs, per account
const DIAG_MAX_HOST_LEN   = 253;  // RFC 1035 maximum FQDN length
