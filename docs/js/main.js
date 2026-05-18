/* ════════════════════════════════════════════
   CORTEX — Main JavaScript
   ════════════════════════════════════════════ */

document.addEventListener('DOMContentLoaded', function () {
  // Initialize sidenav
  var sidenavEls = document.querySelectorAll('.sidenav');
  M.Sidenav.init(sidenavEls);

  // Smooth scroll for anchor links
  document.querySelectorAll('a[href^="#"]').forEach(function (anchor) {
    anchor.addEventListener('click', function (e) {
      var target = document.querySelector(this.getAttribute('href'));
      if (target) {
        e.preventDefault();
        target.scrollIntoView({ behavior: 'smooth', block: 'start' });
      }
    });
  });
});

// Copy install command to clipboard
function copyInstall() {
  var cmd = document.getElementById('install-cmd').textContent;
  navigator.clipboard.writeText(cmd).then(function () {
    M.toast({ html: 'Copied to clipboard', classes: 'rounded' });
  });
}
