(function () {
  'use strict';

  var splashEl = document.getElementById('splash');
  var loaderEl = document.getElementById('loader');
  var logContainer = document.getElementById('logContainer');
  var progressBar = document.getElementById('progressBar');
  var progressLabel = document.getElementById('progressLabel');

  var MAX_LOG_LINES = 60;

  function sleep(ms) {
    return new Promise(function (resolve) {
      setTimeout(resolve, ms);
    });
  }

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

  function runWebkitExploit() {
    // TODO: real WebKit exploit when ready.
    return sleep(1200);
  }

  function runKernelExploit() {
    // TODO: real kernel exploit when ready.
    return sleep(1200);
  }

  function runPayload() {
    // TODO: load the real payload when ready.
    return sleep(900);
  }

  async function runDemoFlow() {
    uiLog('[DEMO MODE] This is a demo — no real exploit runs. No jailbreak is performed.', 'warning');
    uiLog('WebKit Autoloader by PLK', 'success');
    updateProgress(0, 'Running WebKit exploit...');

    uiLog('Preparing heap spray...', 'info');
    await sleep(1000);

    uiLog('Triggering userland vulnerability...', 'info');
    await runWebkitExploit();

    uiLog('Userland exploit finished.', 'success');
    updateProgress(30, 'Running kernel exploit...');

    uiLog('Spraying kernel objects...', 'info');
    await sleep(900);

    uiLog('Triggering kernel vulnerability...', 'info');
    await runKernelExploit();

    uiLog('Kernel exploit finished.', 'success');
    updateProgress(60, 'Checking jailbreak...');

    await sleep(800);
    uiLog('Jailbroken.', 'success');
    updateProgress(80, 'Loading payload...');

    await runPayload();
    uiLog('Payload loaded.', 'success');

    updateProgress(100, 'Autoload finished.');
  }

  function fail(reason) {
    uiLog('[ERROR] ' + reason, 'error');
    updateProgress(0, 'Failed: ' + reason);
    window.hideUI();
  }

  function start() {
    setTimeout(function () {
      splashEl.classList.add('hide');
      setTimeout(function () {
        splashEl.hidden = true;
        loaderEl.hidden = false;
        runDemoFlow().catch(function (e) {
          fail(e.message);
        });
      }, 480);
    }, 1500);
  }

  window.addEventListener('load', start);
})();
