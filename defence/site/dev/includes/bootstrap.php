<?php
/**
 * Siwang Document Control — front-controller bootstrap.
 *
 * Every page in the application starts with:
 *
 *     require_once __DIR__ . '/includes/bootstrap.php';
 *
 * Include order matters: User must be defined before auth.php can resolve it
 * during deserialization, and the session must be started before csrf.php
 * touches $_SESSION.
 *
 * There is no autoloader here, and that is deliberate. An autoloader would
 * make every class in the codebase reachable from the unserialize() call in
 * auth.php, which is precisely what the lab is trying to avoid.
 */

declare(strict_types=1);

require_once __DIR__ . '/config.php';
require_once __DIR__ . '/db.php';
require_once __DIR__ . '/User.php';
require_once __DIR__ . '/auth.php';
require_once __DIR__ . '/csrf.php';
require_once __DIR__ . '/layout.php';

session_boot();

/**
 * Escape for HTML output. Used on every single value this application prints.
 */
function e($value): string
{
    return htmlspecialchars((string) $value, ENT_QUOTES | ENT_SUBSTITUTE, 'UTF-8');
}

/**
 * Read a scalar string out of $_GET / $_POST.
 *
 * PHP 8 raises a TypeError if you cast an array to string, so `?q[]=x` against
 * a naive `(string) $_GET['q']` produces a 500. That is not a vulnerability,
 * but it is an inconsistency students will find and chase, and a stack trace in
 * the error log is not the rabbit hole we want. Anything that is not a plain
 * string is treated as absent.
 */
function req_str(array $source, string $key, string $default = ''): string
{
    $value = $source[$key] ?? null;
    return is_string($value) ? $value : $default;
}

/**
 * Human-readable byte size for the document list.
 */
function human_bytes(int $bytes): string
{
    if ($bytes < 1024) {
        return $bytes . ' B';
    }
    if ($bytes < 1048576) {
        return round($bytes / 1024, 1) . ' KB';
    }
    return round($bytes / 1048576, 1) . ' MB';
}
