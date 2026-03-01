package core;

import js.Browser;

typedef ConnectionInfo = { host: String, port: Int }

/**
 * Application-level state: connection prefs, tabs, layout prefs.
 * Persisted to localStorage.
 */
class AppState {
    static inline var LS_KEY_CONN = "frc-dash-connection";
    static inline var LS_KEY_TAB  = "frc-dash-active-tab";
    static inline var LS_KEY_THEME = "frc-dash-theme";

    public var ntClient: NT4Client;
    public var editMode: Bool = false;
    public var activeTabIndex: Int = 0;
    public var theme: String = "dark";

    public function new() {
        theme = loadString(LS_KEY_THEME, "dark");
        activeTabIndex = Std.parseInt(loadString(LS_KEY_TAB, "0"));
        if (activeTabIndex == null) activeTabIndex = 0;
    }

    // ─── Connection ──────────────────────────────────────────────────────────

    public function saveConnection(host: String, port: Int): Void {
        saveString(LS_KEY_CONN, haxe.Json.stringify({ host: host, port: port }));
    }

    public function getLastConnection(): Null<ConnectionInfo> {
        var s = loadString(LS_KEY_CONN, null);
        if (s == null) return null;
        try { return haxe.Json.parse(s); } catch (_) { return null; }
    }

    // ─── Theme ───────────────────────────────────────────────────────────────

    public function saveTheme(t: String): Void {
        theme = t;
        saveString(LS_KEY_THEME, t);
    }

    // ─── Tab ─────────────────────────────────────────────────────────────────

    public function saveActiveTab(idx: Int): Void {
        activeTabIndex = idx;
        saveString(LS_KEY_TAB, Std.string(idx));
    }

    // ─── Helpers ─────────────────────────────────────────────────────────────

    static function saveString(key: String, value: String): Void {
        try { Browser.window.localStorage.setItem(key, value); } catch (_) {}
    }

    static function loadString(key: String, def: String): String {
        try {
            var v = Browser.window.localStorage.getItem(key);
            return v != null ? v : def;
        } catch (_) { return def; }
    }
}
