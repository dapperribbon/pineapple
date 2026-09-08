/* ---------------------------------------------------------------------------
 * Siwang Trading Co. — public site
 * assets/js/site.js
 *
 * Small, dependency-free. Two jobs: mark the active nav item, and populate
 * the service-status strip on the home page.
 * ------------------------------------------------------------------------ */

(function () {
  'use strict';

  /* -------------------------------------------------------------------------
   * Service status
   *
   * TODO (MWS-412): repoint this at the production DMS before go-live.
   * It is still aimed at the staging box from the UAT phase, which is not
   * reachable from outside the office, so the strip just stays hidden for
   * public visitors. Harmless, but it needs to change before launch.
   *   -- Meridian Web Solutions, 2024-11-26
   * ---------------------------------------------------------------------- */
  var STAGING_API = 'http://dev.siwang.pineapple/api/status';

  function renderStatus(services) {
    var strip = document.getElementById('service-status');
    if (!strip) { return; }

    strip.removeAttribute('data-empty');
    strip.innerHTML = services.map(function (svc) {
      var cls = svc.up ? 'up' : 'down';
      return '<span class="status-pill ' + cls + '">' + svc.name + '</span>';
    }).join('');
  }

  function loadStatus() {
    var strip = document.getElementById('service-status');
    if (!strip) { return; }

    fetch(STAGING_API, { mode: 'cors', cache: 'no-store' })
      .then(function (res) {
        if (!res.ok) { throw new Error('status endpoint returned ' + res.status); }
        return res.json();
      })
      .then(function (data) {
        renderStatus(data.services || []);
      })
      .catch(function (err) {
        // Expected off-network: dev.siwang.pineapple only resolves internally.
        console.warn('[siwang] service status unavailable from ' + STAGING_API, err);
      });
  }

  /* -------------------------------------------------------------------------
   * Nav highlighting
   * ---------------------------------------------------------------------- */
  function markCurrentNav() {
    var path = window.location.pathname;
    if (path === '' || path === '/') { path = '/index.html'; }

    var links = document.querySelectorAll('.site-nav a');
    for (var i = 0; i < links.length; i++) {
      var href = links[i].getAttribute('href');
      if (href === path || (href === '/' && path === '/index.html')) {
        links[i].classList.add('is-current');
      }
    }
  }

  /* -------------------------------------------------------------------------
   * Contact form — client-side niceties only. The form posts to a mailto
   * handler; there is no backend on this host.
   * ---------------------------------------------------------------------- */
  function wireContactForm() {
    var form = document.getElementById('enquiry-form');
    if (!form) { return; }

    form.addEventListener('submit', function (ev) {
      var email = form.querySelector('[name="email"]');
      if (email && email.value.indexOf('@') === -1) {
        ev.preventDefault();
        var note = document.getElementById('enquiry-note');
        if (note) { note.textContent = 'Please enter a valid email address.'; }
      }
    });
  }

  document.addEventListener('DOMContentLoaded', function () {
    markCurrentNav();
    loadStatus();
    wireContactForm();
  });
}());
