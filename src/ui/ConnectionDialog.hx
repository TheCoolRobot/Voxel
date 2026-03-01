package ui;

import js.html.Element;
import js.Browser;
import core.NT4Client;
import core.AppState;

/**
 * Modal dialog for entering robot team number / IP / port.
 */
class ConnectionDialog {
    var overlay: Element;
    var ntClient: NT4Client;
    var appState: AppState;

    public function new(ntClient: NT4Client, appState: AppState) {
        this.ntClient = ntClient;
        this.appState = appState;
    }

    public function show(): Void {
        if (overlay != null && overlay.parentNode != null) return;

        var conn = appState.getLastConnection();
        var currentHost = conn != null ? conn.host : "10.0.0.2";
        var currentPort = conn != null ? Std.string(conn.port) : "5810";

        overlay = Browser.document.createElement("div");
        overlay.className = "dialog-overlay";
        overlay.innerHTML = '
          <div class="dialog">
            <h2>Robot Connection</h2>
            <div class="dialog-field">
              <label>Team Number / IP Address</label>
              <input id="conn-host" type="text" value="${currentHost}" placeholder="10.TE.AM.2 or team number">
            </div>
            <div class="dialog-field">
              <label>Port</label>
              <input id="conn-port" type="number" value="${currentPort}" min="1" max="65535">
            </div>
            <div class="dialog-field" style="display:flex;align-items:center;gap:8px;">
              <input id="conn-sim" type="checkbox" style="width:auto;">
              <label style="margin:0;text-transform:none;font-size:13px;">Simulation (localhost)</label>
            </div>
            <div class="dialog-actions">
              <button class="dialog-btn" id="conn-cancel">Cancel</button>
              <button class="dialog-btn" id="conn-disconnect" style="color:var(--accent-red);">Disconnect</button>
              <button class="dialog-btn primary" id="conn-connect">Connect</button>
            </div>
          </div>
        ';

        Browser.document.body.appendChild(overlay);

        // Focus host field
        var hostInput = cast(Browser.document.getElementById("conn-host"), js.html.InputElement);
        hostInput.focus();
        hostInput.select();

        // Sim checkbox
        var simCheck = cast(Browser.document.getElementById("conn-sim"), js.html.InputElement);
        simCheck.addEventListener("change", function(_) {
            if (simCheck.checked) hostInput.value = "localhost";
        });
        hostInput.addEventListener("input", function(_) { simCheck.checked = false; });

        // Team number auto-expand
        hostInput.addEventListener("blur", function(_) {
            var v = StringTools.trim(hostInput.value);
            var teamNum = Std.parseInt(v);
            if (teamNum != null && teamNum > 0 && teamNum <= 9999) {
                var te = Std.int(teamNum / 100);
                var am = teamNum % 100;
                hostInput.value = '10.${te}.${am}.2';
            }
        });

        Browser.document.getElementById("conn-cancel").addEventListener("click", function(_) { close(); });
        Browser.document.getElementById("conn-disconnect").addEventListener("click", function(_) {
            ntClient.disconnect();
            close();
        });
        Browser.document.getElementById("conn-connect").addEventListener("click", function(_) { doConnect(); });

        // Enter key
        overlay.addEventListener("keydown", function(e: js.html.KeyboardEvent) {
            if (e.key == "Enter") doConnect();
            if (e.key == "Escape") close();
        });

        // Click outside
        overlay.addEventListener("click", function(e: Dynamic) {
            if (e.target == overlay) close();
        });
    }

    function doConnect(): Void {
        var hostInput = cast(Browser.document.getElementById("conn-host"), js.html.InputElement);
        var portInput = cast(Browser.document.getElementById("conn-port"), js.html.InputElement);
        var host = StringTools.trim(hostInput.value);
        var port = Std.parseInt(portInput.value);
        if (port == null || port <= 0) port = 5810;
        if (host.length == 0) return;

        appState.saveConnection(host, port);
        ntClient.connect(host, port);
        close();
    }

    function close(): Void {
        if (overlay != null && overlay.parentNode != null)
            overlay.parentNode.removeChild(overlay);
        overlay = null;
    }
}
