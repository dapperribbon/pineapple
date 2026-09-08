<?php
/**
 * Siwang Document Control — network diagnostics.
 *
 * Added at the helpdesk's request so they could confirm reachability of the
 * EDI endpoints from this host without needing a shell on it.
 *
 * =========================================================================
 * LAB NOTE (not served over HTTP)
 *
 * This is the headline rabbit hole, and it is the highest-risk component on
 * the box, because unlike a fake tool it REALLY DOES execute a command and
 * really does return live output. That is the point: students find genuine
 * command execution, and then cannot get anything out of it. Expect them to
 * spend serious time here.
 *
 * Because it is real, the validation below has to be exactly right. The
 * details that matter, in order of how easily they are got wrong:
 *
 *   1. \A and \z anchors -- NOT ^ and $.
 *      In PHP, '$' also matches immediately before a trailing newline. So
 *      /^[a-z0-9.]+$/ happily accepts "127.0.0.1\n; id". With shell_exec that
 *      is a live command-injection hole, and it is the single most common way
 *      a lab like this leaks an unintended path. \z matches end-of-subject and
 *      nothing else.
 *
 *   2. escapeshellarg() on top of the allowlist.
 *      Belt and braces. If the regex is ever loosened by accident, the shell
 *      still receives one quoted argument.
 *
 *   3. A leading '-' cannot pass validation.
 *      Both the hostname regex and FILTER_VALIDATE_IP require the first
 *      character to be alphanumeric (or a hex digit / colon for IPv6), so
 *      option injection -- "-f" to flood, "-w" to hang the request -- is
 *      impossible. The '--' end-of-options marker in the command line below
 *      is a second layer under the same belt.
 *
 *   4. Bounded execution: -c (count), -W (per-probe timeout) and -w (overall
 *      deadline). Without these the page is a way to hang an FPM worker, and
 *      ten of those is the whole pool.
 *
 *   5. Rate limiting per account, so a class of thirty cannot turn the box
 *      into a traffic generator.
 *
 *   6. Output is HTML-escaped before rendering, so a hostile PTR record
 *      cannot land stored XSS via ping's output. (-n avoids the lookup
 *      entirely, which makes this belt-and-braces too.)
 *
 * Every attempt is logged to diag_queue with accepted=0/1, which gives the
 * instructor a record of exactly which payloads students tried.
 * =========================================================================
 */

declare(strict_types=1);

require_once __DIR__ . '/includes/bootstrap.php';

require_login();

/**
 * A hostname per RFC 1123: labels of alphanumerics and hyphens, hyphens never
 * leading or trailing, labels joined by dots.
 *
 * Anchored with \A ... \z. Do not "tidy" these into ^ ... $.
 */
const DIAG_HOSTNAME_PATTERN =
    '/\A[a-z0-9](?:[a-z0-9\-]{0,61}[a-z0-9])?(?:\.[a-z0-9](?:[a-z0-9\-]{0,61}[a-z0-9])?)*\z/i';

$host      = trim(req_str($_POST, 'host'));
$output    = null;
$error     = '';
$submitted = ($_SERVER['REQUEST_METHOD'] === 'POST');

if ($submitted) {

    $accepted = false;

    if ($host === '') {
        $error = 'Enter a hostname or IP address.';

    } elseif (strlen($host) > DIAG_MAX_HOST_LEN) {
        $error = 'Invalid host.';

    } elseif (!filter_var($host, FILTER_VALIDATE_IP)
              && !preg_match(DIAG_HOSTNAME_PATTERN, $host)) {
        $error = 'Invalid host.';

    } else {
        // Rate limit. The interval is a compile-time constant cast to int, so
        // there is no request data anywhere in this statement.
        $recent = db()->prepare(
            'SELECT COUNT(*) AS hits
               FROM diag_queue
              WHERE user_id = :uid
                AND accepted = 1
                AND created_at > (NOW() - INTERVAL ' . (int) DIAG_RATE_SECONDS . ' SECOND)'
        );
        $recent->execute([':uid' => current_uid()]);
        $hits = (int) ($recent->fetch()['hits'] ?? 0);

        if ($hits > 0) {
            $error = 'Please wait a moment before running another check.';
        } else {
            $accepted = true;
        }
    }

    // Log every attempt, accepted or not, with the raw input exactly as sent.
    $log = db()->prepare(
        'INSERT INTO diag_queue (user_id, host_input, accepted) VALUES (:uid, :host, :ok)'
    );
    $log->execute([
        ':uid'  => current_uid(),
        ':host' => substr($host, 0, 512),
        ':ok'   => $accepted ? 1 : 0,
    ]);

    if ($accepted) {
        $command = sprintf(
            '%s -c %d -W %d -w %d -n -- %s 2>&1',
            DIAG_PING_BIN,
            (int) DIAG_PING_COUNT,
            (int) DIAG_PING_TIMEOUT,
            (int) DIAG_PING_TIMEOUT * (int) DIAG_PING_COUNT,
            escapeshellarg($host)
        );

        $output = shell_exec($command);

        if ($output === null || $output === false || trim((string) $output) === '') {
            $output = null;
            $error  = 'The diagnostics command produced no output. '
                    . 'Check that ICMP is permitted from this host.';
        }
    }
}

page_header('Diagnostics', 'tools');
?>

<div class="page-head">
  <h1>Network diagnostics</h1>
  <p>Reachability check from the staging host.</p>
</div>

<div class="grid-2">

  <div class="card">
    <h2>Ping a host</h2>

    <?php if ($error !== ''): ?>
      <div class="msg msg-bad"><?= e($error) ?></div>
    <?php endif; ?>

    <form method="post" action="/tools.php">
      <div class="field">
        <label for="host">Hostname or IP address</label>
        <input id="host" name="host" type="text" value="<?= e($host) ?>"
               placeholder="10.20.0.14" autocomplete="off" spellcheck="false" autofocus>
        <p class="hint">
          IPv4, IPv6 or a fully qualified domain name.
          <?= (int) DIAG_PING_COUNT ?> probes, <?= (int) DIAG_PING_TIMEOUT ?>s timeout.
        </p>
      </div>
      <button class="btn" type="submit">Run check</button>
    </form>

    <?php if ($output !== null): ?>
      <h2 style="margin-top:1.6rem;">Result</h2>
      <pre class="output"><?= e(rtrim((string) $output)) ?></pre>
    <?php endif; ?>
  </div>

  <div class="card">
    <h2>About this tool</h2>
    <p class="muted">
      This runs a bounded ICMP echo request from the staging host and returns
      the raw result. It exists so the helpdesk can answer &ldquo;can the server
      see it?&rdquo; without opening a shell session.
    </p>
    <p class="muted">
      Input is restricted to a valid IP address or hostname. Requests are rate
      limited to one per <?= (int) DIAG_RATE_SECONDS ?> seconds per account, and
      every check is recorded against your username.
    </p>
    <p class="muted" style="margin-bottom:0;">
      A traceroute equivalent and a TCP port check were requested but are not
      in scope for the staging build.
    </p>
  </div>

</div>

<?php page_footer(); ?>
