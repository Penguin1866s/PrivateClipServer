(function () {
  'use strict';

  var css = document.createElement('style');
  css.textContent =
    '#__pcs_bar{display:none;position:fixed;bottom:0;left:0;width:100%;z-index:99999;' +
    'background:#111827;padding:0.5em 1em 0.6em;box-sizing:border-box;' +
    'font-family:monospace;font-size:1.2em;border-top:1px solid #1f2937;}' +
    '#__pcs_enc_top{display:flex;justify-content:space-between;margin-bottom:0.35em;}' +
    '#__pcs_enc_name{color:#9ca3af;white-space:nowrap;overflow:hidden;text-overflow:ellipsis;max-width:75%;}' +
    '#__pcs_pct{color:#60a5fa;font-weight:bold;}' +
    '#__pcs_track{background:#1f2937;border-radius:3px;height:3px;width:100%;overflow:hidden;}' +
    '#__pcs_fill{background:#3b82f6;height:3px;border-radius:3px;width:0%;transition:width 1s linear;}' +
    '#__pcs_stats{display:flex;gap:1.2em;margin-top:0.35em;}' +
    '#__pcs_stats span{color:#6b7280;}' +
    '#__pcs_stats b{color:#9ca3af;font-weight:normal;}' +
    '#__pcs_state_row{display:none;padding:0.1em 0 0.2em;}' +
    '#__pcs_state_row span{color:#f59e0b;font-size:0.95em;}' +

    '#__pcs_qwidget{display:none;position:fixed;left:1.5em;z-index:100000;' +
    'font-family:monospace;font-size:1.2em;min-width:18em;max-width:28em;}' +
    '#__pcs_qtoggle{display:flex;align-items:center;justify-content:space-between;' +
    'background:#1f2937;border:1px solid #374151;border-bottom:none;' +
    'border-radius:6px 6px 0 0;padding:0.4em 0.8em;cursor:pointer;' +
    'color:#9ca3af;user-select:none;}' +
    '#__pcs_qtoggle:hover{background:#263244;color:#d1d5db;}' +
    '#__pcs_qtitle{display:flex;align-items:center;gap:0.5em;overflow:hidden;}' +
    '#__pcs_qtitle_text{white-space:nowrap;overflow:hidden;text-overflow:ellipsis;}' +
    '#__pcs_qcount{background:#374151;color:#60a5fa;border-radius:3px;' +
    'padding:0 0.4em;font-weight:bold;font-size:0.9em;flex-shrink:0;}' +
    '#__pcs_qarrow{color:#4b5563;font-size:0.85em;transition:transform 0.2s;flex-shrink:0;}' +
    '#__pcs_qarrow.open{transform:rotate(180deg);}' +
    '#__pcs_qpanel{background:#111827;border:1px solid #374151;' +
    'border-bottom:3px solid #3b82f6;border-radius:0 0 6px 6px;max-height:12em;overflow-y:auto;}' +
    '.pcs_qi{padding:0.35em 0.8em;color:#6b7280;border-bottom:1px solid #1f2937;' +
    'white-space:nowrap;overflow:hidden;text-overflow:ellipsis;}' +
    '.pcs_qi:last-child{border-bottom:none;}' +
    '.pcs_qi:hover{background:#1f2937;color:#9ca3af;}' +
    '.pcs_qi_empty{color:#374151;font-style:italic;}' +

    '@keyframes __pcs_pulse{0%,100%{opacity:1}50%{opacity:0.2}}' +
    '#__pcs_dot{display:inline-block;width:0.5em;height:0.5em;background:#3b82f6;' +
    'border-radius:50%;margin-right:0.4em;vertical-align:middle;animation:__pcs_pulse 1.4s infinite;}';
  document.head.appendChild(css);

  // ── DYNAMIC STYLES ──────────────────────────────────────────────────────
  // `<style>` tag, which we will update in real time to beat Vue.js(that is the main style engine of FileBrowser).
  var dynCss = document.createElement('style');
  dynCss.id = '__pcs_dynamic_styles';
  document.head.appendChild(dynCss);

  // ── Progress bar ────────────────────────────────────────────────────────
  var bar = document.createElement('div');
  bar.id = '__pcs_bar';
  bar.innerHTML =
    '<div id="__pcs_state_row"><span id="__pcs_state_text"></span></div>' +
    '<div id="__pcs_enc_top">' +
      '<span id="__pcs_enc_name"><span id="__pcs_dot"></span></span>' +
      '<span id="__pcs_pct"></span>' +
    '</div>' +
    '<div id="__pcs_track"><div id="__pcs_fill"></div></div>' +
    '<div id="__pcs_stats">' +
      '<span>elapsed <b id="__pcs_elapsed"></b></span>' +
      '<span>eta <b id="__pcs_eta"></b></span>' +
      '<span>speed <b id="__pcs_speed"></b></span>' +
    '</div>';
  document.body.appendChild(bar);

  // ── Queue widget ────────────────────────────────────────────────────────
  var qw = document.createElement('div');
  qw.id = '__pcs_qwidget';
  qw.innerHTML =
    '<div id="__pcs_qtoggle">' +
      '<div id="__pcs_qtitle">' +
        '<span id="__pcs_qtitle_text">&#9203; queued</span>' +
        '<span id="__pcs_qcount">0</span>' +
      '</div>' +
      '<span id="__pcs_qarrow">&#9650;</span>' +
    '</div>' +
    '<div id="__pcs_qpanel"><div id="__pcs_qlist"></div></div>';
  document.body.appendChild(qw);

  // starts open
  var qOpen = true;
  document.getElementById('__pcs_qarrow').classList.add('open');

  document.getElementById('__pcs_qtoggle').addEventListener('click', function () {
    qOpen = !qOpen;
    var panel = document.getElementById('__pcs_qpanel');
    var arrow = document.getElementById('__pcs_qarrow');
    var toggle = document.getElementById('__pcs_qtoggle'); // create variable for changing between states of flat and round border radius.
    
    panel.style.display = qOpen ? 'block' : 'none';
    
    if (qOpen) { 
        arrow.classList.add('open'); 
        toggle.style.borderRadius = '6px 6px 0 0'; // Flat when open.
        toggle.style.borderBottom = 'none';        // Remove the border-bottom when open to visually connect the toggle with the panel.
    } else { 
        arrow.classList.remove('open'); 
        toggle.style.borderRadius = '6px'; // Round up the total when closing.
        toggle.style.borderBottom = '1px solid #374151'; // We restore the border-bottom when closed to visually separate the toggle from the panel.
    }
  });

  // ── Polling ─────────────────────────────────────────────────────────────
  setInterval(function () {
    fetch('/status/status.json', { cache: 'no-store' })
      .then(function (r) { return r.json(); })
      .then(function (d) {

        if (!d.active) {
          bar.style.display = 'none';
          qw.style.display  = 'none';
          
          // We cleaned up the dynamic CSS so that FileBrowser would return to its original position.
          dynCss.textContent = '';

          return;
        }

        var state = d.state || 'encoding';
        var queue = d.queue || [];

        // ── Progress bar ──────────────────────────────────────────────────
        bar.style.display = 'block';

        var stateRow  = document.getElementById('__pcs_state_row');
        var stateText = document.getElementById('__pcs_state_text');

        if (state === 'scanning') {
          stateRow.style.display = 'block';
          stateText.textContent  = '\uD83D\uDD0D Scanning for corruption\u2026 pos ' +
                                   (d.scan_pos !== undefined ? d.scan_pos + 's' : '');
        } else if (state === 'correcting') {
          stateRow.style.display = 'block';
          stateText.textContent  = '\u26A0 Corruption found at ' + (d.corrupt_at || '?') +
                                   's \u2014 trimming\u2026';
        } else {
          stateRow.style.display = 'none';
        }

        document.getElementById('__pcs_enc_name').innerHTML =
          '<span id="__pcs_dot"></span>' + (d.filename || '');
        document.getElementById('__pcs_pct').textContent     = (d.percent || 0) + '%';
        document.getElementById('__pcs_fill').style.width    = (d.percent || 0) + '%';
        document.getElementById('__pcs_elapsed').textContent = d.elapsed || '--:--:--';
        document.getElementById('__pcs_eta').textContent     = d.eta     || '--:--:--';
        document.getElementById('__pcs_speed').textContent   = d.speed   || '\u2026';
        // The "'\u2026'" is an unicode character that represents "…" (three dots).
        // we use it instead of "..." to ensure consistent rendering across different browsers and platforms.


        // ── Queue widget — always visible while active ─────────────────────
        qw.style.display = 'block';

        // The title will always be "queued" to avoid redundancy, because the state is already indicated by the progress bar.
        document.getElementById('__pcs_qtitle_text').textContent = '\u23F3 queued';


        // We calculate the current height of the main bar and add a 15-pixel margin.
        // We use setTimeout(..., 0) to let the browser render the "Scanning" text FIRST, 
        // so offsetHeight returns the true expanded height before we move the widget.
        
        // Yield the turn to the renderer(Event Loop yield).
        // info: this allows the DOM updates to happen before we implement things like css transitions, calculating.
        setTimeout(function() {
            var barHeight = bar.offsetHeight;
            var pushUpValue = (barHeight + 15) + 'px';
            
            // We move our little window.
            qw.style.bottom = pushUpValue;

            // DYNAMIC CSS INJECTION: This beats Vue.js.
            // We write a global CSS rule with !important that forces the elements of FileBrowser to float above our toolbar.
            dynCss.textContent = 
                '.card.floating, ' +
                '.Vue-Toastification__container--bottom-left, ' +
                '.Vue-Toastification__container--bottom-right, ' +
                '.Vue-Toastification__container--bottom-center ' +
                '{ bottom: ' + pushUpValue + ' !important; transition: bottom 0.2s ease-out; }';

        }, 0);


        // Count badge: hide when 0
        var countEl = document.getElementById('__pcs_qcount');
        countEl.textContent    = queue.length;
        countEl.style.display  = queue.length > 0 ? 'inline' : 'none';

        // List
        document.getElementById('__pcs_qlist').innerHTML = queue.length > 0
          ? queue.map(function (n) {
              return '<div class="pcs_qi">' + n + '</div>';
            }).join('')
          : '<div class="pcs_qi pcs_qi_empty">nothing else queued</div>';

      })
      .catch(function (err) {
        // If there is a JSON parsing error or a micro-outage, we DO NOT hide the bar.
        console.warn("PCS Widget fetch error:", err);
      });
  }, 2000);

})();