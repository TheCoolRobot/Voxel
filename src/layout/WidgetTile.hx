package layout;

import js.html.Element;
import js.html.MouseEvent;
import js.Browser;
import widgets.Widget;
import util.EventBus;

/**
 * Wraps a Widget in a titled, draggable, resizable tile.
 *
 * Drag: creates a fixed-position ghost clone that follows the cursor.
 * The original tile stays as a dim placeholder so the user sees both
 * where the tile came from and where it will land (via grid's drop target).
 *
 * Resize: updates colspan/rowspan in real-time as the user drags the
 * bottom-right grip.
 */
class WidgetTile {
    public var element: Element;
    public var widget: Widget;
    public var col: Int;
    public var row: Int;
    public var colspan: Int;
    public var rowspan: Int;
    public var tileId: String;

    var titleEl: Element;
    var contentEl: Element;
    var resizeHandle: Element;
    var dragHandle: Element;
    var bus: EventBus;
    var grid: DashboardGrid;

    // Drag state
    var dragging: Bool = false;
    var dragGhost: Element = null;
    var dragOffsetX: Float = 0;
    var dragOffsetY: Float = 0;

    static var _nextId = 0;

    public function new(widget: Widget, col: Int, row: Int, colspan: Int, rowspan: Int,
                        bus: EventBus, grid: DashboardGrid) {
        this.widget = widget;
        this.col = col;
        this.row = row;
        this.colspan = colspan;
        this.rowspan = rowspan;
        this.bus = bus;
        this.grid = grid;
        this.tileId = "tile-" + (_nextId++);

        buildDOM();
        applyGridPlacement();
    }

    function buildDOM(): Void {
        element = Browser.document.createElement("div");
        element.className = "widget-tile";
        element.id = tileId;

        // Header
        var header = Browser.document.createElement("div");
        header.className = "widget-tile-header";

        dragHandle = Browser.document.createElement("div");
        dragHandle.className = "drag-handle";
        dragHandle.innerHTML = "&#9776;";
        dragHandle.title = "Drag to move";
        header.appendChild(dragHandle);

        titleEl = Browser.document.createElement("div");
        titleEl.className = "widget-tile-title";
        titleEl.textContent = widget.title;
        header.appendChild(titleEl);

        var badge = Browser.document.createElement("div");
        badge.style.cssText = "font-size:10px;color:var(--text-dim);flex-shrink:0;";
        badge.textContent = widget.widgetType;
        header.appendChild(badge);

        element.appendChild(header);

        contentEl = Browser.document.createElement("div");
        contentEl.className = "widget-tile-content";
        element.appendChild(contentEl);

        resizeHandle = Browser.document.createElement("div");
        resizeHandle.className = "resize-handle";
        resizeHandle.innerHTML = "&#x2922;";
        resizeHandle.title = "Drag to resize";
        element.appendChild(resizeHandle);

        widget.mount(contentEl);

        element.addEventListener("contextmenu", onContextMenu);
        dragHandle.addEventListener("mousedown", onDragStart);
        resizeHandle.addEventListener("mousedown", onResizeStart);
    }

    public function applyGridPlacement(): Void {
        element.style.gridColumn = '${col} / span ${colspan}';
        element.style.gridRow    = '${row} / span ${rowspan}';
        // Remove any leftover fixed positioning from drag
        element.style.position = "";
        element.style.left = "";
        element.style.top  = "";
        element.style.width = "";
        element.style.height = "";
    }

    public function updateTitle(t: String): Void {
        titleEl.textContent = t;
        widget.title = t;
    }

    public function destroy(): Void {
        cleanupGhost();
        widget.destroy();
        if (element.parentNode != null)
            element.parentNode.removeChild(element);
    }

    // ─── Context Menu ─────────────────────────────────────────────────────────

    function onContextMenu(e: MouseEvent): Void {
        e.preventDefault();
        bus.emit("tile:contextmenu", { tile: this, x: e.clientX, y: e.clientY });
    }

    // ─── Drag ─────────────────────────────────────────────────────────────────

    function onDragStart(e: MouseEvent): Void {
        if (!grid.editMode) return;
        e.preventDefault();
        e.stopPropagation();
        dragging = true;

        // Offset from cursor to the tile's top-left corner
        var rect = element.getBoundingClientRect();
        dragOffsetX = e.clientX - rect.left;
        dragOffsetY = e.clientY - rect.top;

        // Ghost clone follows the cursor
        dragGhost = cast element.cloneNode(true);
        dragGhost.id = tileId + "-ghost";
        dragGhost.style.cssText =
            'position:fixed;left:${rect.left}px;top:${rect.top}px;' +
            'width:${rect.width}px;height:${rect.height}px;' +
            'opacity:0.72;z-index:9999;pointer-events:none;' +
            'box-shadow:0 16px 48px rgba(0,0,0,0.7),0 0 0 2px rgba(0,212,255,0.5);' +
            'border-radius:var(--tile-radius);transition:none;';
        Browser.document.body.appendChild(dragGhost);

        // Original becomes a translucent "source" placeholder
        element.style.opacity = "0.2";

        // Notify grid so it can show the drop-target overlay
        bus.emit("tile:dragstart", { tile: this });

        var onMove: MouseEvent->Void = null;
        var onUp:   MouseEvent->Void = null;
        onMove = function(me: MouseEvent) { onDragMove(me); };
        onUp   = function(me: MouseEvent) {
            onDragEnd(me);
            Browser.document.removeEventListener("mousemove", onMove);
            Browser.document.removeEventListener("mouseup",   onUp);
        };
        Browser.document.addEventListener("mousemove", onMove);
        Browser.document.addEventListener("mouseup",   onUp);
    }

    function onDragMove(e: MouseEvent): Void {
        if (!dragging || dragGhost == null) return;

        // Move the ghost so it tracks the cursor precisely
        dragGhost.style.left = (e.clientX - dragOffsetX) + "px";
        dragGhost.style.top  = (e.clientY - dragOffsetY) + "px";

        // Ask the grid to update the drop-target preview
        bus.emit("tile:dragmove", { tile: this, x: e.clientX, y: e.clientY });
    }

    function onDragEnd(e: MouseEvent): Void {
        dragging = false;
        cleanupGhost();
        element.style.opacity = "";
        bus.emit("tile:dragend", { tile: this, x: e.clientX, y: e.clientY });
    }

    function cleanupGhost(): Void {
        if (dragGhost != null) {
            if (dragGhost.parentNode != null)
                dragGhost.parentNode.removeChild(dragGhost);
            dragGhost = null;
        }
    }

    // ─── Resize ───────────────────────────────────────────────────────────────

    function onResizeStart(e: MouseEvent): Void {
        if (!grid.editMode) return;
        e.preventDefault();
        e.stopPropagation();

        var startX  = e.clientX;
        var startY  = e.clientY;
        var startCols = colspan;
        var startRows = rowspan;
        var cellW = grid.getCellWidth();
        var cellH = grid.getCellHeight();

        element.style.boxShadow =
            "0 0 0 2px rgba(0,212,255,0.5), 0 12px 40px rgba(0,0,0,0.6)";

        var onMove: MouseEvent->Void = null;
        var onUp:   MouseEvent->Void = null;
        onMove = function(me: MouseEvent) {
            var dx = me.clientX - startX;
            var dy = me.clientY - startY;
            var newCols = Std.int(Math.max(1, startCols + Math.round(dx / cellW)));
            var newRows = Std.int(Math.max(1, startRows + Math.round(dy / cellH)));
            // Clamp to grid boundary
            newCols = Std.int(Math.min(newCols, 12 - col + 1));
            if (newCols != colspan || newRows != rowspan) {
                colspan = newCols;
                rowspan = newRows;
                applyGridPlacement();
                widget.onResize();
            }
        };
        onUp = function(me: MouseEvent) {
            element.style.boxShadow = "";
            Browser.document.removeEventListener("mousemove", onMove);
            Browser.document.removeEventListener("mouseup",   onUp);
            bus.emit("layout:changed", null);
        };
        Browser.document.addEventListener("mousemove", onMove);
        Browser.document.addEventListener("mouseup",   onUp);
    }

    public function serialize(): layout.LayoutSerializer.TileData {
        return {
            type: widget.widgetType,
            col: col, row: row,
            colspan: colspan, rowspan: rowspan,
            props: widget.serialize()
        };
    }
}
