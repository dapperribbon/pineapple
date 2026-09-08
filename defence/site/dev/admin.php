<?php
/**
 * Siwang Document Control — administration.
 *
 * Read-only. Lists registered documents and staging accounts.
 *
 * The document table links each stored file at its real URL under /uploads.
 * That link is how a student learns where their uploaded file lives --
 * directory indexing is off on this vhost, so without it they would be
 * guessing at the path. It is a deliberate breadcrumb, not an oversight.
 *
 * `mime_reported` and `mime_detected` are shown side by side. On a normal
 * upload they agree. After a successful Stage 3 bypass the row shows
 * image/gif for both while the filename ends in .phtml -- which is exactly
 * the detection story for the blue-team half of the debrief.
 */

declare(strict_types=1);

require_once __DIR__ . '/includes/bootstrap.php';

require_admin();

$documents = db()->query(
    'SELECT d.id, d.title, d.original_name, d.stored_name, d.mime_reported,
            d.mime_detected, d.size_bytes, d.uploaded_at, u.username AS owner
       FROM documents d
       JOIN users u ON u.id = d.owner_id
      ORDER BY d.uploaded_at DESC, d.id DESC
      LIMIT 200'
)->fetchAll();

$accounts = db()->query(
    'SELECT id, username, email, role, created_at, last_login_at
       FROM users
      ORDER BY id ASC'
)->fetchAll();

$diagnostics = db()->query(
    'SELECT d.host_input, d.accepted, d.created_at, u.username
       FROM diag_queue d
       LEFT JOIN users u ON u.id = d.user_id
      ORDER BY d.created_at DESC, d.id DESC
      LIMIT 15'
)->fetchAll();

page_header('Administration', 'admin');
?>

<div class="page-head">
  <h1>Administration</h1>
  <p>Staging environment — <?= e(APP_RELEASE) ?>.</p>
</div>

<div class="card">
  <h2>Registered documents</h2>

  <?php if ($documents === []): ?>
    <div class="empty">Nothing registered yet.</div>
  <?php else: ?>
    <div class="table-scroll">
      <table class="data">
        <thead>
          <tr>
            <th>Ref</th>
            <th>Title</th>
            <th>Stored as</th>
            <th>Declared</th>
            <th>Detected</th>
            <th>Size</th>
            <th>Owner</th>
            <th>Registered</th>
          </tr>
        </thead>
        <tbody>
          <?php foreach ($documents as $doc): ?>
            <tr>
              <td class="mono nowrap">DOC-<?= e(str_pad((string) $doc['id'], 5, '0', STR_PAD_LEFT)) ?></td>
              <td class="strong"><?= e($doc['title']) ?></td>
              <td class="mono">
                <a href="<?= e(UPLOAD_URL . '/' . rawurlencode((string) $doc['stored_name'])) ?>">
                  <?= e($doc['stored_name']) ?>
                </a>
              </td>
              <td class="mono"><?= e($doc['mime_reported']) ?></td>
              <td class="mono"><?= e($doc['mime_detected']) ?></td>
              <td class="nowrap"><?= e(human_bytes((int) $doc['size_bytes'])) ?></td>
              <td><?= e($doc['owner']) ?></td>
              <td class="mono nowrap"><?= e($doc['uploaded_at']) ?></td>
            </tr>
          <?php endforeach; ?>
        </tbody>
      </table>
    </div>
    <p class="muted small" style="margin-top:1rem;margin-bottom:0;">
      Seeded migration records point at files held in the pre-migration archive
      and will not resolve from this host.
    </p>
  <?php endif; ?>
</div>

<div class="card">
  <h2>Staging accounts</h2>
  <div class="table-scroll">
    <table class="data">
      <thead>
        <tr><th>ID</th><th>Username</th><th>Email</th><th>Role</th><th>Created</th><th>Last sign-in</th></tr>
      </thead>
      <tbody>
        <?php foreach ($accounts as $acct): ?>
          <tr>
            <td class="mono"><?= e((string) $acct['id']) ?></td>
            <td class="strong mono"><?= e($acct['username']) ?></td>
            <td><?= $acct['email'] !== null ? e($acct['email']) : '<span class="muted">—</span>' ?></td>
            <td>
              <span class="chip <?= $acct['role'] === 'admin' ? 'chip-admin' : 'chip-user' ?>">
                <?= e($acct['role']) ?>
              </span>
            </td>
            <td class="mono nowrap"><?= e($acct['created_at']) ?></td>
            <td class="mono nowrap">
              <?= $acct['last_login_at'] !== null ? e($acct['last_login_at']) : '<span class="muted">never</span>' ?>
            </td>
          </tr>
        <?php endforeach; ?>
      </tbody>
    </table>
  </div>
  <p class="muted small" style="margin-top:1rem;margin-bottom:0;">
    Self-service registration is enabled in staging (checklist item MWS-402).
    It must be disabled before handover.
  </p>
</div>

<div class="card">
  <h2>Recent diagnostics</h2>
  <?php if ($diagnostics === []): ?>
    <div class="empty">No checks have been run.</div>
  <?php else: ?>
    <div class="table-scroll">
      <table class="data">
        <thead>
          <tr><th>When</th><th>Account</th><th>Host</th><th>Result</th></tr>
        </thead>
        <tbody>
          <?php foreach ($diagnostics as $row): ?>
            <tr>
              <td class="mono nowrap"><?= e($row['created_at']) ?></td>
              <td><?= $row['username'] !== null ? e($row['username']) : '<span class="muted">—</span>' ?></td>
              <td class="mono"><?= e($row['host_input']) ?></td>
              <td>
                <?php if ((int) $row['accepted'] === 1): ?>
                  <span class="chip chip-user">ran</span>
                <?php else: ?>
                  <span class="chip chip-user">rejected</span>
                <?php endif; ?>
              </td>
            </tr>
          <?php endforeach; ?>
        </tbody>
      </table>
    </div>
  <?php endif; ?>
</div>

<?php page_footer(); ?>
