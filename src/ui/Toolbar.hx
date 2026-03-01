package ui;

import js.html.Element;
import js.Browser;
import core.NT4Client;
import core.AppState;
import layout.LayoutSerializer;
import util.EventBus;

/**
 * Top toolbar: connection, edit-mode toggle, tab bar, theme, import/export.
 */
class Toolbar {
    var root: Element;
    var appState: AppState;
    var ntClient: NT4Client;
    var bus: EventBus;
    var connectionDialog: ConnectionDialog;
    var widgetPicker: WidgetPicker;
    var propertyPanel: PropertyPanel;

    var connBtn: Element;
    var connIndicator: Element;
    var editBtn: Element;
    var pickerBtn: Element;

    public function new(root: Element, appState: AppState, ntClient: NT4Client) {
        this.root = root;
        this.appState = appState;
        this.ntClient = ntClient;
        this.bus = EventBus.instance;

        connectionDialog = new ConnectionDialog(ntClient, appState);
        widgetPicker = new WidgetPicker(bus);
        propertyPanel = new PropertyPanel(bus);

        buildDOM();
    }

    function buildDOM(): Void {
        var toolbar = Browser.document.createElement("div");
        toolbar.id = "toolbar";

        // Connection indicator + button
        connIndicator = Browser.document.createElement("div");
        connIndicator.className = "connection-indicator";
        connIndicator.title = "Disconnected";
        toolbar.appendChild(connIndicator);

        connBtn = makeBtn("Connect", function() { connectionDialog.show(); });
        toolbar.appendChild(connBtn);

        toolbar.appendChild(makeSep());

        // Edit mode toggle
        editBtn = makeBtn("Edit Mode", function() {
            appState.editMode = !appState.editMode;
            bus.emit("grid:editMode", { enabled: appState.editMode });
            updateEditBtn();
        });
        toolbar.appendChild(editBtn);

        // Widget picker toggle (only in edit mode effectively, but always visible)
        pickerBtn = makeBtn("+ Widget", function() { widgetPicker.toggle(); });
        toolbar.appendChild(pickerBtn);

        toolbar.appendChild(makeSep());

        // Import / Export layout
        toolbar.appendChild(makeBtn("Export", function() { doExport(); }));
        toolbar.appendChild(makeBtn("Import", function() { doImport(); }));

        toolbar.appendChild(makeSep());

        // Theme toggle
        toolbar.appendChild(makeBtn("Theme", function() {
            ThemeManager.instance.toggle();
            appState.saveTheme(ThemeManager.instance.getTheme());
        }));

        // Spacer
        var spacer = Browser.document.createElement("div");
        spacer.className = "toolbar-spacer";
        toolbar.appendChild(spacer);

        // Version label
        var ver = Browser.document.createElement("div");
        ver.style.cssText = "font-size:10px;color:var(--text-dim);";
        ver.textContent = "FRC Dashboard v1.0";
        toolbar.appendChild(ver);

        root.appendChild(toolbar);
    }

    function makeBtn(label: String, onClick: Void->Void): Element {
        var btn = Browser.document.createElement("button");
        btn.className = "toolbar-btn";
        btn.textContent = label;
        btn.addEventListener("click", function(_) { onClick(); });
        return btn;
    }

    function makeSep(): Element {
        var sep = Browser.document.createElement("div");
        sep.className = "toolbar-sep";
        return sep;
    }

    public function setConnectionState(connected: Bool): Void {
        if (connected) {
            connIndicator.classList.add("connected");
            connIndicator.title = "Connected";
            connBtn.textContent = "Connected";
            cast(connBtn, js.html.Element).classList.add("active");
        } else {
            connIndicator.classList.remove("connected");
            connIndicator.title = "Disconnected";
            connBtn.textContent = "Connect";
            cast(connBtn, js.html.Element).classList.remove("active");
        }
    }

    function updateEditBtn(): Void {
        if (appState.editMode) {
            cast(editBtn, js.html.Element).classList.add("active");
            editBtn.textContent = "✓ Edit Mode";
        } else {
            cast(editBtn, js.html.Element).classList.remove("active");
            editBtn.textContent = "Edit Mode";
        }
    }

    function doExport(): Void {
        bus.once("grid:requestLayout", function(layout: Dynamic) {
            var json = LayoutSerializer.exportJson(layout);
            var blob = js.lib.Object.create(null);
            // Create download via data URL
            var encoded = js.Browser.window.btoa(haxe.crypto.Base64.encode(haxe.io.Bytes.ofString(json)));
            var url = "data:application/json;base64," + js.Browser.window.btoa(json);
            var a = cast(Browser.document.createElement("a"), js.html.AnchorElement);
            a.href = url;
            a.download = "frc-layout.json";
            a.click();
        });
        bus.emit("grid:getLayout", null);
    }

    function doImport(): Void {
        var input = cast(Browser.document.createElement("input"), js.html.InputElement);
        input.type = "file";
        input.accept = ".json";
        input.addEventListener("change", function(_) {
            var file = input.files.item(0);
            if (file == null) return;
            var reader = new js.html.FileReader();
            reader.onload = function(e) {
                var text: String = Reflect.field(Reflect.field(e, "target"), "result");
                var layout = LayoutSerializer.importJson(text);
                if (layout != null) {
                    bus.emit("grid:loadLayout", layout);
                    LayoutSerializer.save(layout);
                }
            };
            reader.readAsText(file);
        });
        input.click();
    }
}
