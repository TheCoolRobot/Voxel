package layout;

import js.Browser;

typedef TileData = {
    var type: String;
    var col: Int;
    var row: Int;
    var colspan: Int;
    var rowspan: Int;
    var props: Dynamic;
}

typedef TabData = {
    var name: String;
    var tiles: Array<TileData>;
}

typedef LayoutData = {
    var version: Int;
    var tabs: Array<TabData>;
}

/**
 * JSON layout save/load using localStorage (JS target).
 */
class LayoutSerializer {
    static inline var LS_KEY = "frc-dash-layout";

    public static function save(layout: LayoutData): Void {
        try {
            Browser.window.localStorage.setItem(LS_KEY, haxe.Json.stringify(layout));
        } catch (e: Dynamic) {
            trace("LayoutSerializer: save failed: " + e);
        }
    }

    public static function load(): Null<LayoutData> {
        try {
            var s = Browser.window.localStorage.getItem(LS_KEY);
            if (s == null) return null;
            var d: LayoutData = haxe.Json.parse(s);
            return d;
        } catch (e: Dynamic) {
            trace("LayoutSerializer: load failed: " + e);
            return null;
        }
    }

    public static function loadDefault(): Null<LayoutData> {
        // Load from the bundled default.json via XHR
        try {
            var xhr = new js.html.XMLHttpRequest();
            xhr.open("GET", "layouts/default.json", false);
            xhr.send();
            if (xhr.status == 200) {
                return haxe.Json.parse(xhr.responseText);
            }
        } catch (e: Dynamic) {
            trace("LayoutSerializer: loadDefault failed: " + e);
        }
        return buildFallbackLayout();
    }

    public static function exportJson(layout: LayoutData): String {
        return haxe.Json.stringify(layout, null, "  ");
    }

    public static function importJson(json: String): Null<LayoutData> {
        try {
            return haxe.Json.parse(json);
        } catch (e: Dynamic) {
            trace("LayoutSerializer: importJson failed: " + e);
            return null;
        }
    }

    static function buildFallbackLayout(): LayoutData {
        return {
            version: 1,
            tabs: [{
                name: "Dashboard",
                tiles: [
                    { type: "MatchTime",   col: 1, row: 1, colspan: 2, rowspan: 2, props: { title: "Match Time", topic: "/DriverStation/MatchTime" } },
                    { type: "NumberDisplay", col: 3, row: 1, colspan: 2, rowspan: 1, props: { title: "Value", topic: "/SmartDashboard/Value" } }
                ]
            }]
        };
    }
}
