package layout;

import js.html.Element;
import js.Browser;
import core.TopicStore;
import core.AppState;
import util.EventBus;
import widgets.Widget;
import widgets.WidgetRegistry;

/**
 * 12-column CSS grid engine with full drag/drop, resize, collision
 * detection, and drop-target preview.
 */
class DashboardGrid {
    static inline var COLS     = 12;
    static inline var GRID_GAP = 10;   // must match --grid-gap CSS var
    static inline var ROW_H    = 90;   // must match grid-auto-rows CSS var

    public var editMode(default, set): Bool = false;

    var container: Element;
    var store: TopicStore;
    var appState: AppState;
    var bus: EventBus;

    var tabBar: Element;
    var gridEl: Element;
    var dropTargetEl: Element;      // preview cell shown while dragging
    var tabs: Array<TabState> = [];
    var activeTab: Int = 0;
    var draggingTile: WidgetTile = null;

    var contextMenu: Element;

    public function new(container: Element, store: TopicStore, appState: AppState, bus: EventBus) {
        this.container = container;
        this.store = store;
        this.appState = appState;
        this.bus = bus;

        buildDOM();
        hookBus();
    }

    function buildDOM(): Void {
        container.innerHTML = "";

        tabBar = Browser.document.createElement("div");
        tabBar.id = "grid-tab-bar";
        container.appendChild(tabBar);

        gridEl = Browser.document.createElement("div");
        gridEl.className = "dashboard-grid";
        container.appendChild(gridEl);

        // Drop-target overlay: a grid child positioned at the hover cell
        dropTargetEl = Browser.document.createElement("div");
        dropTargetEl.className = "drop-target";
        dropTargetEl.style.display = "none";
        gridEl.appendChild(dropTargetEl);
    }

    function hookBus(): Void {
        bus.on("grid:editMode",    function(d: Dynamic) { editMode = d.enabled; });
        bus.on("tile:contextmenu", onTileContextMenu);
        bus.on("tile:dragstart",   function(d: Dynamic) { draggingTile = d.tile; });
        bus.on("tile:dragmove",    onTileDragMove);
        bus.on("tile:dragend",     onTileDragEnd);
        bus.on("grid:addWidget",   onAddWidget);
        bus.on("grid:removeWidget",function(d: Dynamic) { removeTile(d.tile); });
        bus.on("grid:nextTab",     function(_) { setActiveTab((activeTab + 1) % tabs.length); });
        bus.on("grid:prevTab",     function(_) { setActiveTab((activeTab - 1 + tabs.length) % tabs.length); });
    }

    // ─── Cell dimensions ──────────────────────────────────────────────────────

    /**
     * Measures one column width by reading actual tile rect (most accurate)
     * or falling back to computed grid width minus padding and gaps.
     */
    public function getCellWidth(): Float {
        var tab = activeTab < tabs.length ? tabs[activeTab] : null;
        if (tab != null) {
            for (t in tab.tiles) {
                if (t.colspan == 1 && t != draggingTile) {
                    var w = t.element.getBoundingClientRect().width;
                    if (w > 4) return w + GRID_GAP;
                }
            }
        }
        // Fallback: compute from grid content width
        var rect  = gridEl.getBoundingClientRect();
        var inner = rect.width - 2 * GRID_GAP;          // subtract grid padding
        return (inner - (COLS - 1) * GRID_GAP) / COLS;
    }

    /**
     * Measures one row height by reading actual tile rect (most accurate)
     * or falling back to the CSS grid-auto-rows value.
     */
    public function getCellHeight(): Float {
        var tab = activeTab < tabs.length ? tabs[activeTab] : null;
        if (tab != null) {
            for (t in tab.tiles) {
                if (t.rowspan == 1 && t != draggingTile) {
                    var h = t.element.getBoundingClientRect().height;
                    if (h > 4) return h + GRID_GAP;
                }
            }
        }
        return ROW_H + GRID_GAP;
    }

    // ─── Grid-coordinate helpers ──────────────────────────────────────────────

    /** Convert absolute mouse X → 1-based grid column, clamped. */
    function mouseToCol(mouseX: Float, colspan: Int): Int {
        var rect = gridEl.getBoundingClientRect();
        var relX = mouseX - rect.left - GRID_GAP;   // subtract grid padding
        var col  = Std.int(Math.floor(relX / getCellWidth())) + 1;
        return Std.int(Math.max(1, Math.min(COLS - colspan + 1, col)));
    }

    /** Convert absolute mouse Y → 1-based grid row, clamped. */
    function mouseToRow(mouseY: Float): Int {
        var rect = gridEl.getBoundingClientRect();
        var relY = mouseY - rect.top - GRID_GAP + gridEl.scrollTop;
        var row  = Std.int(Math.floor(relY / getCellHeight())) + 1;
        return Std.int(Math.max(1, row));
    }

    // ─── Collision detection ─────────────────────────────────────────────────

    /**
     * Returns a set of "col_row" strings occupied by all tiles
     * except the one being dragged/resized.
     */
    function occupancyMap(exclude: WidgetTile): Map<String, Bool> {
        var map: Map<String, Bool> = new Map();
        if (activeTab >= tabs.length) return map;
        for (t in tabs[activeTab].tiles) {
            if (t == exclude) continue;
            for (dc in 0...t.colspan)
                for (dr in 0...t.rowspan)
                    map['${t.col + dc}_${t.row + dr}'] = true;
        }
        return map;
    }

    /** True if placing `tile` at (newCol, newRow) overlaps any other tile. */
    function hasCollision(tile: WidgetTile, newCol: Int, newRow: Int): Bool {
        var occ = occupancyMap(tile);
        for (dc in 0...tile.colspan)
            for (dr in 0...tile.rowspan)
                if (occ.exists('${newCol + dc}_${newRow + dr}')) return true;
        return false;
    }

    /**
     * Find the first free position (scanning left→right, top→bottom)
     * that fits a tile of (cols × rows).  Returns {col, row}.
     */
    function findFreePosition(cols: Int, rows: Int): { col: Int, row: Int } {
        if (activeTab >= tabs.length) return { col: 1, row: 1 };
        var occ = occupancyMap(null);
        var row = 1;
        while (true) {
            for (col in 1...COLS - cols + 2) {
                var free = true;
                for (dc in 0...cols) {
                    for (dr in 0...rows) {
                        if (occ.exists('${col + dc}_${row + dr}')) { free = false; break; }
                    }
                    if (!free) break;
                }
                if (free) return { col: col, row: row };
            }
            row++;
            if (row > 20) return { col: 1, row: row }; // safety escape
        }
    }

    // ─── Drop-target preview ─────────────────────────────────────────────────

    function showDropTarget(col: Int, row: Int, colspan: Int, rowspan: Int, valid: Bool): Void {
        dropTargetEl.style.gridColumn = '${col} / span ${colspan}';
        dropTargetEl.style.gridRow    = '${row} / span ${rowspan}';
        dropTargetEl.style.display    = "";
        dropTargetEl.className = "drop-target" + (valid ? "" : " invalid");
    }

    function hideDropTarget(): Void {
        dropTargetEl.style.display = "none";
    }

    // ─── Bus handlers ─────────────────────────────────────────────────────────

    function onTileDragMove(data: Dynamic): Void {
        var tile: WidgetTile = data.tile;
        var mx: Float = data.x;
        var my: Float = data.y;
        var targetCol = mouseToCol(mx, tile.colspan);
        var targetRow = mouseToRow(my);
        var valid = !hasCollision(tile, targetCol, targetRow);
        showDropTarget(targetCol, targetRow, tile.colspan, tile.rowspan, valid);
    }

    function onTileDragEnd(data: Dynamic): Void {
        var tile: WidgetTile = data.tile;
        var mx: Float = data.x;
        var my: Float = data.y;
        draggingTile = null;
        hideDropTarget();

        var newCol = mouseToCol(mx, tile.colspan);
        var newRow = mouseToRow(my);

        if (!hasCollision(tile, newCol, newRow)) {
            // Clean drop — move tile
            tile.col = newCol;
            tile.row = newRow;
            tile.applyGridPlacement();
            bus.emit("layout:changed", null);
        } else {
            // Blocked — snap tile back to its original position, briefly flash red
            tile.applyGridPlacement();
            flashReject(tile.element);
        }
    }

    function flashReject(el: Element): Void {
        el.style.boxShadow = "0 0 0 3px var(--red), 0 0 20px rgba(255,77,109,0.4)";
        js.Browser.window.setTimeout(function() { el.style.boxShadow = ""; }, 450);
    }

    // ─── Tab management ───────────────────────────────────────────────────────

    function addTab(name: String): TabState {
        var tab: TabState = { name: name, tiles: [] };
        tabs.push(tab);
        renderTabBar();
        return tab;
    }

    function renderTabBar(): Void {
        tabBar.innerHTML = "";
        for (i in 0...tabs.length) {
            var t = tabs[i];
            var el = Browser.document.createElement("div");
            el.className = "tab" + (i == activeTab ? " active" : "");
            el.textContent = t.name;
            var idx = i;
            el.addEventListener("click", function(_) { setActiveTab(idx); });
            if (editMode) {
                el.addEventListener("dblclick", function(_) { renameTab(idx); });
            }
            tabBar.appendChild(el);
        }
        var addBtn = Browser.document.createElement("div");
        addBtn.className = "tab tab-add";
        addBtn.textContent = "+";
        addBtn.title = "Add tab";
        addBtn.addEventListener("click", function(_) {
            addTab("Tab " + (tabs.length + 1));
            setActiveTab(tabs.length - 1);
            bus.emit("layout:changed", null);
        });
        tabBar.appendChild(addBtn);
    }

    function setActiveTab(idx: Int): Void {
        if (idx < 0 || idx >= tabs.length) return;
        activeTab = idx;
        appState.saveActiveTab(idx);
        renderTabBar();
        renderActiveTab();
    }

    function renameTab(idx: Int): Void {
        var name = js.Browser.window.prompt("Tab name:", tabs[idx].name);
        if (name != null && StringTools.trim(name).length > 0) {
            tabs[idx].name = StringTools.trim(name);
            renderTabBar();
            bus.emit("layout:changed", null);
        }
    }

    function renderActiveTab(): Void {
        // Preserve the drop-target element across re-renders
        gridEl.innerHTML = "";
        gridEl.appendChild(dropTargetEl);

        if (activeTab >= tabs.length) return;
        for (tile in tabs[activeTab].tiles) {
            gridEl.appendChild(tile.element);
            tile.widget.onResize();
        }
    }

    // ─── Layout load/save ─────────────────────────────────────────────────────

    public function loadLayout(layout: LayoutSerializer.LayoutData): Void {
        for (tab in tabs) for (tile in tab.tiles) tile.destroy();
        tabs = [];

        for (tabData in layout.tabs) {
            var tab = addTab(tabData.name);
            for (tileData in tabData.tiles) {
                var tile = createTile(tileData);
                if (tile != null) tab.tiles.push(tile);
            }
        }

        if (tabs.length == 0) addTab("Dashboard");
        setActiveTab(appState.activeTabIndex < tabs.length ? appState.activeTabIndex : 0);
    }

    public function loadDefaultLayout(): Void {
        var layout = LayoutSerializer.loadDefault();
        if (layout != null) loadLayout(layout);
        else { addTab("Dashboard"); setActiveTab(0); }
    }

    function createTile(data: LayoutSerializer.TileData): Null<WidgetTile> {
        var widget = WidgetRegistry.create(data.type, store, bus);
        if (widget == null) { trace("DashboardGrid: unknown widget: " + data.type); return null; }
        widget.configure(data.props);
        return new WidgetTile(widget, data.col, data.row, data.colspan, data.rowspan, bus, this);
    }

    public function serialize(): LayoutSerializer.LayoutData {
        return {
            version: 1,
            tabs: tabs.map(function(tab) {
                return {
                    name: tab.name,
                    tiles: tab.tiles.map(function(t) return t.serialize())
                };
            })
        };
    }

    // ─── Edit mode ────────────────────────────────────────────────────────────

    function set_editMode(v: Bool): Bool {
        editMode = v;
        if (v) { container.classList.add("edit-mode"); gridEl.classList.add("edit-mode"); }
        else   { container.classList.remove("edit-mode"); gridEl.classList.remove("edit-mode"); hideDropTarget(); }
        renderTabBar();
        return v;
    }

    // ─── Add / Remove widgets ─────────────────────────────────────────────────

    function onAddWidget(data: Dynamic): Void {
        var widget = WidgetRegistry.create(data.type, store, bus);
        if (widget == null) return;
        widget.configure({});
        if (activeTab >= tabs.length) addTab("Dashboard");
        var pos = findFreePosition(2, 2);
        var tile = new WidgetTile(widget, pos.col, pos.row, 2, 2, bus, this);
        tabs[activeTab].tiles.push(tile);
        gridEl.appendChild(tile.element);
        bus.emit("layout:changed", null);
    }

    function removeTile(tile: WidgetTile): Void {
        if (activeTab >= tabs.length) return;
        tabs[activeTab].tiles = tabs[activeTab].tiles.filter(t -> t != tile);
        tile.destroy();
        bus.emit("layout:changed", null);
    }

    // ─── Context menu ─────────────────────────────────────────────────────────

    function onTileContextMenu(data: Dynamic): Void {
        showContextMenu(data.x, data.y, data.tile);
    }

    function showContextMenu(x: Float, y: Float, tile: WidgetTile): Void {
        hideContextMenu();
        contextMenu = Browser.document.createElement("div");
        contextMenu.className = "context-menu";
        contextMenu.style.left = x + "px";
        contextMenu.style.top  = y + "px";

        var items = [
            { label: "Properties",      cls: "",       action: function() { bus.emit("tile:openProps", tile); } },
            { label: "Configure NT…",   cls: "",       action: function() { openNTConfig(tile); } },
            { label: "",                cls: "sep",    action: function() {} },
            { label: "Duplicate",       cls: "",       action: function() { duplicateTile(tile); } },
            { label: "Remove",          cls: "danger", action: function() { removeTile(tile); } }
        ];

        for (item in items) {
            if (item.cls == "sep") {
                var s = Browser.document.createElement("div"); s.className = "ctx-sep"; contextMenu.appendChild(s); continue;
            }
            var el = Browser.document.createElement("div");
            el.className = "ctx-item " + item.cls;
            el.textContent = item.label;
            var action = item.action;
            el.addEventListener("click", function(_) { action(); hideContextMenu(); });
            contextMenu.appendChild(el);
        }

        Browser.document.body.appendChild(contextMenu);
        js.Browser.window.setTimeout(function() {
            Browser.document.addEventListener("click", hideContextMenuOnce);
        }, 0);
    }

    function hideContextMenuOnce(_: Dynamic): Void {
        hideContextMenu();
        Browser.document.removeEventListener("click", hideContextMenuOnce);
    }

    function hideContextMenu(): Void {
        if (contextMenu != null && contextMenu.parentNode != null)
            contextMenu.parentNode.removeChild(contextMenu);
        contextMenu = null;
    }

    function openNTConfig(tile: WidgetTile): Void {
        var current = tile.widget.ntTopics.join(", ");
        var newTopics = js.Browser.window.prompt("NT Topics (comma separated):", current);
        if (newTopics != null) {
            var arr = newTopics.split(",").map(StringTools.trim).filter(s -> s.length > 0);
            tile.widget.ntTopics = arr;
            var props = tile.widget.serialize();
            if (arr.length > 0) Reflect.setField(props, "topic", arr[0]);
            tile.widget.configure(props);
            bus.emit("layout:changed", null);
        }
    }

    function duplicateTile(tile: WidgetTile): Void {
        var data = tile.serialize();
        var pos = findFreePosition(data.colspan, data.rowspan);
        data.col = pos.col;
        data.row = pos.row;
        var newTile = createTile(data);
        if (newTile == null) return;
        tabs[activeTab].tiles.push(newTile);
        gridEl.appendChild(newTile.element);
        bus.emit("layout:changed", null);
    }
}

typedef TabState = {
    var name: String;
    var tiles: Array<WidgetTile>;
}
