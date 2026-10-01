// =============================================================================
// preview.qml
//
// Headless offscreen render for Ardoise marketplace preview and screenshots.
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

ShellRoot {
    FloatingWindow {
        id: win
        visible: true
        implicitWidth: 1600
        implicitHeight: 900
        color: "#090d16"

        Item {
            id: artwork
            anchors.fill: parent

            // Deep slate canvas with subtle radial illumination
            Canvas {
                anchors.fill: parent
                onPaint: {
                    var ctx = getContext("2d");
                    var g = ctx.createRadialGradient(1140, 450, 40, 1140, 450, 960);
                    g.addColorStop(0, "#172554");
                    g.addColorStop(0.5, "#0b1220");
                    g.addColorStop(1, "#070a12");
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
                    color: "#f8fafc"
                    font.family: "Inter"
                    font.pixelSize: Style.space(68)
                    font.bold: true
                    lineHeight: 1.08
                }

                Text {
                    text: "Instant capture, profile tags, and background reminders.\nWipe the slate clean when you are done."
                    color: "#94a3b8"
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
                            { icon: "󰍉", text: "In-panel search (/ or Ctrl+F) across tasks, notes, & profiles" },
                            { icon: "󰊢", text: "Git-backed snapshots: automatic undo, rollback, & sync" },
                            { icon: "󰉋", text: "Context-aware: auto-detects active workspace (Zed, VS Code, Nvim)" },
                            { icon: "󱫌", text: "Urgency ladder: smart severity escalations without red alert fatigue" },
                            { icon: "󰆍", text: "23 shell commands over omarchy-shell tablerase.ardoise" }
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
                                color: "#cbd5e1"
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
                    color: "#1e293b"
                }

                Text {
                    text: "Ardoise for Omarchy. Native to Quickshell."
                    color: "#64748b"
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

                // Simulated Omarchy Bar Widget Snippet with active underline
                Item {
                    anchors.right: panelCard.right
                    anchors.rightMargin: Style.space(8)
                    y: 0
                    width: barReadout.implicitWidth + Style.space(16)
                    height: Style.space(28)

                    Row {
                        id: barReadout
                        anchors.centerIn: parent
                        spacing: Style.space(6)

                        PluginUi.ArdoiseIcon {
                            id: barIcon
                            iconSize: Style.bar.iconFont
                            store: previewContent.store
                            forcedKey: "overdue"
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

                    // Bar active popout indicator underline
                    Rectangle {
                        anchors.bottom: parent.bottom
                        anchors.left: parent.left
                        anchors.right: parent.right
                        height: 2
                        radius: 1
                        color: Color.accent || "#1e66f5"
                    }
                }

                // Authentic Panel Popup Card
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
                        store: ({
                            version: 1,
                            activeProfile: "personal",
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
                                    reminder: new Date(Date.now() - 3600000).toISOString(),
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
                    }
                }

                Text {
                    anchors.horizontalCenter: panelCard.horizontalCenter
                    y: panelCard.y + panelCard.height + Style.space(16)
                    text: "Your task slate, without leaving your desktop."
                    color: "#64748b"
                    font.family: Style.font.family
                    font.pixelSize: Style.space(13)
                }
            }
        }
    }

    Timer {
        interval: 600
        running: true
        onTriggered: {
            var outDir = Quickshell.env("ARDOISE_PREVIEW_OUT") || ".";
            artwork.grabToImage(function(result) {
                result.saveToFile(outDir + "/preview.png");
            });
            panelCard.grabToImage(function(result) {
                result.saveToFile(outDir + "/screenshots/panel.png");
                Qt.quit();
            });
        }
    }
}
