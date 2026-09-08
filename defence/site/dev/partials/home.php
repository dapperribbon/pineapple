<?php
/**
 * Dashboard partial — the full document register.
 *
 * Expects $documents, $q and $totals from dashboard.php.
 * Not reachable over HTTP (partials/ is denied in the vhost).
 */
declare(strict_types=1);
?>

<div class="card">
  <form method="get" action="/dashboard.php">
    <input type="hidden" name="view" value="home">
    <div class="field" style="margin-bottom:0.8rem;">
      <label for="q">Search title or filename</label>
      <input id="q" name="q" type="text" value="<?= e($q) ?>"
             placeholder="e.g. bill of lading, berth, 88214">
    </div>
    <button class="btn" type="submit">Search</button>
    <?php if ($q !== ''): ?>
      <a class="btn btn-quiet" href="/dashboard.php?view=home">Clear</a>
    <?php endif; ?>
  </form>
</div>

<div class="card">
  <h2>
    Documents
    <?php if ($q !== ''): ?>
      <span class="muted small">matching &ldquo;<?= e($q) ?>&rdquo;</span>
    <?php endif; ?>
  </h2>

  <?php if ($documents === []): ?>
    <div class="empty">
      <?php if ($q !== ''): ?>
        No results for &ldquo;<?= e($q) ?>&rdquo;.
      <?php else: ?>
        No documents have been registered yet.
      <?php endif; ?>
    </div>
  <?php else: ?>
    <div class="table-scroll">
      <table class="data">
        <thead>
          <tr>
            <th>Ref</th>
            <th>Title</th>
            <th>Filename</th>
            <th>Type</th>
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
              <td class="mono"><?= e($doc['original_name']) ?></td>
              <td class="mono"><?= e($doc['mime_detected']) ?></td>
              <td class="nowrap"><?= e(human_bytes((int) $doc['size_bytes'])) ?></td>
              <td><?= e($doc['owner']) ?></td>
              <td class="nowrap"><?= e($doc['uploaded_at']) ?></td>
            </tr>
          <?php endforeach; ?>
        </tbody>
      </table>
    </div>
  <?php endif; ?>

  <p class="muted small" style="margin-top:1rem;margin-bottom:0;">
    Document retrieval is not enabled in staging. Registered documents are
    listed here for verification only; download links are available to
    administrators from the administration screen.
  </p>
</div>

<div class="card">
  <h2>Register totals</h2>
  <div class="table-scroll">
    <table class="data">
      <tbody>
        <tr><td class="strong">Documents registered</td><td><?= e((string) $totals['docs']) ?></td></tr>
        <tr><td class="strong">Accounts</td><td><?= e((string) $totals['users']) ?></td></tr>
        <tr><td class="strong">Total size</td><td><?= e(human_bytes((int) $totals['bytes'])) ?></td></tr>
      </tbody>
    </table>
  </div>
</div>
