<?php
/**
 * Siwang Document Control — dashboard.
 *
 * Two deliberate rabbit holes live on this page.
 *
 * 1. ?view=  looks like a local file include. It is a fixed lookup table:
 *    the request value is only ever used as an ARRAY KEY, and the value that
 *    reaches include() comes from this file, never from the request. There is
 *    no path traversal here and no amount of ../ will produce one.
 *
 * 2. ?q=  looks like a SQL injection. The value is echoed back in the
 *    "no results" message (HTML-escaped) which makes it feel reflective, but
 *    the query is a bound prepared statement with emulation disabled. sqlmap
 *    finds nothing, correctly.
 */

declare(strict_types=1);

require_once __DIR__ . '/includes/bootstrap.php';

require_login();

/*
 * View resolution. The request never contributes a path fragment -- it selects
 * a key, and an unknown key silently falls back to 'home'.
 */
$views = [
    'home'   => 'home.php',
    'recent' => 'recent.php',
    'help'   => 'help.php',
];

$requestedView = req_str($_GET, 'view', 'home');
$viewKey       = isset($views[$requestedView]) ? $requestedView : 'home';
$partial       = $views[$viewKey];

/*
 * Document search. Bound parameter; the wildcards are added in PHP so the
 * user's own % and _ characters are data, not pattern syntax.
 */
$q = trim(req_str($_GET, 'q'));

if ($q !== '') {
    $stmt = db()->prepare(
        'SELECT d.id, d.title, d.original_name, d.stored_name, d.mime_detected,
                d.size_bytes, d.uploaded_at, u.username AS owner
           FROM documents d
           JOIN users u ON u.id = d.owner_id
          WHERE d.title LIKE :needle OR d.original_name LIKE :needle
          ORDER BY d.uploaded_at DESC
          LIMIT 100'
    );
    $stmt->execute([':needle' => '%' . str_replace(['\\', '%', '_'], ['\\\\', '\%', '\_'], $q) . '%']);
} else {
    $stmt = db()->prepare(
        'SELECT d.id, d.title, d.original_name, d.stored_name, d.mime_detected,
                d.size_bytes, d.uploaded_at, u.username AS owner
           FROM documents d
           JOIN users u ON u.id = d.owner_id
          ORDER BY d.uploaded_at DESC
          LIMIT 100'
    );
    $stmt->execute();
}

$documents = $stmt->fetchAll();

$totals = db()->query(
    'SELECT (SELECT COUNT(*) FROM documents) AS docs,
            (SELECT COUNT(*) FROM users)     AS users,
            (SELECT COALESCE(SUM(size_bytes), 0) FROM documents) AS bytes'
)->fetch();

page_header('Dashboard', 'dashboard');
?>

<div class="page-head">
  <h1>Document register</h1>
  <p>Signed in as <?= e(current_username()) ?>. Staging data only.</p>
</div>

<nav class="app-nav" style="margin-bottom:1.4rem;">
  <a href="/dashboard.php?view=home"<?= $viewKey === 'home' ? ' class="is-current"' : '' ?>>All documents</a>
  <a href="/dashboard.php?view=recent"<?= $viewKey === 'recent' ? ' class="is-current"' : '' ?>>Recent activity</a>
  <a href="/dashboard.php?view=help"<?= $viewKey === 'help' ? ' class="is-current"' : '' ?>>Using the register</a>
</nav>

<?php require __DIR__ . '/partials/' . $partial; ?>

<?php page_footer(); ?>
