<?php
/**
 * Siwang Document Control — authentication and session handling.
 *
 * =========================================================================
 * LAB NOTE — this file contains the Stage 2 vulnerability.
 * (Not served over HTTP; see the includes/ deny rule in the vhost.)
 *
 * restore_from_remember_cookie() deserializes an attacker-controlled cookie
 * and then trusts the ROLE carried by the resulting object. Forging an admin
 * session is a matter of flipping one string inside the serialized blob.
 *
 * Note the allowed_classes restriction on the unserialize() call. That is
 * there on purpose and it is not a mistake in the lab design:
 *
 *   - It blocks POP gadget chains. Without it, any class reachable at that
 *     point with a __wakeup() or __destruct() becomes an object-injection
 *     primitive, and a student could get file write or code execution here --
 *     skipping Stage 3 entirely and defeating the "exactly one path" rule.
 *
 *   - It is realistic. Half-applying the PHP 7 unserialize() hardening advice
 *     is exactly what real codebases do.
 *
 *   - It is the actual lesson. allowed_classes stops gadget chains; it does
 *     NOT make unserialize() of untrusted input safe, because the *contents*
 *     of the permitted object are still entirely attacker-controlled. This
 *     box exists to make that distinction land.
 *
 * Do not remove the restriction to make the bug "more real". It is already
 * real; removing it just adds unintended paths.
 * =========================================================================
 */

declare(strict_types=1);

require_once __DIR__ . '/config.php';
require_once __DIR__ . '/db.php';
require_once __DIR__ . '/User.php';

const REMEMBER_COOKIE = 'siwang_remember';
const REMEMBER_TTL    = 1209600;   // 14 days

/**
 * Start the session and, if the visitor has no active session but does carry a
 * "keep me signed in" cookie, rehydrate their account from it.
 */
function session_boot(): void
{
    if (session_status() !== PHP_SESSION_ACTIVE) {
        session_set_cookie_params([
            'lifetime' => 0,
            'path'     => '/',
            'httponly' => true,
            'samesite' => 'Lax',
        ]);
        session_start();
    }

    restore_from_remember_cookie();
}

/**
 * "Keep me signed in."
 *
 * Carried over from the 2014 intranet codebase. Storing the account object in
 * the cookie means we can restore the session without a database round trip on
 * every request, which mattered a great deal more on the old hardware than it
 * does now.
 */
function restore_from_remember_cookie(): void
{
    /*
     * The cookie is re-read on every request rather than only when the session
     * is empty, so that a role change made in the staff directory takes effect
     * on the user's next page load instead of after their next sign-in.
     *
     * LAB NOTE: this ordering is deliberate. If the cookie were only consulted
     * when $_SESSION['uid'] is unset, a student who tampers with it while still
     * signed in would see nothing happen at all -- a dead end with no feedback,
     * which is the worst possible failure mode in a teaching box. As written,
     * editing the cookie and reloading any page works immediately.
     */
    if (empty($_COOKIE[REMEMBER_COOKIE]) || !is_string($_COOKIE[REMEMBER_COOKIE])) {
        return;
    }

    // Some proxies rewrite '+' in a cookie value to a space. Put it back
    // before decoding, or the payload fails to parse for those clients.
    $encoded = strtr($_COOKIE[REMEMBER_COOKIE], ' ', '+');

    $raw = base64_decode($encoded, true);
    if ($raw === false) {
        return;
    }

    $account = @unserialize($raw, ['allowed_classes' => ['User']]);

    if (!($account instanceof User)) {
        return;
    }

    $_SESSION['uid']      = (int) $account->id;
    $_SESSION['username'] = (string) $account->username;
    $_SESSION['role']     = (string) $account->role;
}

/**
 * Establish a logged-in session for a freshly authenticated account row.
 */
function login_user(array $row, bool $remember): void
{
    // New session id on privilege change, so a pre-set session id cannot be
    // ridden into an authenticated session.
    session_regenerate_id(true);

    $_SESSION['uid']      = (int) $row['id'];
    $_SESSION['username'] = (string) $row['username'];
    $_SESSION['role']     = (string) $row['role'];

    $stmt = db()->prepare('UPDATE users SET last_login_at = NOW() WHERE id = :id');
    $stmt->execute([':id' => (int) $row['id']]);

    if (!$remember) {
        return;
    }

    $account = new User((int) $row['id'], (string) $row['username'], (string) $row['role']);

    setcookie(REMEMBER_COOKIE, base64_encode(serialize($account)), [
        'expires'  => time() + REMEMBER_TTL,
        'path'     => '/',
        // The status widget on the marketing site needs to read this to decide
        // whether to show the staff banner, so it cannot be httpOnly.
        'httponly' => false,
        'samesite' => 'Lax',
    ]);
}

/**
 * End the session and drop the persistent cookie with it.
 */
function logout_user(): void
{
    $_SESSION = [];

    if (ini_get('session.use_cookies')) {
        $p = session_get_cookie_params();
        setcookie(session_name(), '', time() - 42000, $p['path'], $p['domain'], $p['secure'], $p['httponly']);
    }

    setcookie(REMEMBER_COOKIE, '', ['expires' => time() - 42000, 'path' => '/']);

    session_destroy();
}

function is_logged_in(): bool
{
    return isset($_SESSION['uid']);
}

function is_admin(): bool
{
    return ($_SESSION['role'] ?? '') === 'admin';
}

function current_username(): string
{
    return (string) ($_SESSION['username'] ?? '');
}

function current_uid(): int
{
    return (int) ($_SESSION['uid'] ?? 0);
}

/**
 * Fetch the signed-in account's canonical database row.
 *
 * Used by the pages that display account details. Note that this reads the
 * REAL role from the database, which is why the profile page can disagree with
 * the navigation after a forged session -- an intentional tell for students who
 * are paying attention, and a talking point for the debrief.
 */
function current_user_row(): ?array
{
    if (!is_logged_in()) {
        return null;
    }

    $stmt = db()->prepare(
        'SELECT id, username, email, role, created_at, last_login_at
           FROM users WHERE id = :id'
    );
    $stmt->execute([':id' => current_uid()]);

    $row = $stmt->fetch();
    return $row === false ? null : $row;
}

function require_login(): void
{
    if (!is_logged_in()) {
        header('Location: /login.php');
        exit;
    }
}

/**
 * Gate an admin-only page.
 *
 * This is a real server-side check on every request, not merely a hidden
 * navigation item: a low-privilege account that types /upload.php directly
 * gets a 403 and nothing else. Without the Stage 2 escalation there is
 * genuinely nothing to exploit here.
 */
function require_admin(): void
{
    require_login();

    if (!is_admin()) {
        http_response_code(403);
        require __DIR__ . '/../partials/403.php';
        exit;
    }
}
