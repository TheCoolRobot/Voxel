package;

import core.AppState;
import core.NT4Client;
import core.TopicStore;
import layout.DashboardGrid;
import layout.LayoutSerializer;
import ui.Toolbar;
import ui.ThemeManager;
import util.EventBus;
import widgets.WidgetRegistry;
import js.Browser;
import js.html.Element;

class Main {
    static var appState: AppState;
    static var ntClient: NT4Client;
    static var topicStore: TopicStore;
    static var grid: DashboardGrid;
    static var toolbar: Toolbar;

    static function main() {
        // Register all widgets before anything else
        WidgetRegistry.registerAll();

        var root = Browser.document.getElementById("root");
        if (root == null) {
            trace("ERROR: #root element not found");
            return;
        }

        // Init subsystems
        appState = new AppState();
        var bus = EventBus.instance;
        topicStore = new TopicStore(bus);
        ntClient = new NT4Client(topicStore, bus);
        appState.ntClient = ntClient;

        // Wire NT publish requests from widgets
        bus.on("nt:publish", function(data: Dynamic) {
            ntClient.publish(data.topic, data.value, data.type != null ? data.type : "string");
        });

        // Apply saved theme
        ThemeManager.instance.apply(appState.theme);

        // Build toolbar (includes widget picker, property panel)
        toolbar = new Toolbar(root, appState, ntClient, topicStore);

        // Build grid container
        var gridContainer = Browser.document.createElement("div");
        gridContainer.id = "grid-container";
        gridContainer.style.cssText = "flex:1;display:flex;flex-direction:column;overflow:hidden;";
        root.appendChild(gridContainer);

        grid = new DashboardGrid(gridContainer, topicStore, appState, bus);

        // Handle layout import from toolbar
        bus.on("grid:loadLayout", function(layout: Dynamic) {
            grid.loadLayout(layout);
        });

        // Load persisted layout
        var layout = LayoutSerializer.load();
        if (layout != null) {
            grid.loadLayout(layout);
        } else {
            grid.loadDefaultLayout();
        }

        // Auto-save on changes
        bus.on("layout:changed", function(_) {
            LayoutSerializer.save(grid.serialize());
        });

        // Handle connection state UI
        bus.on("nt:connected", function(_) {
            toolbar.setConnectionState(true);
        });
        bus.on("nt:disconnected", function(_) {
            toolbar.setConnectionState(false);
        });

        // Restore last connection if saved
        var lastConn = appState.getLastConnection();
        if (lastConn != null) {
            ntClient.connect(lastConn.host, lastConn.port);
        }

        // Keyboard shortcuts
        Browser.document.addEventListener("keydown", function(e: js.html.KeyboardEvent) {
            if (e.ctrlKey || e.metaKey) {
                switch (e.key) {
                    case "e": bus.emit("grid:editMode", { enabled: !appState.editMode }); appState.editMode = !appState.editMode; e.preventDefault();
                    case "Tab": if (e.shiftKey) bus.emit("grid:prevTab", null); else bus.emit("grid:nextTab", null); e.preventDefault();
                }
            }
        });

        trace("FRC Dashboard initialized");
    }
}
