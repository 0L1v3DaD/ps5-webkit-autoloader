(function () {
  'use strict';

  var splashEl = document.getElementById('splash');
  var loaderEl = document.getElementById('loader');
  var logContainer = document.getElementById('logContainer');
  var progressBar = document.getElementById('progressBar');
  var progressLabel = document.getElementById('progressLabel');
  var exploitEl = document.getElementById('exploit');
  var exploitWrap = document.getElementById('exploitWrap');
  var exploitToggle = document.getElementById('exploitToggle');

  /* After a WebProcess crash the PS5 browser restores this page together with
     the iframe at its last URL — the armed exploit URL, which would auto-run
     the chain again. Blank it as early as possible (the iframe element is
     already in the DOM at script parse) so the chain only runs after the
     test-build gate is accepted. */
  try {
    exploitEl.src = 'about:blank';
  } catch (e) { }

  /* Collapse/expand the debug frame: minimized it becomes a slim bar docked
     at the bottom of the screen, with the slopkit iframe hidden. */
  if (exploitWrap && exploitToggle) {
    exploitToggle.addEventListener('click', function () {
      var minimized = exploitWrap.classList.toggle('minimized');
      exploitToggle.textContent = minimized ? '+' : '\u2212';
    });
  }

  var MAX_LOG_LINES = 80;
  var finished = false;
  var chainStarted = false;
  var mirroredLines = 0;
  var lastStageText = '';
  var lastStageCls = '';
  var lastSummaryText = '';
  var earlyLinesLogged = 0;
  var lastFrameUrl = '';
  var repairCount = 0;

  /* Keep in sync with EXPLOIT_IFRAME_URL in tools/gen_file_registry.py — the
     AppCache manifest lists this exact URL so the console can serve it
     offline (AppCache matches URLs including the query string). */
  var EXPLOIT_URL =
    'slopkit/slopkit/poops.html?go=1&auto=1&trigger=netcontrol&payload=1&autoload=payload.elf&v=17';

  function uiLog(message, type) {
    type = type || 'info';
    var entry = document.createElement('div');
    entry.className = 'line ' + type;
    entry.textContent = message;
    logContainer.appendChild(entry);
    while (logContainer.childElementCount > MAX_LOG_LINES) {
      logContainer.removeChild(logContainer.firstChild);
    }
    logContainer.parentNode.scrollTop = logContainer.parentNode.scrollHeight;
  }

  function updateProgress(percent, message) {
    progressBar.style.transform = 'scaleX(' + percent / 100 + ')';
    if (message) {
      progressLabel.textContent = message;
      uiLog(message, 'info');
    }
  }

  window.uiLog = uiLog;
  window.updateProgress = updateProgress;

  window.hideUI = function () {
    loaderEl.hidden = true;
  };

  function revealExploit() {
    splashEl.classList.add('hide');
    setTimeout(function () {
      splashEl.hidden = true;
      loaderEl.hidden = false;
    }, 480);
  }

  function onAutoloadResult(data) {
    if (finished) return;
    finished = true;
    if (data.ok) {
      uiLog('Payload loaded (' + data.bytes + ' bytes sent to elfldr).', 'success');
      updateProgress(100, 'Autoload finished.');
    } else {
      uiLog('[ERROR] Autoload failed: ' + (data.why || 'unknown error'), 'error');
      updateProgress(0, 'Autoload failed.');
    }
    setTimeout(function () {
      if (data.ok) {
        uiLog('Payload running on the console.', 'success');
      }
    }, 1500);
  }

  /* Mirror slopkit's live screen log (#scr) and stage text (#stage) from the
     same-origin exploit iframe into our own log view, so the UI shows what
     the chain is doing (and errors) instead of a generic progress message. */
  function mirrorSlopkit() {
    var doc;
    try {
      doc = exploitEl.contentDocument;
    } catch (e) {
      return;
    }
    if (!doc) return;

    /* Detect iframe navigation/reload: reset the mirror so a fresh document
       (or a crash restore) streams its log from the top. */
    var frameUrl = '';
    try {
      frameUrl = exploitEl.contentWindow.location.href;
    } catch (e) { }
    if (frameUrl !== lastFrameUrl) {
      lastFrameUrl = frameUrl;
      mirroredLines = 0;
      lastStageText = '';
      lastStageCls = '';
      lastSummaryText = '';
      earlyLinesLogged = 0;
      if (frameUrl && frameUrl !== 'about:blank') {
        uiLog('[iframe] loaded: ' + frameUrl, 'info');
      }
    }
    /* The iframe is intentionally empty until the test-build gate is
       accepted — nothing to mirror yet. */
    if (!chainStarted) return;

    var scr = doc.getElementById('scr');
    if (!scr) {
      /* #scr is static HTML in poops.html — while it parses, #cat (earlier in
         the DOM) and <title> are already present, so a poll can briefly see
         "slopkit page without its screen". Same for the blank pre-navigation
         document. Never warn or re-arm during these windows: re-arming
         reloads the exploit a second time (and the log doubles). */
      var isArmedUrl = frameUrl.length > EXPLOIT_URL.length &&
        frameUrl.slice(-EXPLOIT_URL.length) === EXPLOIT_URL;
      if (frameUrl === 'about:blank' || doc.readyState !== 'complete'
        || isArmedUrl) {
        return;
      }
      /* Only reached when the iframe settled on a *different* page: slopkit's
         landing page (RUN button), a not-armed poops.html, or a 404. */
      var arm = doc.getElementById('arm');
      var cat = doc.getElementById('cat');
      var start = doc.getElementById('start');
      var title = doc.title || '';
      if (mirrorSlopkit.warned !== frameUrl) {
        mirrorSlopkit.warned = frameUrl;
        if (start) {
          uiLog('[iframe] slopkit landing page loaded (RUN button) — chain not started.', 'warning');
        } else if (arm && !arm.hidden) {
          uiLog('[iframe] slopkit page is NOT armed (?go=1 missing) — nothing will run.', 'warning');
        } else if (cat && title.indexOf('slopkit') !== -1) {
          uiLog('[iframe] slopkit page loaded without its screen (title="' + title + '").', 'warning');
        } else {
          uiLog('[iframe] page has no slopkit screen: title="' + title + '"', 'warning');
        }
      }
      /* Re-arm only for a wrong *slopkit* page (landing page or not-armed
         poops.html) — never for the armed URL itself. */
      var isSlopkitPage = !!start || (arm && !arm.hidden);
      if (chainStarted && isSlopkitPage && repairCount < 5) {
        repairCount++;
        uiLog('[iframe] re-arming (attempt ' + repairCount + '): ' + EXPLOIT_URL, 'info');
        try {
          exploitEl.src = EXPLOIT_URL;
        } catch (e) {
          uiLog('[iframe] re-arm failed: ' + (e && e.message ? e.message : e), 'error');
        }
      } else if (chainStarted && isSlopkitPage) {
        uiLog('[iframe] giving up after ' + repairCount + ' re-arm attempts.', 'error');
      }
      return;
    }

    var lines = scr.textContent.split('\n');
    /* If the screen shrank (slopkit caps its log at SCREEN_LINES and drops
       the oldest lines, or a fresh document replaced it), re-anchor the
       counter WITHOUT re-logging — the remaining lines were already streamed,
       and re-streaming them would double the log. A fresh document starts
       empty, so its new lines stream normally from here on. */
    if (lines.length < mirroredLines) {
      mirroredLines = lines.length;
    }
    for (; mirroredLines < lines.length; mirroredLines++) {
      var line = lines[mirroredLines].trim();
      if (line) {
        uiLog(line, /FAIL|ERROR|REFUSED|REBOOT|failed/i.test(line) ? 'error'
          : /PASS|READY|DONE|SUCCESS|OK/i.test(line) ? 'success' : 'info');
      }
    }

    var stage = doc.getElementById('stage');
    if (stage && stage.textContent !== lastStageText) {
      lastStageText = stage.textContent;
      lastStageCls = stage.className || '';
      progressLabel.textContent = lastStageText;
      if (lastStageCls.indexOf('bad') !== -1) {
        uiLog('[slopkit] ' + lastStageText, 'error');
      } else if (lastStageCls.indexOf('ok') !== -1) {
        uiLog('[slopkit] ' + lastStageText, 'success');
      }
    }

    /* Mirror the summary block (verdict/reboot details) when it changes. */
    var summary = doc.getElementById('summary');
    if (summary && summary.textContent && summary.textContent !== lastSummaryText) {
      var summaryLines = summary.textContent.split('\n');
      for (var i = 0; i < summaryLines.length; i++) {
        var sline = summaryLines[i].trim();
        if (sline) {
          uiLog('[summary] ' + sline, 'info');
        }
      }
      lastSummaryText = summary.textContent;
    }

    /* Mirror the #early log (errors/notices written before the module chain
       runs — the earliest thing slopkit produces). slopkit only ever appends
       to #early, so log just the new tail — re-logging the whole buffer on
       every change doubled every early line. */
    var early = doc.getElementById('early');
    if (early && early.textContent) {
      var earlyLines = early.textContent.split('\n');
      if (earlyLines.length < earlyLinesLogged) {
        earlyLinesLogged = 0;
      }
      for (; earlyLinesLogged < earlyLines.length; earlyLinesLogged++) {
        var eline = earlyLines[earlyLinesLogged].trim();
        if (eline) {
          uiLog('[early] ' + eline, /ERROR|FAIL/i.test(eline) ? 'error' : 'info');
        }
      }
    }
  }

  function start() {
    uiLog('WebKit Autoloader by PLK', 'success');
    updateProgress(0, 'Waiting to start...');

    window.addEventListener('message', function (event) {
      var data = event.data;
      if (!data || data.type !== 'wkal') return;
      if (data.kind === 'autoload') {
        onAutoloadResult(data);
      }
    });

    /* No iframe 'load' listener: its mirroredLines reset re-streamed the
       whole screen mid-run (doubling the log), and the other state resets
       are already handled by the URL-diff branch in mirrorSlopkit() plus
       the shrink re-anchor (fresh documents start with an empty screen,
       so their lines stream normally). */
    setInterval(mirrorSlopkit, 500);

    /* Test-build gate: the exploit chain only starts after the user presses
       Continue on the full-screen test notice, and only once the splash has
       fully faded out — so nothing runs behind the notice or the splash. */
    var gateEl = document.getElementById('testGate');
    var proceedBtn = document.getElementById('proceedBtn');
    if (gateEl && proceedBtn) {
      /* After a WebProcess crash the browser restores this page together with
         the iframe at its last URL — the armed exploit URL, which would
         auto-run the chain again. Blank it so the chain only runs after
         Continue. */
      try {
        exploitEl.src = 'about:blank';
      } catch (e) { }

      proceedBtn.addEventListener('click', function () {
        chainStarted = true;
        gateEl.classList.add('hide');
        setTimeout(function () {
          gateEl.hidden = true;
        }, 480);
        setTimeout(function () {
          revealExploit();
        }, 1500);
        /* Splash fade-out takes 480ms after revealExploit(), so start the
           chain only after it is completely gone. */
        setTimeout(function () {
          try {
            exploitEl.src = EXPLOIT_URL;
          } catch (e) {
            uiLog('[ERROR] Could not start the chain: ' + (e && e.message ? e.message : e), 'error');
          }
        }, 1500 + 480 + 200);
      });
    } else {
      chainStarted = true;
      try {
        exploitEl.src = EXPLOIT_URL;
      } catch (e) { }
      setTimeout(function () {
        revealExploit();
      }, 1500);
    }
  }

  window.addEventListener('load', start);
})();
