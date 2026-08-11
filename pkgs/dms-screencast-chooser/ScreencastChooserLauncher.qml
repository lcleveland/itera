// itera's screencast source picker, as a DankMaterialShell launcher plugin.
//
// xdg-desktop-portal-wlr cannot start a screencast until something tells it WHICH
// source to capture. Its built-in fallback is a bare `slurp` crosshair with no
// prompt, and when that is dismissed it walks a list of dmenu programs itera does
// not ship — so every request ended in `wlroots: no output found`. This plugin is
// the picker instead: DMS's own launcher, themed and searchable, listing the exact
// labels xdpw offered.
//
// It is driven by `itera-screencast-chooser` (the `chooser_cmd` registered in
// `modules/nixos/desktop/screencast.nix`), which is what xdpw actually execs. The
// handoff is two files under $XDG_RUNTIME_DIR/itera-screencast-chooser:
//
//   sources — written by the wrapper before it opens the launcher: the label list
//             xdpw piped to it on stdin, one per line ("Monitor: eDP-1",
//             "Window: Some Title", …).
//   choice  — written by THIS plugin when the user picks: the chosen label. The
//             wrapper polls for it and prints it back to xdpw on stdout.
//
// Why files and not IPC: no documented DMS API hands a user's selection back to a
// CLI caller. Every `dms ipc call` function returns a fixed status token
// immediately — a QML IpcHandler function is synchronous on the GUI thread and
// cannot await input. `qs ipc wait <target> <signal>` would fit, but it is absent
// from Quickshell's published IpcHandler docs and DMS declares no IPC signals, so
// this deliberately stays on documented ground: the launcher plugin interface
// (getItems/executeItem) plus `dms ipc call spotlight openQuery`.
import QtQuick
import Quickshell
import Quickshell.Io

Item {
    id: root

    property var pluginService: null

    // Kept in step with plugin.json, which is what DMS actually reads
    // (getPluginTrigger falls back to the manifest's `trigger`).
    //
    // The launcher dispatches on the first trigger that prefixes the query, in
    // plugin load order, so another launcher plugin triggered on a bare "#" would
    // shadow this one. itera ships no such plugin — DMS's built-in triggers are
    // checked only after plugin triggers, so they cannot — but a user who installs
    // one may need to re-point either trigger in DMS settings.
    property string trigger: "#share"

    signal itemsChanged

    readonly property string runtimeDir: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/itera-screencast-chooser"

    // The label list for the request currently in flight.
    //
    // DMS keeps ONE instance of a launcher plugin alive for the whole session
    // (PluginService instantiates the launcher surface at load time), so this file
    // is re-read per request rather than cached at startup — the labels differ every
    // time, and a window that has since closed must not be offered again.
    FileView {
        id: sourcesFile

        path: root.runtimeDir + "/sources"
        // `getItems()` must return an array synchronously, so the read cannot be
        // async: blockLoading/blockAllReads make text() wait for the load instead of
        // returning the previous request's contents.
        blockLoading: true
        blockAllReads: true
        watchChanges: true
        // The file only exists while a screencast request is in flight; missing is
        // the normal resting state, not something to log about.
        printErrors: false

        onFileChanged: reload()
        onLoaded: root.itemsChanged()
    }

    function getItems(query) {
        // Re-read on every keystroke: cheap (a handful of short lines) and it is the
        // only thing guaranteeing the list belongs to THIS request.
        sourcesFile.reload();

        let raw = "";
        try {
            raw = sourcesFile.text();
        } catch (e) {
            // No request in flight — nothing to offer.
            return [];
        }

        const labels = raw.split("\n").map(line => line.trim()).filter(line => line.length > 0);

        const items = labels.map(label => ({
                    // The label IS the payload. xdpw compares the chooser's stdout against
                    // the lines it piped in with strcmp, so it has to survive round-trip
                    // untouched — never reformat it for display.
                    name: label,
                    icon: label.startsWith("Window:") ? "material:web_asset" : "material:monitor",
                    comment: label.startsWith("Window:") ? "Share this window" : "Share this whole screen",
                    action: label,
                    categories: ["Screencast"]
                }));

        if (!query || query.length === 0) {
            return items;
        }

        const lowerQuery = query.toLowerCase();
        return items.filter(item => item.name.toLowerCase().includes(lowerQuery));
    }

    function executeItem(item) {
        if (!item || !item.action) {
            return;
        }

        // Write via a temp file and rename so the wrapper's poll can never catch a
        // half-written label. Arguments go through argv rather than the command
        // string — window titles are arbitrary user text and would otherwise need
        // shell quoting.
        Quickshell.execDetached(["sh", "-c", "printf '%s\\n' \"$1\" > \"$2.tmp\" && mv \"$2.tmp\" \"$2\"", "sh", item.action, root.runtimeDir + "/choice"]);
    }
}
