<?php
/**
 * Siwang Document Control — database access.
 *
 * Every query in this application goes through a prepared statement obtained
 * from here. There is no string concatenation of user input into SQL anywhere
 * in the codebase; the search box on the dashboard looks injectable and is not.
 *
 * ATTR_EMULATE_PREPARES is false on purpose, so placeholders are bound by the
 * MySQL server rather than interpolated client-side by PDO. With emulation on,
 * exotic charset tricks can occasionally still bite; with it off they cannot.
 */

declare(strict_types=1);

require_once __DIR__ . '/config.php';

function db(): PDO
{
    static $pdo = null;

    if ($pdo instanceof PDO) {
        return $pdo;
    }

    $dsn = sprintf('mysql:host=%s;dbname=%s;charset=utf8mb4', DB_HOST, DB_NAME);

    try {
        $pdo = new PDO($dsn, DB_USER, DB_PASS, [
            PDO::ATTR_ERRMODE            => PDO::ERRMODE_EXCEPTION,
            PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC,
            PDO::ATTR_EMULATE_PREPARES   => false,
        ]);
    } catch (PDOException $e) {
        // display_errors is off in the pool config, so an uncaught exception
        // would render a blank page. Catch it here and log the detail rather
        // than letting the DSN, credentials or a stack trace reach the browser.
        error_log('siwang-dev: database connection failed: ' . $e->getMessage());
        http_response_code(503);
        exit('Service temporarily unavailable.');
    }

    return $pdo;
}
