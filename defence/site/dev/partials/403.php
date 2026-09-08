<?php
/**
 * Rendered by require_admin() when a non-administrator reaches an admin page.
 *
 * This is a real server-side refusal, not a hidden menu item. Nothing on the
 * far side of it is reachable without an administrative session.
 *
 * Not reachable directly over HTTP (partials/ is denied in the vhost).
 */
declare(strict_types=1);

page_header('Not permitted');
?>

<div class="deny">
  <div class="code">403</div>
  <h1>You do not have access to this screen</h1>
  <p>
    Document upload and administration are restricted to accounts with the
    administrator role during the staging phase.
  </p>
  <p class="muted small">
    If you believe you should have access, contact the IT helpdesk quoting your
    username.
  </p>
  <p style="margin-top:1.6rem;">
    <a class="btn btn-quiet" href="/dashboard.php">Back to the register</a>
  </p>
</div>

<?php page_footer(); ?>
