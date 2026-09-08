<?php
/**
 * Siwang Document Control — account profile.
 *
 * The password change requires the current password, so a forged session
 * cannot be turned into a persistent account takeover of a real user.
 *
 * The role shown here is read from the DATABASE, not from the session. After a
 * successful Stage 2 escalation the navigation says "admin" while this page
 * still says "user" -- a deliberate tell, and a good talking point in the
 * debrief about where authorisation state should actually live.
 */

declare(strict_types=1);

require_once __DIR__ . '/includes/bootstrap.php';

require_login();

$account = current_user_row();

if ($account === null) {
    // Session points at an account that does not exist -- which is exactly what
    // a forged cookie carrying an arbitrary id looks like.
    logout_user();
    header('Location: /login.php');
    exit;
}

$errors = [];
$done   = '';

if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    csrf_check();

    $current = req_str($_POST, 'current');
    $fresh   = req_str($_POST, 'password');
    $confirm = req_str($_POST, 'confirm');

    $stmt = db()->prepare('SELECT password_hash FROM users WHERE id = :id');
    $stmt->execute([':id' => (int) $account['id']]);
    $row = $stmt->fetch();

    if ($row === false || !password_verify($current, (string) $row['password_hash'])) {
        $errors[] = 'Your current password is not correct.';
    }

    if (strlen($fresh) < 8) {
        $errors[] = 'The new password must be at least 8 characters.';
    }

    if ($fresh !== $confirm) {
        $errors[] = 'The two new passwords do not match.';
    }

    if ($errors === []) {
        $update = db()->prepare('UPDATE users SET password_hash = :hash WHERE id = :id');
        $update->execute([
            ':hash' => password_hash($fresh, PASSWORD_BCRYPT),
            ':id'   => (int) $account['id'],
        ]);
        $done = 'Password updated.';
    }
}

page_header('Profile', 'profile');
?>

<div class="page-head">
  <h1>Your account</h1>
  <p>Staging directory record for <?= e($account['username']) ?>.</p>
</div>

<div class="grid-2">

  <div class="card">
    <h2>Account details</h2>
    <div class="table-scroll">
      <table class="data">
        <tbody>
          <tr>
            <td class="strong">Username</td>
            <td class="mono"><?= e($account['username']) ?></td>
          </tr>
          <tr>
            <td class="strong">Email</td>
            <td><?= $account['email'] !== null ? e($account['email']) : '<span class="muted">not set</span>' ?></td>
          </tr>
          <tr>
            <td class="strong">Directory role</td>
            <td>
              <span class="chip <?= $account['role'] === 'admin' ? 'chip-admin' : 'chip-user' ?>">
                <?= e($account['role']) ?>
              </span>
            </td>
          </tr>
          <tr>
            <td class="strong">Created</td>
            <td class="mono nowrap"><?= e($account['created_at']) ?></td>
          </tr>
          <tr>
            <td class="strong">Last sign-in</td>
            <td class="mono nowrap">
              <?= $account['last_login_at'] !== null ? e($account['last_login_at']) : '<span class="muted">never</span>' ?>
            </td>
          </tr>
        </tbody>
      </table>
    </div>
    <p class="muted small" style="margin-top:1rem;margin-bottom:0;">
      Roles are managed in the staff directory and cannot be changed from this
      screen. Contact the IT helpdesk for a role change.
    </p>
  </div>

  <div class="card">
    <h2>Change password</h2>

    <?php if ($done !== ''): ?>
      <div class="msg msg-good"><?= e($done) ?></div>
    <?php endif; ?>

    <?php if ($errors !== []): ?>
      <div class="msg msg-bad">
        <?php foreach ($errors as $i => $err): ?>
          <?= $i > 0 ? '<br>' : '' ?><?= e($err) ?>
        <?php endforeach; ?>
      </div>
    <?php endif; ?>

    <form method="post" action="/profile.php">
      <?= csrf_field() ?>

      <div class="field">
        <label for="current">Current password</label>
        <input id="current" name="current" type="password" autocomplete="current-password" required>
      </div>

      <div class="field">
        <label for="password">New password</label>
        <input id="password" name="password" type="password" autocomplete="new-password" required>
        <p class="hint">Minimum 8 characters.</p>
      </div>

      <div class="field">
        <label for="confirm">Confirm new password</label>
        <input id="confirm" name="confirm" type="password" autocomplete="new-password" required>
      </div>

      <button class="btn" type="submit">Update password</button>
    </form>
  </div>

</div>

<?php page_footer(); ?>
