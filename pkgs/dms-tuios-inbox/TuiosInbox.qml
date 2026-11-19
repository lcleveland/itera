// tuios's Inbox (what agents wait on you for, in every session) as a dank-bar
// widget: hidden while the Inbox is empty, a count coloured by the most urgent
// item otherwise, and a popout listing the items. Clicking one focuses its pane
// and raises the terminal.
//
// Live without polling: `tuios subscribe --types attention` prints a line per
// Inbox change, and each line re-reads `tuios list-attention --json`. If the
// daemon is not running, subscribe exits and is retried.
//
// Read-only on purpose: tuios lets only the person at a client dismiss items, and
// answering prompts stays in tuios. pluginData.tuios is the tuios binary, set by
// modules/nixos/desktop/tuios.nix.
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Common
import qs.Modules.Plugins
import qs.Widgets

PluginComponent {
    id: root

    readonly property string tuios: pluginData.tuios ?? "tuios"
    property var items: []

    // The agent is blocked on these; errored is worse, the rest can wait.
    readonly property var blocking: ["approval", "plan", "question", "ask"]
    function kindColor(kind) {
        if (kind === "errored")
            return Theme.error;
        if (blocking.includes(kind))
            return Theme.warning;
        return Theme.surfaceVariantText;
    }
    readonly property color statusColor: items.some(i => i.kind === "errored") ? Theme.error : items.some(i => blocking.includes(i.kind)) ? Theme.warning : Theme.surfaceVariantText

    onItemsChanged: setVisibilityOverride(items.length > 0)
    Component.onCompleted: setVisibilityOverride(false)

    // A change during a read re-reads once it ends, so none is missed.
    property bool stale: false
    function refresh() {
        if (listProcess.running)
            stale = true;
        else
            listProcess.running = true;
    }

    function jump(item) {
        Quickshell.execDetached([tuios, "focus-window", item.window, "-s", item.session]);
        // shortcut: raises the first WezTerm window (the terminal battery's); a
        // tuios client in another terminal is focused inside tuios but not raised.
        const term = ToplevelManager.toplevels.values.find(t => t.appId === "org.wezfurlong.wezterm");
        if (term)
            term.activate();
        closePopout();
    }

    // Private Processes, not Proc.runCommand: one instance per bar, and Proc
    // collapses same-id commands onto the last caller (see IteraUpdate.qml).
    Process {
        id: listProcess
        command: [root.tuios, "list-attention", "--json"]
        stdout: StdioCollector {
            id: listOutput
        }
        onExited: {
            try {
                root.items = JSON.parse(listOutput.text).items ?? [];
            } catch (e) {
                root.items = [];
            }
            if (root.stale) {
                root.stale = false;
                running = true;
            }
        }
    }

    Process {
        id: subscribeProcess
        command: [root.tuios, "subscribe", "--types", "attention"]
        running: true
        stdout: SplitParser {
            onRead: root.refresh()
        }
        onExited: retry.start()
    }

    Timer {
        id: retry
        interval: 5000
        onTriggered: subscribeProcess.running = true
    }

    popoutWidth: 440
    popoutHeight: Math.min(560, 90 + items.length * 56)

    horizontalBarPill: Component {
        Row {
            spacing: Theme.spacingXS
            DankIcon {
                name: "inbox"
                size: root.iconSize
                color: root.statusColor
                anchors.verticalCenter: parent.verticalCenter
            }
            StyledText {
                text: root.items.length
                color: root.statusColor
                font.pixelSize: Theme.barTextSize(root.barThickness, root.barConfig?.fontScale, root.barConfig?.maximizeWidgetText)
                anchors.verticalCenter: parent.verticalCenter
            }
        }
    }

    verticalBarPill: Component {
        Column {
            spacing: Theme.spacingXS
            DankIcon {
                name: "inbox"
                size: root.iconSize
                color: root.statusColor
                anchors.horizontalCenter: parent.horizontalCenter
            }
            StyledText {
                text: root.items.length
                color: root.statusColor
                font.pixelSize: Theme.barTextSize(root.barThickness, root.barConfig?.fontScale, root.barConfig?.maximizeWidgetText)
                anchors.horizontalCenter: parent.horizontalCenter
            }
        }
    }

    popoutContent: Component {
        PopoutComponent {
            width: parent ? parent.width : 0
            headerText: "tuios Inbox"
            detailsText: root.items.length + " waiting"
            showCloseButton: false

            Column {
                width: parent.width
                spacing: Theme.spacingXS

                Repeater {
                    model: root.items

                    StyledRect {
                        width: parent.width
                        height: 50
                        radius: Theme.cornerRadius
                        color: rowArea.containsMouse ? Theme.surfaceContainerHighest : Theme.surfaceContainerHigh

                        Column {
                            anchors.fill: parent
                            anchors.margins: Theme.spacingS

                            StyledText {
                                width: parent.width
                                text: modelData.kind + " · " + modelData.session + "/" + (modelData.name ?? "")
                                color: root.kindColor(modelData.kind)
                                font.pixelSize: Theme.fontSizeSmall
                                elide: Text.ElideRight
                            }
                            StyledText {
                                width: parent.width
                                text: modelData.summary ?? ""
                                color: Theme.surfaceText
                                font.pixelSize: Theme.fontSizeSmall
                                elide: Text.ElideRight
                            }
                        }

                        MouseArea {
                            id: rowArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.jump(modelData)
                        }
                    }
                }
            }
        }
    }
}
