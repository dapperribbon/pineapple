<?php
/**
 * Siwang Document Control — register a document.
 *
 * =========================================================================
 * LAB NOTE — this file contains the Stage 3 vulnerability.
 * (Not served as source over HTTP.)
 *
 * Three checks, each individually bypassable, applied in this order:
 *
 *   1. The Content-Type header from the multipart part.
 *      Client-supplied. Never verified. Spoof it.
 *
 *   2. finfo content sniff of the temporary file.
 *      A REAL server-side check -- it opens the file and asks libmagic. But
 *      libmagic identifies a GIF from its 6-byte signature alone, so prefixing
 *      "GIF89a" to a PHP payload is enough to satisfy it. The rest of the file
 *      is never parsed.
 *
 *   3. An extension blacklist containing exactly one entry: "php".
 *      .phtml, .php5, .php7 and .phar are not on it, and the vhost maps all
 *      four to the FPM socket.
 *
 * Working payload:  a file starting with the bytes "GIF89a", containing a PHP
 * tag, named shell.phtml, sent with Content-Type: image/gif.
 *
 * Why finfo and not getimagesize(): getimagesize() parses the logical screen
 * descriptor and would reject a bare 6-byte prefix, forcing students to build
 * a structurally valid GIF. That is a different and fiddlier puzzle. See
 * docs/WALKTHROUGH.md if you want to raise the difficulty that way.
 *
 * What is deliberately NOT vulnerable here:
 *   - basename() strips every path component, so the file cannot be written
 *     outside the uploads directory. The only way out is execution, not
 *     placement.
 *   - Leading-dot filenames are refused, so no .htaccess games (and the vhost
 *     sets AllowOverride None anyway).
 *   - The page is behind require_admin(), checked server-side on every
 *     request. Stage 2 is not optional.
 * =========================================================================
 */

declare(strict_types=1);

require_once __DIR__ . '/includes/bootstrap.php';

require_admin();

$errors  = [];
$stored  = null;
$title   = req_str($_POST, 'title');

if ($_SERVER['REQUEST_METHOD'] === 'POST') {

    $file = $_FILES['doc'] ?? null;

    if (!is_array($file) || !is_string($file['name'] ?? null)) {
        $errors[] = 'No document was received. Choose a file and try again.';

    } elseif (($file['error'] ?? UPLOAD_ERR_NO_FILE) !== UPLOAD_ERR_OK) {

        $errors[] = match ((int) $file['error']) {
            UPLOAD_ERR_INI_SIZE, UPLOAD_ERR_FORM_SIZE =>
                'That file is larger than the ' . human_bytes(UPLOAD_MAX) . ' limit.',
            UPLOAD_ERR_NO_FILE =>
                'No document was received. Choose a file and try again.',
            UPLOAD_ERR_PARTIAL =>
                'The upload was interrupted. Please try again.',
            default =>
                'The upload could not be completed (error ' . (int) $file['error'] . ').',
        };

    } elseif (!is_uploaded_file((string) $file['tmp_name'])) {
        $errors[] = 'The upload could not be verified.';

    } elseif ((int) $file['size'] > UPLOAD_MAX) {
        $errors[] = 'That file is larger than the ' . human_bytes(UPLOAD_MAX) . ' limit.';

    } else {

        $tmp      = (string) $file['tmp_name'];
        $original = (string) $file['name'];
        $reported = is_string($file['type'] ?? null) ? (string) $file['type'] : '';

        // ---- check 1: declared content type ---------------------------------
        if (!in_array($reported, UPLOAD_ALLOWED_MIME, true)) {
            $errors[] = 'That content type is not accepted. Documents must be GIF, PNG or JPEG.';
        }

        // ---- check 2: detected content type ---------------------------------
        $detected = '';
        if ($errors === []) {
            $finfo = finfo_open(FILEINFO_MIME_TYPE);
            if ($finfo === false) {
                $errors[] = 'Content validation is unavailable. Contact the helpdesk.';
            } else {
                $detected = (string) finfo_file($finfo, $tmp);
                finfo_close($finfo);

                if (!in_array($detected, UPLOAD_ALLOWED_MIME, true)) {
                    $errors[] = 'File content does not match an accepted image format.';
                }
            }
        }

        // ---- check 3: extension ---------------------------------------------
        $name = basename(str_replace('\\', '/', $original));

        if ($errors === []) {
            if ($name === '' || $name[0] === '.' || strpos($name, "\0") !== false) {
                $errors[] = 'That filename is not acceptable.';
            } elseif (strlen($name) > 120) {
                $errors[] = 'That filename is too long.';
            } else {
                $ext = strtolower(pathinfo($name, PATHINFO_EXTENSION));

                if ($ext === '') {
                    $errors[] = 'The document must have a file extension.';
                } elseif ($ext === 'php') {
                    $errors[] = 'PHP files are not permitted.';
                }
            }
        }

        // ---- store ------------------------------------------------------------
        if ($errors === []) {
            $target = UPLOAD_DIR . '/' . $name;

            if (!move_uploaded_file($tmp, $target)) {
                error_log('siwang-dev: move_uploaded_file failed for ' . $target);
                $errors[] = 'The document could not be stored. Contact the helpdesk.';
            } else {
                @chmod($target, 0644);

                // Register the file in the document list. This is wrapped so a
                // failure here cannot turn a successful upload into a blank 500:
                // owner_id is a foreign key, and a forged session can carry a
                // user id that does not exist as a real row (the 'forge'
                // helper allows any id). The file is already on disk either
                // way, so we still report the stored name and its link -- the
                // row just won't appear in the admin list.
                try {
                    $insert = db()->prepare(
                        'INSERT INTO documents
                            (owner_id, title, original_name, stored_name,
                             mime_reported, mime_detected, size_bytes)
                         VALUES
                            (:owner, :title, :original, :stored, :reported, :detected, :size)'
                    );
                    $insert->execute([
                        ':owner'    => current_uid(),
                        ':title'    => ($title !== '' ? $title : $name),
                        ':original' => $original,
                        ':stored'   => $name,
                        ':reported' => $reported,
                        ':detected' => $detected,
                        ':size'     => (int) $file['size'],
                    ]);
                } catch (PDOException $e) {
                    error_log('siwang-dev: document row insert failed: ' . $e->getMessage());
                }

                $stored = $name;
                $title  = '';
            }
        }
    }
}

page_header('Document upload', 'upload');
?>

<div class="page-head">
  <h1>Register a document</h1>
  <p>Administrator function. Staging environment — do not upload live customer paperwork.</p>
</div>

<div class="grid-2">

  <div class="card">
    <h2>Upload</h2>

    <?php if ($stored !== null): ?>
      <div class="msg msg-good">
        Registered <strong><?= e($stored) ?></strong>.
        <a href="<?= e(UPLOAD_URL . '/' . rawurlencode($stored)) ?>">View stored document</a>
      </div>
    <?php endif; ?>

    <?php if ($errors !== []): ?>
      <div class="msg msg-bad">
        <?php foreach ($errors as $i => $err): ?>
          <?= $i > 0 ? '<br>' : '' ?><?= e($err) ?>
        <?php endforeach; ?>
      </div>
    <?php endif; ?>

    <form method="post" action="/upload.php" enctype="multipart/form-data">
      <div class="field">
        <label for="title">Document title</label>
        <input id="title" name="title" type="text" value="<?= e($title) ?>"
               placeholder="e.g. Bill of Lading — job 44120">
        <p class="hint">Optional. Defaults to the filename.</p>
      </div>

      <div class="field">
        <label for="doc">Document file</label>
        <input id="doc" name="doc" type="file" required>
        <p class="hint">
          Accepted: GIF, PNG, JPEG — maximum <?= e(human_bytes(UPLOAD_MAX)) ?>.
        </p>
      </div>

      <button class="btn" type="submit">Register document</button>
    </form>
  </div>

  <div class="card">
    <h2>Validation</h2>
    <p class="muted">
      Uploaded files are checked against the accepted image formats before they
      are stored. Both the declared content type and the file's actual contents
      are inspected.
    </p>
    <p class="muted">
      PDF handling is implemented but currently rejects output from the Tuas
      scanners at the content-validation step. Until that is fixed, please
      upload page images.
    </p>
    <p class="muted" style="margin-bottom:0;">
      Registered documents are listed on the
      <a href="/admin.php">administration screen</a>.
    </p>
  </div>

</div>

<?php page_footer(); ?>
