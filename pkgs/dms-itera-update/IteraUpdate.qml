// itera's update indicator, as a DankMaterialShell dank-bar widget.
//
// A machine running itera does not track the itera repository directly. It runs a
// downstream config flake (itera.update.flake, e.g. github:me/my-config) which
// pins itera in ITS flake.lock, so `itera update` — which is `nh os switch <that
// flake> --refresh` — only ever fetches the newest pushed revision of the config
// repo. New itera commits reach the machine when, and only when, somebody bumps
// that lock and pushes it. Nothing surfaced that gap, so framework work could sit
// unpicked-up indefinitely with no signal anywhere on the desktop.
//
// This widget is that signal, and nothing more. It compares two revisions:
//
//   pluginData.lockedRev  the itera revision THIS system was built with. Not
//                         discovered at runtime — modules/nixos/desktop/
//                         update-indicator.nix bakes `self.rev` into
//                         plugin_settings.json at build time, so the widget needs
//                         no checkout, no flake evaluation and no privileges.
//   the remote tip        whatever `itera-update-check` reports for the configured
//                         repository/branch.
//
// It is deliberately READ-ONLY. Everything it could usefully automate — bumping
// the downstream lock, pushing it, rebuilding — spans a git push and a privileged
// rebuild with a lot of partial-failure states in between, so acting on the signal
// stays a deliberate step at a terminal. The only process this file ever spawns is
// `checkCommand`, whose whole job is to print one JSON object.
//
// Configuration is one-way: itera symlinks plugin_settings.json out of the Nix
// store (clobber = true), so `pluginService.savePluginData` cannot persist and
// there is intentionally no settings component in plugin.json. Every knob is an
// `itera.desktop.updateIndicator.*` NixOS option.
import QtQuick
import Quickshell.Io
import qs.Common
import qs.Modules.Plugins
import qs.Widgets

PluginComponent {
    id: root

    // --- Declarative configuration (plugin_settings.json). Read-only; see header.
    readonly property string lockedRev: pluginData.lockedRev ?? ""
    readonly property string lockedRevShort: pluginData.lockedRevShort ?? ""
    // Unix seconds, from the flake input's `lastModified`. 0 when unknown.
    readonly property int lockedDate: pluginData.lockedDate ?? 0
    readonly property string repository: pluginData.repository ?? ""
    readonly property string branch: pluginData.branch ?? "main"
    readonly property string checkCommand: pluginData.checkCommand ?? ""
    readonly property int pollIntervalSeconds: pluginData.pollIntervalSeconds ?? 1800
    readonly property bool hideWhenUpToDate: pluginData.hideWhenUpToDate ?? false

    // --- Observed state, all of it from the last `checkCommand` run.
    property string remoteRev: ""
    // How many commits ahead the remote is. `-1` means "ahead, but the count is
    // unavailable" — the compare API is GitHub-only and best-effort, while the
    // ahead/not-ahead answer only needs the two revisions.
    property int behindBy: -1
    property var commits: []
    property bool bootPending: false
    property string error: ""
    property bool checking: false
    property bool everChecked: false
    property double checkedAt: 0

    // `lockedRev` is empty when itera was consumed from a dirty checkout, where
    // the flake has no revision at all. That is a real state, not a failure: with
    // nothing to compare against, the widget must not claim either answer.
    readonly property bool unknown: lockedRev === ""
    readonly property bool answered: !unknown && remoteRev !== "" && error === ""
    readonly property bool behind: answered && remoteRev !== lockedRev
    readonly property bool current: answered && remoteRev === lockedRev

    readonly property color statusColor: {
        if (error !== "")
            return Theme.error;
        if (unknown)
            return Theme.surfaceVariantText;
        if (behind)
            return Theme.warning;
        if (bootPending)
            return Theme.primary;
        if (current)
            return Theme.success;
        return Theme.surfaceVariantText;
    }

    readonly property string statusIcon: {
        if (error !== "")
            return "sync_problem";
        if (unknown)
            return "help";
        if (behind)
            return "deployed_code_update";
        if (bootPending)
            return "restart_alt";
        return "deployed_code";
    }

    // Only the commit count earns space in the bar; everything else is one glyph.
    readonly property string pillText: (behind && behindBy > 0) ? String(behindBy) : ""

    readonly property string summary: {
        if (error !== "")
            return error;
        if (unknown)
            return "Built from a dirty itera checkout — no revision to compare.";
        if (!everChecked || (!answered && !behind))
            return "Checking…";
        if (behind)
            return behindBy > 0 ? (behindBy + (behindBy === 1 ? " commit behind" : " commits behind")) : "Behind";
        return "Up to date";
    }

    function formatEpoch(seconds) {
        if (!seconds)
            return "unknown";
        return Qt.formatDateTime(new Date(seconds * 1000), "yyyy-MM-dd hh:mm");
    }

    function check() {
        if (checkCommand === "" || checking)
            return;
        checking = true;
        checkProcess.running = true;
    }

    // A private Process rather than the shared `Proc.runCommand` helper, and not
    // for style: DankBar instantiates this component once per bar, so on a
    // multi-monitor setup several copies run side by side. Proc keys its
    // in-flight commands by the id string passed to it, so every copy asking for
    // the same id collapses onto ONE registration and only the last one to
    // register ever gets its callback — leaving every other bar's pill frozen in
    // its pre-check state. Owning the process here keeps the instances
    // independent.
    Process {
        id: checkProcess

        command: [root.checkCommand]
        running: false

        stdout: StdioCollector {
            id: checkOutput
        }

        onExited: exitCode => {
            root.checking = false;
            root.everChecked = true;
            let data = null;
            try {
                data = JSON.parse(checkOutput.text);
            } catch (e) {
                data = null;
            }
            if (!data) {
                // The helper emits valid JSON on every path it knows about, so no
                // parse means it did not run at all (missing, or killed).
                root.error = "the update check produced no usable output (exit " + exitCode + ")";
                return;
            }
            root.remoteRev = data.remoteRev ?? "";
            root.behindBy = (typeof data.behindBy === "number") ? data.behindBy : -1;
            root.commits = data.commits ?? [];
            root.bootPending = data.bootPending ?? false;
            root.error = data.error ?? "";
            root.checkedAt = data.checkedAt ?? 0;
        }
    }

    // Collapse the pill to nothing when there is nothing to say. `bootPending` and
    // failures still show: both are things the user asked to be told about.
    function applyVisibility() {
        setVisibilityOverride(!(hideWhenUpToDate && current && !bootPending));
    }

    onCurrentChanged: applyVisibility()
    onBootPendingChanged: applyVisibility()
    onHideWhenUpToDateChanged: applyVisibility()

    Component.onCompleted: applyVisibility()

    Timer {
        // Floor the interval: the widget is a background poller against somebody
        // else's server, and a mis-set option should not turn it into a hammer.
        interval: Math.max(60, root.pollIntervalSeconds) * 1000
        repeat: true
        running: root.checkCommand !== ""
        triggeredOnStart: true
        onTriggered: root.check()
    }

    popoutWidth: 440
    // Header + the fixed detail rows + one line per listed commit, capped so a
    // wide compare never grows the popout past the screen.
    popoutHeight: Math.min(560, 230 + Math.min(root.commits.length, 10) * 34)

    horizontalBarPill: Component {
        Item {
            implicitWidth: pillRow.implicitWidth
            implicitHeight: pillRow.implicitHeight
            width: implicitWidth
            height: implicitHeight

            Row {
                id: pillRow

                spacing: Theme.spacingXS

                DankIcon {
                    name: root.statusIcon
                    size: root.iconSize
                    color: root.statusColor
                    anchors.verticalCenter: parent.verticalCenter
                }

                StyledText {
                    text: root.pillText
                    color: root.statusColor
                    font.pixelSize: Theme.barTextSize(root.barThickness, root.barConfig?.fontScale, root.barConfig?.maximizeWidgetText)
                    anchors.verticalCenter: parent.verticalCenter
                    visible: root.pillText !== ""
                }
            }
        }
    }

    verticalBarPill: Component {
        Item {
            implicitWidth: pillColumn.implicitWidth
            implicitHeight: pillColumn.implicitHeight
            width: implicitWidth
            height: implicitHeight

            Column {
                id: pillColumn

                spacing: Theme.spacingXS

                DankIcon {
                    name: root.statusIcon
                    size: root.iconSize
                    color: root.statusColor
                    anchors.horizontalCenter: parent.horizontalCenter
                }

                StyledText {
                    text: root.pillText
                    color: root.statusColor
                    font.pixelSize: Theme.barTextSize(root.barThickness, root.barConfig?.fontScale, root.barConfig?.maximizeWidgetText)
                    anchors.horizontalCenter: parent.horizontalCenter
                    visible: root.pillText !== ""
                }
            }
        }
    }

    popoutContent: Component {
        FocusScope {
            width: parent ? parent.width : 0
            implicitHeight: mainContent.implicitHeight

            PopoutComponent {
                id: mainContent

                width: parent.width
                headerText: "itera"
                detailsText: root.summary
                showCloseButton: false

                headerActions: Component {
                    Rectangle {
                        width: 32
                        height: 32
                        radius: 16
                        color: refreshArea.containsMouse ? Theme.surfaceContainerHigh : "transparent"
                        anchors.verticalCenter: parent.verticalCenter

                        DankIcon {
                            anchors.centerIn: parent
                            name: "refresh"
                            size: Theme.iconSizeSmall
                            color: root.checking ? Theme.surfaceVariantText : Theme.surfaceText
                        }

                        MouseArea {
                            id: refreshArea

                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.check()
                        }
                    }
                }

                Column {
                    width: parent.width
                    spacing: Theme.spacingM

                    // Revisions.
                    StyledRect {
                        width: parent.width
                        height: revisionColumn.implicitHeight + Theme.spacingM * 2
                        color: Theme.surfaceContainerHigh
                        radius: Theme.cornerRadius
                        border.color: Qt.rgba(Theme.outline.r, Theme.outline.g, Theme.outline.b, 0.1)
                        border.width: 1

                        Column {
                            id: revisionColumn

                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.top: parent.top
                            anchors.margins: Theme.spacingM
                            spacing: Theme.spacingXS

                            Row {
                                width: parent.width
                                spacing: Theme.spacingS

                                StyledText {
                                    text: "This system"
                                    color: Theme.surfaceVariantText
                                    font.pixelSize: Theme.fontSizeSmall
                                    width: 92
                                }

                                StyledText {
                                    text: root.unknown ? "dirty checkout" : (root.lockedRevShort || root.lockedRev.substring(0, 7))
                                    color: Theme.surfaceText
                                    font.pixelSize: Theme.fontSizeSmall
                                }

                                StyledText {
                                    text: root.lockedDate ? "· " + root.formatEpoch(root.lockedDate) : ""
                                    color: Theme.surfaceVariantText
                                    font.pixelSize: Theme.fontSizeSmall
                                    visible: text !== ""
                                }
                            }

                            Row {
                                width: parent.width
                                spacing: Theme.spacingS

                                StyledText {
                                    text: root.branch
                                    color: Theme.surfaceVariantText
                                    font.pixelSize: Theme.fontSizeSmall
                                    width: 92
                                    elide: Text.ElideRight
                                }

                                StyledText {
                                    text: root.remoteRev !== "" ? root.remoteRev.substring(0, 7) : "—"
                                    color: root.behind ? Theme.warning : Theme.surfaceText
                                    font.pixelSize: Theme.fontSizeSmall
                                }
                            }

                            StyledText {
                                width: parent.width
                                text: root.repository
                                color: Theme.surfaceVariantText
                                font.pixelSize: Theme.fontSizeSmall
                                elide: Text.ElideMiddle
                            }
                        }
                    }

                    // What changed. Absent when up to date, and absent when the
                    // remote is ahead but the compare API could not be reached —
                    // an empty list would read as "nothing changed", which is the
                    // opposite of what we know.
                    StyledRect {
                        width: parent.width
                        height: commitColumn.implicitHeight + Theme.spacingM * 2
                        color: Theme.surfaceContainerHigh
                        radius: Theme.cornerRadius
                        border.color: Qt.rgba(Theme.outline.r, Theme.outline.g, Theme.outline.b, 0.1)
                        border.width: 1
                        visible: root.commits.length > 0

                        Column {
                            id: commitColumn

                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.top: parent.top
                            anchors.margins: Theme.spacingM
                            spacing: Theme.spacingXS

                            Repeater {
                                model: root.commits

                                Row {
                                    width: commitColumn.width
                                    spacing: Theme.spacingS

                                    StyledText {
                                        text: modelData.sha ?? ""
                                        color: Theme.surfaceVariantText
                                        font.pixelSize: Theme.fontSizeSmall
                                        width: 60
                                    }

                                    // One line each, elided: `popoutHeight` above
                                    // budgets a fixed height per commit, and a
                                    // subject allowed to wrap would push the last
                                    // rows out of the popout.
                                    StyledText {
                                        text: modelData.subject ?? ""
                                        color: Theme.surfaceText
                                        font.pixelSize: Theme.fontSizeSmall
                                        width: parent.width - 60 - Theme.spacingS
                                        wrapMode: Text.NoWrap
                                        elide: Text.ElideRight
                                    }
                                }
                            }
                        }
                    }

                    // A staged generation is a different fact from "itera moved
                    // on", and the only one the user can act on without a network.
                    Row {
                        width: parent.width
                        spacing: Theme.spacingS
                        visible: root.bootPending

                        DankIcon {
                            name: "restart_alt"
                            size: Theme.iconSizeSmall
                            color: Theme.primary
                            anchors.verticalCenter: parent.verticalCenter
                        }

                        StyledText {
                            text: "A newer generation is staged — reboot to apply it."
                            color: Theme.primary
                            font.pixelSize: Theme.fontSizeSmall
                            anchors.verticalCenter: parent.verticalCenter
                        }
                    }

                    // The widget does not run this; it shows it. Selectable so it
                    // can be copied straight into a terminal.
                    Column {
                        width: parent.width
                        spacing: Theme.spacingXS
                        visible: root.behind

                        StyledText {
                            text: "To pick this up, bump itera in your config flake, push, then:"
                            color: Theme.surfaceVariantText
                            font.pixelSize: Theme.fontSizeSmall
                            width: parent.width
                            wrapMode: Text.WordWrap
                        }

                        StyledRect {
                            width: parent.width
                            height: commandText.implicitHeight + Theme.spacingS * 2
                            color: Theme.surfaceContainerHigh
                            radius: Theme.cornerRadius

                            TextEdit {
                                id: commandText

                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                anchors.margins: Theme.spacingS
                                text: "itera update-boot"
                                color: Theme.surfaceText
                                font.pixelSize: Theme.fontSizeSmall
                                font.family: "monospace"
                                readOnly: true
                                selectByMouse: true
                                wrapMode: TextEdit.NoWrap
                            }
                        }
                    }

                    StyledText {
                        width: parent.width
                        text: root.checkedAt ? "Checked " + root.formatEpoch(root.checkedAt) : ""
                        color: Theme.surfaceVariantText
                        font.pixelSize: Theme.fontSizeSmall
                        visible: text !== ""
                    }
                }
            }
        }
    }
}
