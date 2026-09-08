<?php
/**
 * Dashboard partial — static help text.
 *
 * Not reachable over HTTP (partials/ is denied in the vhost).
 */
declare(strict_types=1);
?>

<div class="card">
  <h2>Using the register</h2>

  <p class="muted">
    The document register is the staging replacement for the shared drive. Every
    document that belongs to a job is registered here against a DOC reference,
    so it can be found without knowing which folder someone filed it in.
  </p>

  <h3 style="font-size:0.95rem;margin-top:1.5rem;">Searching</h3>
  <p class="muted">
    The search box matches on both the document title and the original filename.
    Partial words work. Search is limited to the first 100 matches.
  </p>

  <h3 style="font-size:0.95rem;margin-top:1.5rem;">Registering a document</h3>
  <p class="muted">
    Uploading is restricted to administrators during the staging phase. Send
    documents to your account handler and they will register them for you. This
    restriction is expected to be lifted for all staff at general release.
  </p>

  <h3 style="font-size:0.95rem;margin-top:1.5rem;">Accepted formats</h3>
  <p class="muted">
    GIF, PNG and JPEG page images. PDF support is implemented but is currently
    failing content validation on output from the Tuas scanners, so operations
    have been asked to upload page images until that is resolved.
  </p>

  <h3 style="font-size:0.95rem;margin-top:1.5rem;">Diagnostics</h3>
  <p class="muted" style="margin-bottom:0;">
    The Diagnostics screen was added so the helpdesk could confirm reachability
    of the EDI endpoints from this host without needing a shell. It is a
    reachability check only.
  </p>
</div>
