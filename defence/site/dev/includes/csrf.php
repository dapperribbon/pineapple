<?php
/**
 * Siwang Document Control — CSRF tokens.
 *
 * Applied to the login, registration and profile forms.
 *
 * Deliberately NOT applied to upload.php or tools.php. In-world that is an
 * oversight by the contractor (those two screens were added late, after the
 * security review). In lab terms it keeps Stage 3 scriptable with a plain
 * multipart POST and keeps the diagnostics rabbit hole easy to poke at, which
 * is what makes students spend time on it.
 */

declare(strict_types=1);

function csrf_token(): string
{
    if (empty($_SESSION['csrf'])) {
        $_SESSION['csrf'] = bin2hex(random_bytes(32));
    }
    return $_SESSION['csrf'];
}

function csrf_field(): string
{
    return '<input type="hidden" name="csrf" value="'
         . htmlspecialchars(csrf_token(), ENT_QUOTES, 'UTF-8')
         . '">';
}

function csrf_check(): void
{
    $sent = $_POST['csrf'] ?? '';

    if (!is_string($sent) || !hash_equals($_SESSION['csrf'] ?? '', $sent)) {
        http_response_code(400);
        exit('Invalid or expired form token. Please reload the page and try again.');
    }
}
