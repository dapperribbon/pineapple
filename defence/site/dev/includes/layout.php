<?php
/**
 * Siwang Document Control — shared chrome.
 *
 * page_header() / page_footer() wrap every screen. The navigation is built
 * from the session role, but note that hiding a nav item is presentation only:
 * the admin pages call require_admin() themselves on every request.
 */

declare(strict_types=1);

function nav_item(string $href, string $label, string $active, string $key): string
{
    $cls = ($active === $key) ? ' class="is-current"' : '';
    return '<a href="' . $href . '"' . $cls . '>' . $label . '</a>';
}

function page_header(string $title, string $active = ''): void
{
    $logged = is_logged_in();
    $admin  = is_admin();
    ?><!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="robots" content="noindex, nofollow">
<title><?= htmlspecialchars($title, ENT_QUOTES, 'UTF-8') ?> — Siwang DMS (staging)</title>
<link rel="stylesheet" href="/assets/css/app.css">
</head>
<body>

<div class="env-bar">
  <span class="env-tag">STAGING</span>
  <span>Siwang Document Control <?= htmlspecialchars(APP_RELEASE, ENT_QUOTES, 'UTF-8') ?> — not for production data</span>
</div>

<header class="app-head">
  <div class="wrap head-inner">
    <a class="brand" href="<?= $logged ? '/dashboard.php' : '/login.php' ?>">
      <span class="brand-mark">SW</span>
      <span class="brand-text">Document Control</span>
    </a>

    <?php if ($logged): ?>
      <nav class="app-nav">
        <?= nav_item('/dashboard.php', 'Dashboard',   $active, 'dashboard') ?>
        <?= nav_item('/tools.php',     'Diagnostics', $active, 'tools') ?>
        <?= nav_item('/profile.php',   'Profile',     $active, 'profile') ?>
        <?php if ($admin): ?>
          <?= nav_item('/upload.php', 'Document Upload', $active, 'upload') ?>
          <?= nav_item('/admin.php',  'Administration',  $active, 'admin') ?>
        <?php endif; ?>
      </nav>

      <div class="who">
        <span class="who-name"><?= htmlspecialchars(current_username(), ENT_QUOTES, 'UTF-8') ?></span>
        <?php if ($admin): ?><span class="chip chip-admin">admin</span><?php endif; ?>
        <a class="signout" href="/logout.php">Sign out</a>
      </div>
    <?php endif; ?>
  </div>
</header>

<main class="wrap app-main">
<?php
}

function page_footer(): void
{
    ?>
</main>

<footer class="app-foot">
  <div class="wrap">
    <p>
      Siwang Document Control — staging environment.
      Built by Meridian Web Solutions Pte Ltd under MWS-2024-118.
      Issues to <a href="mailto:helpdesk@siwang-trading.example">helpdesk@siwang-trading.example</a>.
    </p>
    <!--
      Pre-launch checklist (MWS-2024-118), outstanding items:
        [ ] MWS-402  disable self-service registration before handover
        [ ] MWS-407  purge /backup-old/ from the docroot
        [ ] MWS-412  repoint the marketing site status widget away from staging
        [x] MWS-418  CSRF tokens on auth forms
    -->
  </div>
</footer>

</body>
</html>
<?php
}
