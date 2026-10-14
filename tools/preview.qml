// =============================================================================
// preview.qml
//
// Headless offscreen render for Ardoise marketplace preview and feature screenshots.
// Uses Quickshell offscreen mode to capture pixel-perfect QML artwork.
// Architecture and rendering pipeline inspired by Carmine Paolino's OmaTasks.
// =============================================================================

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import qs.Commons
import qs.Ui
import "plugin" as Plugin
import "plugin/ui" as PluginUi
import "plugin/TodoStore.js" as TodoStore
import "plugin/PanelLogic.js" as Logic
import "plugin/GitSync.js" as GitSync

ShellRoot {
    id: root

    readonly property var sampleStore: ({
        version: 1,
        activeProfile: "work",
        profiles: ["personal", "work"],
        todos: [
            {
                id: 1,
                title: "Fix memory leak in parser AST traversal",
                description: "Profile heap allocations during tree node cleanup",
                done: false,
                profile: "work",
                repo: "omarchy-ardoise",
                tags: ["ui", "parser"],
                reminder: new Date(Date.now() + 2 * 3600000).toISOString(),
                location: { repo: "tablerase/omarchy-ardoise", localPath: "~/Work/tries/omarchy-ardoise" },
                createdAt: 1726930000000
            },
            {
                id: 2,
                title: "Review PR #42 git snapshot search filter",
                description: "Test cross-field matching on message, device, and hash",
                done: false,
                profile: "work",
                repo: "omarchy-ardoise",
                tags: ["git", "search"],
                reminder: new Date(Date.now() + 86400000).toISOString(),
                location: { repo: "tablerase/omarchy-ardoise", localPath: "~/Work/tries/omarchy-ardoise" },
                createdAt: 1726931000000
            },
            {
                id: 3,
                title: "Pick up fresh sourdough bread",
                description: "",
                done: false,
                profile: "personal",
                tags: ["errands"],
                reminder: null,
                createdAt: 1726932000000
            },
            {
                id: 4,
                title: "Setup Lua keybindings configuration engine",
                description: "Provide customizable bindings template with sandbox validation",
                done: true,
                profile: "work",
                tags: ["lua"],
                reminder: null,
                completedAt: Date.now() - 7200000,
                createdAt: 1726920000000
            }
        ]
    })

    // Window 1: Marketplace Banner (preview.png) & Panel (screenshots/panel.png)
    FloatingWindow {
        id: winMain
        visible: true
        implicitWidth: 1600
        implicitHeight: 900
        color: Color.background

        Item {
            id: artwork
            anchors.fill: parent

            readonly property bool isLight: (Color.background.r * 0.299 + Color.background.g * 0.587 + Color.background.b * 0.114) > 0.5
            readonly property color brandPrimaryText: isLight ? Color.foreground : "#f8fafc"
            readonly property color brandSecondaryText: isLight ? Util.alpha(Color.foreground, 0.8) : "#94a3b8"
            readonly property color brandMutedText: isLight ? Util.alpha(Color.foreground, 0.55) : "#64748b"
            readonly property color featureText: isLight ? Color.foreground : "#cbd5e1"
            readonly property color separatorColor: isLight ? Util.alpha(Color.foreground, 0.12) : "#1e293b"

            Canvas {
                anchors.fill: parent
                onPaint: {
                    var ctx = getContext("2d");
                    var g = ctx.createRadialGradient(1140, 450, 40, 1140, 450, 960);
                    if (artwork.isLight) {
                        g.addColorStop(0, Qt.tint(Color.background, Util.alpha(Color.accent, 0.12)).toString());
                        g.addColorStop(0.5, Color.background.toString());
                        g.addColorStop(1, Qt.darker(Color.background, 1.08).toString());
                    } else {
                        g.addColorStop(0, Qt.tint(Color.background, Util.alpha(Color.accent, 0.25)).toString());
                        g.addColorStop(0.5, Qt.darker(Color.background, 1.25).toString());
                        g.addColorStop(1, Qt.darker(Color.background, 1.55).toString());
                    }
                    ctx.fillStyle = g;
                    ctx.fillRect(0, 0, width, height);
                }
            }

            // Left Side: Branding & Features
            Column {
                x: 90
                y: 84
                spacing: Style.space(24)
                width: 640

                Row {
                    spacing: Style.space(12)
                    Rectangle {
                        width: Style.space(10); height: Style.space(10); radius: width / 2
                        color: Color.accent || "#1e66f5"
                        anchors.verticalCenter: parent.verticalCenter
                    }
                    Text {
                        text: "ARDOISE / TABLERASE"
                        color: Color.accent || "#1e66f5"
                        font.family: Style.font.family
                        font.pixelSize: Style.space(17)
                        font.bold: true
                        font.letterSpacing: 4
                    }
                }

                Text {
                    text: "Your task slate,\nright in the bar."
                    color: artwork.brandPrimaryText
                    font.family: "Inter"
                    font.pixelSize: Style.space(68)
                    font.bold: true
                    lineHeight: 1.08
                }

                Text {
                    text: "Instant capture, profile tags, and background reminders.\nWipe the slate clean when you are done."
                    color: artwork.brandSecondaryText
                    font.family: Style.font.family
                    font.pixelSize: Style.space(20)
                    lineHeight: 1.45
                }

                Item { width: 1; height: Style.space(6) }

                Column {
                    spacing: Style.space(17)
                    Repeater {
                        model: [
                            { icon: "󰌌", text: "Vim & keyboard navigation with customizable Lua bindings" },
                            { icon: "󰥔", text: "Natural-language reminders with calendar picker & presets" },
                            { icon: "󰅙", text: "Hold-to-confirm laser progress bar for safe deletions" },
                            { icon: "󰊢", text: "Git-backed snapshots: automatic undo, rollback, & sync" },
                            { icon: "󰉋", text: "Context-aware: auto-detects active workspace (Zed, VS Code, Nvim)" },
                            { icon: "󰆍", text: "31 shell commands over omarchy-shell tablerase.ardoise" }
                        ]
                        Row {
                            required property var modelData
                            spacing: Style.space(12)
                            Text {
                                text: modelData.icon
                                color: Color.accent || "#1e66f5"
                                font.family: Style.font.family
                                font.pixelSize: Style.space(18)
                                anchors.verticalCenter: parent.verticalCenter
                            }
                            Text {
                                text: modelData.text
                                color: artwork.featureText
                                font.family: Style.font.family
                                font.pixelSize: Style.space(17)
                                anchors.verticalCenter: parent.verticalCenter
                            }
                        }
                    }
                }

                Item { width: 1; height: Style.space(14) }

                Rectangle {
                    width: Style.space(560); height: 1
                    color: artwork.separatorColor
                }

                Text {
                    text: "Ardoise for Omarchy. Native to Quickshell."
                    color: artwork.brandMutedText
                    font.family: Style.font.family
                    font.pixelSize: Style.space(15)
                }
            }

            // Right Side: Bar Widget & Open Panel Scene
            Item {
                id: panelScene
                x: 940
                y: 38
                width: Style.space(420)
                height: 820
                scale: 1.18
                transformOrigin: Item.TopLeft

                // Simulated Bar Widget Readout
                Rectangle {
                    anchors.right: panelCard.right
                    anchors.rightMargin: Style.space(8)
                    y: 0
                    width: barReadout.implicitWidth + Style.space(22)
                    height: Style.space(28)
                    radius: Style.space(6)
                    color: artwork.isLight ? Color.popups.background : (Color.bar.background || "#1e293b")
                    border.color: Color.popups.border
                    border.width: 1

                    Row {
                        id: barReadout
                        anchors.centerIn: parent
                        spacing: Style.space(6)

                        PluginUi.ArdoiseIcon {
                            id: barIcon
                            iconSize: Style.bar.iconFont
                            store: previewContent.store
                            forcedKey: "due"
                            anchors.verticalCenter: parent.verticalCenter
                        }

                        Text {
                            text: "1"
                            color: barIcon.ladderColor
                            font.family: Style.font.family
                            font.pixelSize: Style.font.body
                            font.bold: true
                            anchors.verticalCenter: parent.verticalCenter
                        }
                    }

                    Rectangle {
                        anchors.bottom: parent.bottom
                        anchors.left: parent.left
                        anchors.leftMargin: Style.space(4)
                        anchors.right: parent.right
                        anchors.rightMargin: Style.space(4)
                        height: 2
                        radius: 1
                        color: Color.accent || "#1e66f5"
                    }
                }

                // Panel Popup Card
                Rectangle {
                    id: panelCard
                    y: Style.space(34)
                    width: Style.space(420)
                    implicitHeight: previewContent.implicitHeight + Style.space(24)
                    radius: Style.cornerRadius
                    color: Color.popups.background
                    border.color: Color.popups.border
                    border.width: 2

                    Plugin.PanelContent {
                        id: previewContent
                        anchors.fill: parent
                        anchors.margins: Style.space(12)
                        shortcutState: "active"
                        shortcutRegistered: true
                        panelShortcutRegistered: true
                        quickAddShortcutRegistered: true
                        detectedPanelShortcut: "SUPER + ALT + T"
                        detectedQuickAddShortcut: "SUPER + SHIFT + T"
                        expandedTaskId: 1
                        store: root.sampleStore
                    }
                }

                Text {
                    anchors.horizontalCenter: panelCard.horizontalCenter
                    y: panelCard.y + panelCard.height + Style.space(16)
                    text: "Your task slate, without leaving your desktop."
                    color: artwork.brandMutedText
                    font.family: Style.font.family
                    font.pixelSize: Style.space(13)
                }
            }
        }
    }

    // Window 2: Quick Add Modal (screenshots/quick-add.png)
    FloatingWindow {
        id: winQuickAdd
        visible: true
        implicitWidth: 700
        implicitHeight: 600
        color: Color.background

        Rectangle {
            id: quickAddCard
            anchors.centerIn: parent
            width: Style.space(560)
            height: qaCol.implicitHeight + Style.space(32)
            color: Color.menu.background
            border.color: Color.menu.border
            border.width: 1
            radius: Style.cornerRadius

            Column {
                id: qaCol
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.margins: Style.space(16)
                spacing: Style.space(12)

                Row {
                    width: parent.width
                    spacing: Style.space(8)

                    PluginUi.ArdoiseIcon {
                        anchors.verticalCenter: parent.verticalCenter
                        store: root.sampleStore
                        iconSize: Style.font.subtitle
                        foregroundOverride: Color.menu.text || Color.foreground
                    }

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "Quick Add Task"
                        color: Color.menu.text || Color.foreground
                        font.family: Style.font.family
                        font.pixelSize: Style.font.subtitle
                        font.bold: true
                    }
                }

                PanelSeparator { width: parent.width }

                TextField {
                    id: qaInput
                    width: parent.width
                    text: "Fix memory leak in parser AST traversal"
                    font.family: Style.font.family
                    font.pixelSize: Style.font.body
                    color: Color.menu.text || Color.foreground
                    leftPadding: Style.space(10)
                    rightPadding: Style.space(10)
                    topPadding: Style.space(8)
                    bottomPadding: Style.space(8)
                    background: BorderSurface {
                        color: Util.alpha(Color.accent, 0.08)
                        borderSpec: Border.flat(Color.accent, 2)
                        radius: Style.cornerRadius
                    }
                }

                Row {
                    width: parent.width
                    spacing: Style.space(8)

                    Button {
                        text: "Notes"
                        iconText: "󰏫"
                        fontSize: Style.font.caption
                        fontFamily: Style.font.family
                        bordered: true
                        color: Util.alpha(Color.accent, 0.12)
                        borderSpec: Border.flat(Color.accent, 1)
                    }

                    Button {
                        text: "In 1 hour (16:30)"
                        iconText: "󰥔"
                        fontSize: Style.font.caption
                        fontFamily: Style.font.family
                        bordered: true
                        color: Util.alpha(Color.accent, 0.12)
                        borderSpec: Border.flat(Color.accent, 1)
                    }
                }

                TextArea {
                    width: parent.width
                    height: Style.space(56)
                    text: "Profile heap allocations during tree node cleanup"
                    font.family: Style.font.family
                    font.pixelSize: Style.font.caption
                    color: Color.menu.text || Color.foreground
                    background: BorderSurface {
                        color: Util.alpha(Color.foreground, 0.03)
                        borderSpec: Border.flat(Color.menu.border || Util.alpha(Color.foreground, 0.15), 1)
                        radius: Style.cornerRadius
                    }
                }

                PluginUi.ReminderPills {
                    width: parent.width
                    presets: TodoStore.getReminderPresets()
                    selectedValue: presets.length > 1 ? presets[1].value : ""
                    hasReminder: true
                    fadeColor: Color.menu.background
                }

                Row {
                    width: parent.width
                    spacing: Style.space(6)

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "Profile:"
                        color: Color.muted
                        font.family: Style.font.family
                        font.pixelSize: Style.font.caption
                    }

                    PluginUi.ProfileSelector {
                        width: parent.width - Style.space(60)
                        profiles: ["personal", "work"]
                        selectedProfile: "work"
                        wrap: false
                        fadeColor: Color.menu.background
                    }
                }

                Row {
                    width: parent.width
                    spacing: Style.space(6)

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "Tags:"
                        color: Color.muted
                        font.family: Style.font.family
                        font.pixelSize: Style.font.caption
                    }

                    PluginUi.Chip {
                        text: "#parser"
                        variant: "tag"
                        removable: true
                        chipColor: Color.muted
                        textColor: Color.muted
                        fontFamily: Style.font.family
                    }

                    PluginUi.Chip {
                        text: "#ui"
                        variant: "tag"
                        removable: true
                        chipColor: Color.muted
                        textColor: Color.muted
                        fontFamily: Style.font.family
                    }
                }

                Row {
                    spacing: Style.space(6)

                    PluginUi.Chip {
                        variant: "location"
                        iconText: "󰊤"
                        text: "tablerase/omarchy-ardoise"
                        removable: true
                        maximumWidth: Style.space(260)
                        fontFamily: Style.font.family
                    }
                }

                PanelSeparator { width: parent.width }

                Item {
                    width: parent.width
                    implicitHeight: Math.max(hintText.implicitHeight, actionButtons.implicitHeight)

                    Text {
                        id: hintText
                        anchors.left: parent.left
                        anchors.right: actionButtons.left
                        anchors.rightMargin: Style.space(12)
                        anchors.verticalCenter: parent.verticalCenter
                        text: "󰌑 Enter  •  Tab/Vim Nav  •  Esc Cancel"
                        color: Color.muted
                        font.family: Style.font.family
                        font.pixelSize: Style.font.caption
                    }

                    Row {
                        id: actionButtons
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: Style.space(8)

                        Button {
                            iconText: "󰅖"
                            text: "Cancel"
                            fontSize: Style.font.caption
                            fontFamily: Style.font.family
                            bordered: true
                        }

                        Button {
                            iconText: "󰐕"
                            text: "Add"
                            fontSize: Style.font.caption
                            fontFamily: Style.font.family
                            bordered: true
                            selected: true
                        }
                    }
                }
            }
        }
    }

    // Window 3: Custom Reminder Picker (screenshots/reminder-picker.png)
    FloatingWindow {
        id: winPicker
        visible: true
        implicitWidth: 500
        implicitHeight: 600
        color: Color.background

        Item {
            id: pickerContainer
            width: 400
            height: 520
            anchors.centerIn: parent

            PluginUi.ReminderPicker {
                id: reminderPicker
                isOpen: true
                manualText: "tomorrow 9am"
                calYear: 2026
                calMonth: 9
            }
        }
    }

    // Window 4: Git Snapshots Modal (screenshots/git-snapshots.png)
    FloatingWindow {
        id: winGit
        visible: true
        implicitWidth: 500
        implicitHeight: 720
        color: Color.background

        Rectangle {
            id: gitCard
            anchors.centerIn: parent
            width: 440
            height: 640
            color: Color.popups.background
            border.color: Color.popups.border
            border.width: 2
            radius: Style.cornerRadius

            PluginUi.GitModal {
                id: gitModal
                isOpen: true
                barWidget: ({
                    deviceName: "omarchy-workstation",
                    gitSnapshots: [
                        {
                            hash: "f4a8b19e2d3c4b5a67890123456789abcdef0123",
                            shortHash: "f4a8b19",
                            message: "Fix parser AST memory leak [omarchy-workstation]",
                            cleanMessage: "Fix parser AST memory leak",
                            deviceName: "workstation",
                            timestamp: Date.now() - 15 * 60 * 1000,
                            pendingCount: 3
                        },
                        {
                            hash: "e3d7a08b1c2d3e4f5a6b7c8d9e0f1a2b3c4d5e6f",
                            shortHash: "e3d7a08",
                            message: "Add natural language reminder parsing",
                            cleanMessage: "Add natural language reminder parsing",
                            deviceName: "laptop",
                            timestamp: Date.now() - 2 * 3600 * 1000,
                            pendingCount: 4
                        },
                        {
                            hash: "c2b1a9f8e7d6c5b4a3f2e1d0c9b8a7f6e5d4c3b2",
                            shortHash: "c2b1a9f",
                            message: "Initial Ardoise task suite configuration",
                            cleanMessage: "Initial Ardoise task suite configuration",
                            deviceName: "workstation",
                            timestamp: Date.now() - 24 * 3600 * 1000,
                            pendingCount: 2
                        }
                    ],
                    inspectedSnapshotDiff: {
                        summary: { added: 1, deleted: 1, modified: 1, completed: 0 },
                        tasks: [
                            { id: 1, title: "Fix memory leak in parser AST traversal", profile: "work", diffStatus: "added" },
                            { id: 2, title: "Review PR #42 git snapshot search filter", profile: "work", diffStatus: "modified" },
                            { id: 3, title: "Legacy prototype parser cleanup", profile: "work", diffStatus: "removed", isMissingFromStore: true }
                        ]
                    },
                    inspectedSnapshotTasks: [
                        { id: 1, title: "Fix memory leak in parser AST traversal", profile: "work", diffStatus: "added" },
                        { id: 2, title: "Review PR #42 git snapshot search filter", profile: "work", diffStatus: "modified" },
                        { id: 3, title: "Legacy prototype parser cleanup", profile: "work", diffStatus: "removed", isMissingFromStore: true }
                    ]
                })
                selectedIndex: 0
                snapshotSection: "preview"
                previewIndex: 0
            }
        }
    }

    // Window 5: Archive Modal (screenshots/archive.png)
    FloatingWindow {
        id: winArchive
        visible: true
        implicitWidth: 500
        implicitHeight: 720
        color: Color.background

        Rectangle {
            id: archiveCard
            anchors.centerIn: parent
            width: 420
            height: 600
            color: Color.popups.background
            border.color: Color.popups.border
            border.width: 2
            radius: Style.cornerRadius

            PluginUi.ArchiveModal {
                id: archiveModal
                isOpen: true
                barWidget: ({
                    getArchiveText: function() {
                        return JSON.stringify({
                            version: 1,
                            archived: [
                                {
                                    id: 101,
                                    title: "Implement tree-sitter AST traversal parser",
                                    profile: "work",
                                    repo: "tablerase/omarchy-ardoise",
                                    tags: ["parser", "tree-sitter"],
                                    completedAt: Date.now() - 3600000 * 24,
                                    description: "Evaluated C-based binding performance against quickshell"
                                },
                                {
                                    id: 102,
                                    title: "Configure unit test harness in Node & Bun",
                                    profile: "work",
                                    tags: ["tests", "ci"],
                                    completedAt: Date.now() - 3600000 * 48,
                                    description: "Added coverage for TodoStore.js and PanelLogic.js"
                                },
                                {
                                    id: 103,
                                    title: "Renew annual domain certificate",
                                    profile: "personal",
                                    tags: ["admin"],
                                    completedAt: Date.now() - 3600000 * 72,
                                    description: ""
                                },
                                {
                                    id: 104,
                                    title: "Clean up legacy IPC command handlers",
                                    profile: "work",
                                    tags: ["ipc", "refactor"],
                                    completedAt: Date.now() - 3600000 * 96,
                                    description: "Standardized all return contracts across shell commands"
                                }
                            ]
                        })
                    }
                })
                selectedIndex: 0
            }
        }
    }

    // Window 6: Help & Shortcuts Modal (screenshots/help-shortcuts.png)
    FloatingWindow {
        id: winHelp
        visible: true
        implicitWidth: 500
        implicitHeight: 720
        color: Color.background

        Rectangle {
            id: helpCard
            anchors.centerIn: parent
            width: 420
            height: 620
            color: Color.popups.background
            border.color: Color.popups.border
            border.width: 2
            radius: Style.cornerRadius

            PluginUi.HelpModal {
                id: helpModal
                isOpen: true
                hasNewRelease: true
                releaseNotesCollapsed: false
                detectedPanelShortcut: "SUPER + ALT + T"
                detectedQuickAddShortcut: "SUPER + SHIFT + T"
                activeBindings: Logic.resolveBindings({})
            }
        }
    }

    // Window 7: Context Action Menu (screenshots/context-menu.png)
    FloatingWindow {
        id: winMenu
        visible: true
        implicitWidth: 600
        implicitHeight: 760
        color: Color.background

        Rectangle {
            id: menuCard
            anchors.centerIn: parent
            width: 420
            height: 650
            color: Color.popups.background
            border.color: Color.popups.border
            border.width: 2
            radius: Style.cornerRadius

            Plugin.PanelContent {
                id: menuContent
                anchors.fill: parent
                anchors.margins: Style.space(12)
                shortcutState: "active"
                shortcutRegistered: true
                panelShortcutRegistered: true
                quickAddShortcutRegistered: true
                detectedPanelShortcut: "SUPER + ALT + T"
                detectedQuickAddShortcut: "SUPER + SHIFT + T"
                expandedTaskId: 1
                store: root.sampleStore
                showTaskMenu: true
                taskMenuIndex: 0
                taskMenuAnchorX: 300
                taskMenuAnchorY: 155
                taskMenuTitle: "Fix memory leak in parser AST traversal"
                taskMenuMeta: "#work • tablerase/omarchy-ardoise"
                taskMenuItems: Logic.getTaskMenuItems(root.sampleStore.todos[0])
            }
        }
    }

    Timer {
        interval: 1000
        running: true
        onTriggered: {
            var outDir = Quickshell.env("ARDOISE_PREVIEW_OUT") || ".";
            var remaining = 8;
            function checkDone() {
                remaining--;
                if (remaining <= 0) {
                    Qt.quit();
                }
            }

            artwork.grabToImage(function(result) {
                result.saveToFile(outDir + "/preview.png");
                checkDone();
            });

            panelCard.grabToImage(function(result) {
                result.saveToFile(outDir + "/screenshots/panel.png");
                checkDone();
            });

            quickAddCard.grabToImage(function(result) {
                result.saveToFile(outDir + "/screenshots/quick-add.png");
                checkDone();
            });

            var pickerCard = reminderPicker.children[1];
            pickerCard.grabToImage(function(result) {
                result.saveToFile(outDir + "/screenshots/reminder-picker.png");
                checkDone();
            });

            gitCard.grabToImage(function(result) {
                result.saveToFile(outDir + "/screenshots/git-snapshots.png");
                checkDone();
            });

            archiveCard.grabToImage(function(result) {
                result.saveToFile(outDir + "/screenshots/archive.png");
                checkDone();
            });

            helpCard.grabToImage(function(result) {
                result.saveToFile(outDir + "/screenshots/help-shortcuts.png");
                checkDone();
            });

            menuCard.grabToImage(function(result) {
                result.saveToFile(outDir + "/screenshots/context-menu.png");
                checkDone();
            });
        }
    }
}
