(function () {
  'use strict';

  /* TEMPORARY no-iframe workaround: the autoloader page only exists to clear
     slopkit's one-shot state and then redirect the browser straight to the
     exploit page (top-level, no iframe), matching the environment the
     original slopkit runs in. See tools/slopkit-autoload.patch for the
     restyled poops.html. */
  var EXPLOIT_URL =
    'slopkit/slopkit/poops.html?go=1&auto=1&trigger=netcontrol&payload=1&autoload=payload.elf&v=17';

  /* slopkit keeps its one-shot latch and its "stopped at …" marker in
     sessionStorage. On the PS5 browser the shortcut session can outlive a
     console reboot, so a previous interrupted run would otherwise block
     every retry with "the last run stopped at X but the latch is clear".
     Clear them before redirecting so the full ladder always restarts from
     the top (never a mid-chain resume). Same origin, so this is exactly the
     storage the chain reads. */
  function clearSlopkitState() {
    try {
      sessionStorage.removeItem('slopkit-poops:next');
      sessionStorage.removeItem('slopkit-poops:latch');
    } catch (e) { }
  }

  function start() {
    clearSlopkitState();
    setTimeout(function () {
      window.location.replace(EXPLOIT_URL);
    }, 1200);
  }

  window.addEventListener('load', start);
})();
