(function () {

  // --- Create Styles ---
  var style = document.createElement("style");
  style.textContent =
    "#__pcs_bar{display:none;position:fixed;bottom:0;left:0;width:100%;z-index:99999;" +
    "background:#111827;padding:8px 16px 10px;box-sizing:border-box;" +
    "font-family:monospace;font-size:11px;border-top:1px solid #1f2937;}" +
    "#__pcs_toprow{display:flex;justify-content:space-between;margin-bottom:5px;}" +
    "#__pcs_name{color:#9ca3af;white-space:nowrap;overflow:hidden;text-overflow:ellipsis;max-width:75%;}" +
    "#__pcs_pct{color:#60a5fa;font-weight:bold;}" +
    "#__pcs_track{background:#1f2937;border-radius:3px;height:4px;width:100%;overflow:hidden;}" +
    "#__pcs_fill{background:#3b82f6;height:4px;border-radius:3px;width:0%;transition:width 1s linear;}" +
    "#__pcs_botrow{display:flex;gap:20px;margin-top:5px;}" +
    "#__pcs_botrow span{color:#6b7280;}" +
    "#__pcs_botrow span b{color:#9ca3af;font-weight:normal;}" +
    "@keyframes __pcs_pulse{0%,100%{opacity:1}50%{opacity:0.2}}" +
    "#__pcs_dot{display:inline-block;width:6px;height:6px;background:#3b82f6;" +
    "border-radius:50%;margin-left:6px;vertical-align:middle;" +
    "animation:__pcs_pulse 1.4s infinite;}";
  document.head.appendChild(style);

  // --- Create the widget ---
  var widget = document.createElement("div");
  widget.id = "__pcs_bar";
  widget.innerHTML =
    '<div id="__pcs_toprow">' +
      '<span id="__pcs_name"><span id="__pcs_dot"></span></span>' +
      '<span id="__pcs_pct"></span>' +
    '</div>' +
    '<div id="__pcs_track"><div id="__pcs_fill"></div></div>' +
    '<div id="__pcs_botrow">' +
      '<span>elapsed <b id="__pcs_elapsed"></b></span>' +
      '<span>eta <b id="__pcs_eta"></b></span>' +
      '<span>speed <b id="__pcs_speed"></b></span>' +
    '</div>';

  document.body.appendChild(widget);

  // --- Polling every 2 seconds ---
  // A loop for every 2000 milliseconds(every 2 seconds) execute the function 
  // that extract the data of the '/status/status.json'.
  setInterval(function () {
    // Charge/download the '/status/status.json'.
    fetch('/status/status.json', {cache: "no-store"})
      // Parse/translate the raw data into an javascript object(json, interpretable data for javascript).
      .then(function (raw_data) { return raw_data.json(); })
      .then(function (procs_data) {
        // If value of the field 'active' is not true, is false, the div of the progress bar 
        // will not be displayed(will hide it).
        if (!procs_data.active) { widget.style.display = "none"; return; }
        widget.style.display = "block";
        document.getElementById("__pcs_name").textContent    = procs_data.filename  || "";
        document.getElementById("__pcs_pct").textContent     = (procs_data.percent  || 0) + "%";
        document.getElementById("__pcs_fill").style.width    = (procs_data.percent  || 0) + "%";
        document.getElementById("__pcs_elapsed").textContent = procs_data.elapsed   || "--:--:--";
        document.getElementById("__pcs_eta").textContent     = procs_data.eta       || "--:--:--";
        document.getElementById("__pcs_speed").textContent   = procs_data.speed     || "...";
      
      // Queue block
        var queueEl  = document.getElementById("__pcs_queue");
        var listEl   = document.getElementById("__pcs_queue_list");
        var queue    = procs_data.queue || [];
        if (queue.length > 0) {
          listEl.innerHTML = queue.map(function(name) {
            return '<div class="pcs_queue_item">⏳ ' + name + '</div>';
          }).join('');
          queueEl.style.display = "block";
        } else {
          queueEl.style.display = "none";
        }
      })
      .catch(function () {
        // If 'status.json' didn't exist --> no active transcoding --> hide progress bar.
        widget.style.display = "none"; });
  }, 2000);

})();