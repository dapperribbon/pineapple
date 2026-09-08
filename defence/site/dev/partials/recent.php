<?php
/**
 * Dashboard partial — recent activity.
 *
 * Expects $documents from dashboard.php.
 * Not reachable over HTTP (partials/ is denied in the vhost).
 */
declare(strict_types=1);

$recent = array_slice($documents, 0, 8);
?>

<div class="card">
  <h2>Recently registered</h2>

  <?php if ($recent === []): ?>
    <div class="empty">Nothing has been registered yet.</div>
  <?php else: ?>
    <div class="table-scroll">
      <table class="data">
        <thead>
          <tr><th>Registered</th><th>Title</th><th>Owner</th><th>Size</th></tr>
        </thead>
        <tbody>
          <?php foreach ($recent as $doc): ?>
            <tr>
              <td class="mono nowrap"><?= e($doc['uploaded_at']) ?></td>
              <td class="strong"><?= e($doc['title']) ?></td>
              <td><?= e($doc['owner']) ?></td>
              <td class="nowrap"><?= e(human_bytes((int) $doc['size_bytes'])) ?></td>
            </tr>
          <?php endforeach; ?>
        </tbody>
      </table>
    </div>
  <?php endif; ?>
</div>

<div class="card">
  <h2>Migration progress</h2>
  <p class="muted">
    Batch 1 (2019–2024 scanned sets) is loaded. Batches 2 and 3 are blocked
    pending sign-off on the retention schedule. Approximately 1.4 million pages
    remain in the pre-migration archive.
  </p>
  <p class="muted" style="margin-bottom:0;">
    Nightly snapshots of the staging register are written to the operations
    backup host. Restores are handled by the IT helpdesk.
  </p>
</div>
