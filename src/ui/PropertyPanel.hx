package ui;

import js.html.Element;
import js.Browser;
import layout.WidgetTile;
import util.EventBus;

/**
 * Right-side property panel for configuring the selected widget tile.
 */
class PropertyPanel {
    var panel: Element;
    var bus: EventBus;
    var currentTile: Null<WidgetTile>;
    public var isOpen(default, null): Bool = false;

    public function new(bus: EventBus) {
        this.bus = bus;
        buildDOM();

        bus.on("tile:openProps", function(tile: Dynamic) { openForTile(tile); });
    }

    function buildDOM(): Void {
        panel = Browser.document.createElement("div");
        panel.id = "property-panel";
        Browser.document.body.appendChild(panel);
    }

    public function openForTile(tile: WidgetTile): Void {
        currentTile = tile;
        isOpen = true;
        panel.classList.add("open");
        renderContent();
    }

    function renderContent(): Void {
        panel.innerHTML = "";
        if (currentTile == null) return;

        var widget = currentTile.widget;
        var props = widget.serialize();

        var header = Browser.document.createElement("div");
        header.style.cssText = "display:flex;align-items:center;justify-content:space-between;margin-bottom:12px;";

        var h3 = Browser.document.createElement("h3");
        h3.textContent = widget.widgetType;
        header.appendChild(h3);

        var closeBtn = Browser.document.createElement("button");
        closeBtn.className = "toolbar-btn";
        closeBtn.textContent = "✕";
        closeBtn.style.padding = "2px 6px";
        closeBtn.addEventListener("click", function(_) { close(); });
        header.appendChild(closeBtn);
        panel.appendChild(header);

        // Title field
        addField("Title", "title", widget.title, "text", function(v) {
            currentTile.updateTitle(v);
            bus.emit("layout:changed", null);
        });

        // NT topic(s)
        addField("NT Topic", "topic", widget.ntTopics.join(", "), "text", function(v) {
            var topicArr = v.split(",").map(StringTools.trim);
            widget.ntTopics = topicArr;
            var p = widget.serialize();
            if (topicArr.length > 0) Reflect.setField(p, "topic", topicArr[0]);
            widget.configure(p);
            bus.emit("layout:changed", null);
        });

        // Widget-specific props from serialize()
        var fields = Reflect.fields(props);
        for (f in fields) {
            if (f == "title" || f == "topic") continue;
            var val = Reflect.field(props, f);
            var field = f;
            addField(f, f, Std.string(val), "text", function(v) {
                Reflect.setField(props, field, v);
                widget.configure(props);
                bus.emit("layout:changed", null);
            });
        }

        // Grid position
        addSep("Grid Position");
        addInlineFields([
            { label: "Col",     val: Std.string(currentTile.col),     key: "col"     },
            { label: "Row",     val: Std.string(currentTile.row),     key: "row"     },
            { label: "ColSpan", val: Std.string(currentTile.colspan), key: "colspan" },
            { label: "RowSpan", val: Std.string(currentTile.rowspan), key: "rowspan" }
        ], function(key, v) {
            var n = Std.parseInt(v);
            if (n == null || n < 1) return;
            switch (key) {
                case "col":     currentTile.col     = n;
                case "row":     currentTile.row     = n;
                case "colspan": currentTile.colspan = n;
                case "rowspan": currentTile.rowspan = n;
            }
            currentTile.applyGridPlacement();
            bus.emit("layout:changed", null);
        });
    }

    function addField(label: String, key: String, value: String, type: String, onChange: String->Void): Void {
        var div = Browser.document.createElement("div");
        div.className = "prop-field";
        var lbl = Browser.document.createElement("label");
        lbl.textContent = label;
        div.appendChild(lbl);
        var inp = cast(Browser.document.createElement("input"), js.html.InputElement);
        inp.type = type;
        inp.value = value;
        inp.addEventListener("change", function(_) { onChange(inp.value); });
        div.appendChild(inp);
        panel.appendChild(div);
    }

    function addSep(label: String): Void {
        var div = Browser.document.createElement("div");
        div.style.cssText = "margin:12px 0 6px;padding-top:8px;border-top:1px solid var(--border-color);font-size:10px;color:var(--text-dim);text-transform:uppercase;letter-spacing:0.5px;";
        div.textContent = label;
        panel.appendChild(div);
    }

    function addInlineFields(fields: Array<{label:String, val:String, key:String}>, onChange: String->String->Void): Void {
        var row = Browser.document.createElement("div");
        row.style.cssText = "display:grid;grid-template-columns:1fr 1fr;gap:6px;";
        for (f in fields) {
            var div = Browser.document.createElement("div");
            div.className = "prop-field";
            var lbl = Browser.document.createElement("label");
            lbl.textContent = f.label;
            div.appendChild(lbl);
            var inp = cast(Browser.document.createElement("input"), js.html.InputElement);
            inp.type = "number";
            inp.value = f.val;
            var key = f.key;
            inp.addEventListener("change", function(_) { onChange(key, inp.value); });
            div.appendChild(inp);
            row.appendChild(div);
        }
        panel.appendChild(row);
    }

    public function close(): Void {
        isOpen = false;
        panel.classList.remove("open");
        currentTile = null;
    }
}
