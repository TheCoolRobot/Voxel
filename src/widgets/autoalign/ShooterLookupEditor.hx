package widgets.autoalign;

import js.html.Element;
import js.html.TableElement;
import util.EventBus;

typedef ShooterRow = { dist: Float, angle: Float, rpm: Float }

/**
 * Editable shooter lookup table. Reads + writes back to NT as JSON string.
 */
class ShooterLookupEditor {
    public var element: Element;
    var tableBody: Element;
    var rows: Array<ShooterRow> = [];
    var ntTopic: String = "/SmartDashboard/ShooterTable";
    var bus: EventBus;
    var onPublish: String->Dynamic->String->Void;

    public function new(bus: EventBus, onPublish: String->Dynamic->String->Void) {
        this.bus = bus;
        this.onPublish = onPublish;
        buildDOM();
    }

    function buildDOM(): Void {
        element = js.Browser.document.createElement("div");
        element.className = "shooter-lookup";

        // Header
        var header = js.Browser.document.createElement("div");
        header.className = "shooter-lookup-header";
        var titleSpan = js.Browser.document.createElement("span");
        titleSpan.textContent = "Shooter Lookup Table";
        header.appendChild(titleSpan);

        var actions = js.Browser.document.createElement("div");
        actions.className = "slt-actions";

        var addBtn = makeBtn("+", function() { addRow(); });
        var expBtn = makeBtn("CSV ↑", function() { exportCsv(); });
        var impBtn = makeBtn("CSV ↓", function() { importCsv(); });
        actions.appendChild(addBtn);
        actions.appendChild(expBtn);
        actions.appendChild(impBtn);
        header.appendChild(actions);
        element.appendChild(header);

        // Scrollable table
        var scroll = js.Browser.document.createElement("div");
        scroll.className = "slt-scroll";
        var table = cast(js.Browser.document.createElement("table"), TableElement);
        table.className = "slt-table";

        var thead = js.Browser.document.createElement("thead");
        thead.innerHTML = '<tr><th>Dist (m)</th><th>Angle (°)</th><th>RPM</th><th></th></tr>';
        table.appendChild(thead);

        tableBody = js.Browser.document.createElement("tbody");
        table.appendChild(tableBody);
        scroll.appendChild(table);
        element.appendChild(scroll);
    }

    public function setTopic(topic: String): Void {
        ntTopic = topic;
    }

    public function loadFromNT(value: Dynamic): Void {
        try {
            var data: Array<Dynamic>;
            if (Std.isOfType(value, String)) {
                data = haxe.Json.parse(value);
            } else if (Std.isOfType(value, Array)) {
                data = value;
            } else return;

            rows = [];
            for (item in data) {
                rows.push({
                    dist:  cast item.dist  != null ? item.dist  : item.d,
                    angle: cast item.angle != null ? item.angle : item.a,
                    rpm:   cast item.rpm   != null ? item.rpm   : item.r
                });
            }
            // Sort by distance
            rows.sort(function(a, b) return a.dist < b.dist ? -1 : (a.dist > b.dist ? 1 : 0));
            rebuildTable();
        } catch (e: Dynamic) {
            trace("ShooterLookupEditor: parse error: " + e);
        }
    }

    function rebuildTable(): Void {
        if (tableBody == null) return;
        tableBody.innerHTML = "";
        for (i in 0...rows.length) {
            appendRow(i);
        }
    }

    function appendRow(idx: Int): Void {
        var row = rows[idx];
        var tr = js.Browser.document.createElement("tr");

        for (field in ["dist", "angle", "rpm"]) {
            var td = js.Browser.document.createElement("td");
            td.className = "editable";
            var val: Float = Reflect.field(row, field);
            td.textContent = Std.string(Math.round(val * 10) / 10);
            var f = field;
            var i = idx;
            td.addEventListener("dblclick", function(e: js.html.MouseEvent) {
                e.stopPropagation();
                startEdit(td, i, f);
            });
            tr.appendChild(td);
        }

        // Actions
        var tdAct = js.Browser.document.createElement("td");
        var delBtn = makeBtn("✕", function() { deleteRow(idx); });
        delBtn.className = "row-btn";
        tdAct.appendChild(delBtn);
        tr.appendChild(tdAct);

        tableBody.appendChild(tr);
    }

    function startEdit(td: Element, rowIdx: Int, field: String): Void {
        var current = Reflect.field(rows[rowIdx], field);
        var input = cast(js.Browser.document.createElement("input"), js.html.InputElement);
        input.type = "number";
        input.value = Std.string(current);
        input.step = "0.1";
        input.style.width = "70px";
        td.innerHTML = "";
        td.appendChild(input);
        input.focus();
        input.select();

        var commit = function() {
            var v = Std.parseFloat(input.value);
            if (Math.isNaN(v)) v = current;
            Reflect.setField(rows[rowIdx], field, v);
            td.textContent = Std.string(Math.round(v * 10) / 10);
            publishTable();
        };

        input.addEventListener("blur",  function(_) { commit(); });
        input.addEventListener("keydown", function(e: js.html.KeyboardEvent) {
            if (e.key == "Enter")  { commit(); e.preventDefault(); }
            if (e.key == "Escape") { td.textContent = Std.string(current); }
        });
    }

    function addRow(): Void {
        var lastDist = rows.length > 0 ? rows[rows.length-1].dist + 0.5 : 1.0;
        rows.push({ dist: lastDist, angle: 40.0, rpm: 2000.0 });
        rebuildTable();
        publishTable();
    }

    function deleteRow(idx: Int): Void {
        rows.splice(idx, 1);
        rebuildTable();
        publishTable();
    }

    function publishTable(): Void {
        var json = haxe.Json.stringify(rows);
        onPublish(ntTopic, json, "string");
    }

    function exportCsv(): Void {
        var csv = "dist_m,angle_deg,rpm\n";
        for (r in rows) csv += r.dist + "," + r.angle + "," + r.rpm + "\n";
        // Use untyped for global JS function
        var encoded: String = untyped encodeURIComponent(csv);
        var url = "data:text/csv;charset=utf-8," + encoded;
        var a = cast(js.Browser.document.createElement("a"), js.html.AnchorElement);
        a.href = url;
        a.download = "shooter-table.csv";
        a.click();
    }

    function importCsv(): Void {
        var input = cast(js.Browser.document.createElement("input"), js.html.InputElement);
        input.type = "file";
        input.accept = ".csv";
        input.addEventListener("change", function(_) {
            var file = input.files.item(0);
            if (file == null) return;
            var reader = new js.html.FileReader();
            reader.onload = function(e) {
                var text: String = Reflect.field(Reflect.field(e, "target"), "result");
                parseCsv(text);
            };
            reader.readAsText(file);
        });
        input.click();
    }

    function parseCsv(text: String): Void {
        var lines = text.split("\n");
        rows = [];
        var first = true;
        for (line in lines) {
            if (first) { first = false; continue; } // skip header
            var parts = StringTools.trim(line).split(",");
            if (parts.length < 3) continue;
            var d = Std.parseFloat(parts[0]);
            var a = Std.parseFloat(parts[1]);
            var r = Std.parseFloat(parts[2]);
            if (!Math.isNaN(d) && !Math.isNaN(a) && !Math.isNaN(r))
                rows.push({ dist: d, angle: a, rpm: r });
        }
        rows.sort(function(a, b) return a.dist < b.dist ? -1 : 1);
        rebuildTable();
        publishTable();
    }

    function makeBtn(label: String, onClick: Void->Void): Element {
        var btn = js.Browser.document.createElement("button");
        btn.className = "slt-btn";
        btn.textContent = label;
        btn.addEventListener("click", function(_) { onClick(); });
        return btn;
    }

    public function serialize(): Dynamic {
        return { topic: ntTopic };
    }
}
