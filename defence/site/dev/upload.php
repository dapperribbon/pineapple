<?php
/**
 * Siwang Document Control — register a document.
 *
 * =========================================================================
 * LAB NOTE — this file contains the Stage 3 vulnerability.
 * (Not served as source over HTTP.)
 *
 * Five checks, applied in this order. Each has a distinct rejection message
 * so a student can tell which layer they are fighting:
 *
 *   1. Extension ALLOWLIST -- jpg / jpeg / gif / png / bmp only.
 *      (No .phtml/.php5 tricks: the extension must be a real image type.)
 *
 *   2. Size cap.
 *
 *   3. Filename must not contain the substring ".php" anywhere.
 *
 *   4. The file must decode as a real image via GD (imagecreatefrom*).
 *      A genuine server-side check -- junk renamed .gif is rejected. But note
 *      GD only has to LOAD it; the original bytes are what get stored, so a
 *      valid image with a payload appended after the image data still passes.
 *
 *   5. The file contents must not contain the literal string "<?php".
 *      This is the weak link: it does NOT catch the short-echo tag "<?=",
 *      and <script language=php> was removed in PHP 7. So a valid image
 *      carrying "<?= system($_GET['c']); ?>" defeats all five checks.
 *
 * Execution: the stored file keeps its image extension, and the vhost maps
 * image extensions to PHP-FPM *inside the uploads directory only*. So fetching
 * /uploads/<name>.gif runs the embedded PHP -> RCE as www-data.
 *
 * What is deliberately NOT vulnerable here:
 *   - The stored name is server-generated (random) + the validated extension;
 *     the client filename never reaches the path, so no traversal / overwrite.
 *   - Image execution is scoped to the uploads dir by the vhost, not global.
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

/**
 * Decode an uploaded image with the matching GD loader. Returns a GdImage on
 * success or false on failure -- exactly the validity gate uploadv2 used.
 */
function siwang_image_loads(string $ext, string $path)
{
    switch ($ext) {
        case 'jpg':
        case 'jpeg': return @imagecreatefromjpeg($path);
        case 'gif':  return @imagecreatefromgif($path);
        case 'png':  return @imagecreatefrompng($path);
        case 'bmp':  return function_exists('imagecreatefrombmp')
                          ? @imagecreatefrombmp($path) : false;
        default:     return false;
    }
}

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

    } else {

        $tmp      = (string) $file['tmp_name'];
        $original = (string) $file['name'];
        $reported = is_string($file['type'] ?? null) ? (string) $file['type'] : '';
        $name     = basename(str_replace('\\', '/', $original));
        $ext      = strtolower(pathinfo($name, PATHINFO_EXTENSION));

        // ---- check 1: extension allowlist -----------------------------------
        if (!in_array($ext, UPLOAD_ALLOWED_EXT, true)) {
            $errors[] = 'Only image files are accepted (JPG, JPEG, GIF, PNG, BMP).';
        }

        // ---- check 2: size --------------------------------------------------
        if ($errors === [] && (int) $file['size'] > UPLOAD_MAX) {
            $errors[] = 'That file is larger than the ' . human_bytes(UPLOAD_MAX) . ' limit.';
        }

        // ---- check 3: no ".php" anywhere in the filename --------------------
        if ($errors === [] && stripos($name, '.php') !== false) {
            $errors[] = 'That filename is not permitted.';
        }

        // ---- check 4: must decode as a real image ---------------------------
        if ($errors === []) {
            $im = siwang_image_loads($ext, $tmp);
            if ($im === false) {
                $errors[] = 'That file is not a valid image.';
            } elseif ($im instanceof GdImage) {
                imagedestroy($im);
            }
        }

        // ---- check 5: contents must not contain "<?php" ---------------------
        if ($errors === []) {
            $data = (string) file_get_contents($tmp);
            if (strpos($data, '<?php') !== false) {
                $errors[] = 'That file appears to contain server code and was rejected.';
            }
        }

        // ---- store ------------------------------------------------------------
        if ($errors === []) {
            // Server-generated name: the client filename never influences the
            // path, and the extension is one of the validated image types.
            $storedName = bin2hex(random_bytes(8)) . '.' . $ext;
            $target     = UPLOAD_DIR . '/' . $storedName;

            if (!move_uploaded_file($tmp, $target)) {
                error_log('siwang-dev: move_uploaded_file failed for ' . $target);
                $errors[] = 'The document could not be stored. Contact the helpdesk.';
            } else {
                @chmod($target, 0644);

                // Register the file in the document list. Wrapped so a failure
                // here cannot turn a successful upload into a blank 500: owner_id
                // is a foreign key, and a forged session can carry a user id that
                // does not exist as a real row. The file is already on disk
                // either way, so we still report the stored name and its link.
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
                        ':stored'   => $storedName,
                        ':reported' => $reported,
                        ':detected' => 'image/' . ($ext === 'jpg' ? 'jpeg' : $ext),
                        ':size'     => (int) $file['size'],
                    ]);
                } catch (PDOException $e) {
                    error_log('siwang-dev: document row insert failed: ' . $e->getMessage());
                }

                $stored = $storedName;
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
        <a href="/view.php?f=<?= e(rawurlencode($stored)) ?>">View stored document</a>
        <div class="mono small" style="margin-top:0.4rem;">
          <?= e(UPLOAD_URL . '/' . $stored) ?>
        </div>
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
          Accepted: JPG, JPEG, GIF, PNG, BMP — maximum <?= e(human_bytes(UPLOAD_MAX)) ?>.
        </p>
      </div>

      <button class="btn" type="submit">Register document</button>
    </form>
  </div>

  <div class="card">
    <h2>Validation</h2>
    <p class="muted">
      Uploads must be page images. Each file is checked by extension, decoded to
      confirm it is a real image, and scanned to reject any that carry embedded
      server code before it is stored.
    </p>
    <p class="muted">
      PDF handling is implemented but currently rejects output from the Tuas
      scanners at the decode step. Until that is fixed, please upload page
      images (a scan or a photo of the document).
    </p>
    <p class="muted" style="margin-bottom:0;">
      Registered documents are listed on the
      <a href="/admin.php">administration screen</a>.
    </p>
  </div>

</div>

<?php page_footer(); ?>
