package ui;

import js.Browser;
import core.AppState;

/**
 * Switches between dark and light CSS themes.
 */
class ThemeManager {
    static var _instance: ThemeManager;
    public static var instance(get, never): ThemeManager;
    static function get_instance(): ThemeManager {
        if (_instance == null) _instance = new ThemeManager();
        return _instance;
    }

    var currentTheme: String = "dark";

    public function new() {}

    public function apply(?theme: String): Void {
        if (theme != null) currentTheme = theme;
        var link = Browser.document.getElementById("theme-css");
        if (link == null) return;
        cast(link, js.html.LinkElement).href = 'assets/themes/${currentTheme}.css';
    }

    public function toggle(): Void {
        apply(currentTheme == "dark" ? "light" : "dark");
    }

    public function getTheme(): String return currentTheme;
}
