// itera's MangoWC layout chooser, as a DankMaterialShell launcher plugin.
//
// SUPER+SHIFT+n cycles the focused tag's layout one step at a time; this lists
// every layout in the launcher (trigger `#layout`, SUPER+CTRL+n) so one can be
// picked by name. DMS's own bar `layout` widget does the same from the bar.
//
// Everything comes from plugin_settings.json, written by
// modules/nixos/desktop/dankmaterialshell.nix: `layouts` is
// iteraLib.mango.supportedLayouts and `mmsg` is the absolute path to mango's IPC
// client, so nothing depends on PATH.
import QtQuick
import Quickshell

Item {
    id: root

    property var pluginService: null

    // Kept in step with plugin.json, which is what DMS actually reads.
    property string trigger: "#layout"

    signal itemsChanged

    function setting(key, fallback) {
        return pluginService ? pluginService.loadPluginData("layoutChooser", key, fallback) : fallback;
    }

    function getItems(query) {
        const items = root.setting("layouts", []).map(layout => ({
                    name: layout.replace(/_/g, " "),
                    icon: "material:view_quilt",
                    comment: "Set the focused tag's layout",
                    action: layout,
                    categories: ["Layout"]
                }));

        if (!query || query.length === 0)
            return items;

        const lowerQuery = query.toLowerCase();
        return items.filter(item => item.name.includes(lowerQuery) || item.action.includes(lowerQuery));
    }

    function executeItem(item) {
        const mmsg = root.setting("mmsg", "");
        if (!item || !item.action || mmsg === "")
            return;
        // `setlayout` with no output acts on the focused monitor's current tag.
        Quickshell.execDetached([mmsg, "dispatch", "setlayout," + item.action]);
    }
}
