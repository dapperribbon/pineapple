<?php
/**
 * Siwang Document Control — document viewer.
 *
 * Streams a stored upload with its correct image Content-Type, so legitimate
 * images render in the browser instead of being handed to the PHP interpreter.
 *
 * Why this exists: the uploads directory maps image extensions to PHP-FPM (the
 * Stage 3 misconfiguration), so fetching /uploads/<name>.gif *executes* it. A
 * clean image fetched that way comes back as text/html garbage. This viewer
 * READS the bytes with readfile() (it never executes them) and sends the right
 * image header, so staff can actually look at uploaded documents.
 *
 * It is NOT an alternate exploit path:
 *   - admin-only (require_admin);
 *   - the name is basename()'d and must match the exact stored-name shape,
 *     then confirmed to resolve inside UPLOAD_DIR -- no traversal;
 *   - readfile() streams bytes, it does not interpret them.
 *
 * The raw /uploads/<name> URL still exists and still executes -- that remains
 * the intended Stage 3 vector, and the admin listing still shows that raw path.
 */

declare(strict_types=1);

require_once __DIR__ . '/includes/bootstrap.php';

require_admin();

$name = basename(str_replace('\\', '/', req_str($_GET, 'f')));

// Stored names are bin2hex(random_bytes(8)) + '.' + a validated image ext.
if (!preg_match('/\A[a-f0-9]{16}\.(jpg|jpeg|gif|png|bmp)\z/', $name)) {
    http_response_code(404);
    exit('Not found.');
}

$path = UPLOAD_DIR . '/' . $name;
$real = realpath($path);

// Must resolve to a real file physically inside the uploads directory.
if ($real === false || strpos($real, realpath(UPLOAD_DIR) . DIRECTORY_SEPARATOR) !== 0 || !is_file($real)) {
    http_response_code(404);
    exit('Not found.');
}

$ext   = strtolower(pathinfo($name, PATHINFO_EXTENSION));
$types = [
    'jpg'  => 'image/jpeg',
    'jpeg' => 'image/jpeg',
    'gif'  => 'image/gif',
    'png'  => 'image/png',
    'bmp'  => 'image/bmp',
];

header('Content-Type: ' . ($types[$ext] ?? 'application/octet-stream'));
header('Content-Length: ' . filesize($real));
// Never let the browser second-guess the type, and never treat it as a page.
header('X-Content-Type-Options: nosniff');
header('Content-Disposition: inline; filename="' . $name . '"');

readfile($real);
