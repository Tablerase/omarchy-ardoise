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
                            "Reactive local storage (~/.config/omarchy/todos.json)",
                            "Auto-hiding profile filters with smooth scrollbar",
                            "24/7 background reminder notifications",
                            "Dedicated completion archive (todos-archive.json)",
                            "Fast global Quick Add overlay (SUPER + SHIFT + T)",
                            "Native to Omarchy Quattro, down to the details"
                        ]
                        Row {
                            required property string modelData
                            spacing: Style.space(12)
                            Text {
                                text: "•"
                                color: Color.accent || "#1e66f5"
                                font.pixelSize: Style.space(22)
                            }
                            Text {
                                text: modelData
                                color: "#cbd5e1"
                                font.family: Style.font.family
                                font.pixelSize: Style.space(17)
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

                        PluginUi.InboxIcon {
                            width: Style.space(16); height: Style.space(16)
                            color: Color.urgent || "#d20f39"
                            anchors.verticalCenter: parent.verticalCenter
                        }

                        Text {
                            text: "6"
                            color: Color.urgent || "#d20f39"
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
                        store: ({
                            version: 1,
                            activeProfile: "personal",
                            profiles: ["personal", "work"],
                            todos: [
                                {
                                    id: 1,
                                    title: "Finalize quarterly planning architecture",
                                    description: "Review roadmap deliverables and milestones",
                                    done: false,
                                    profile: "work",
                                    reminder: "Today 18:00",
                                    notified: false,
                                    createdAt: 1726930000000
                                },
                                {
                                    id: 2,
                                    title: "Review pull request for Ardoise plugin",
                                    description: "Validate CI workflows and headless test suite",
                                    done: false,
                                    profile: "work",
                                    reminder: "Tomorrow 09:00",
                                    notified: false,
                                    createdAt: 1726931000000
                                },
                                {
                                    id: 3,
                                    title: "Pick up fresh sourdough bread",
                                    description: "",
                                    done: false,
                                    profile: "personal",
                                    reminder: null,
                                    notified: false,
                                    createdAt: 1726932000000
                                },
                                {
                                    id: 4,
                                    title: "Book dinner table for Friday evening",
                                    description: "",
                                    done: false,
                                    profile: "personal",
                                    reminder: "Friday 20:00",
                                    notified: false,
                                    createdAt: 1726933000000
                                },
                                {
                                    id: 5,
                                    title: "Refactor storage parser unit tests",
                                    description: "",
                                    done: false,
                                    profile: "work",
                                    reminder: null,
                                    notified: false,
                                    createdAt: 1726934000000
                                },
                                {
                                    id: 6,
                                    title: "Read chapter 4 of Designing Data-Intensive Apps",
                                    description: "",
                                    done: false,
                                    profile: "personal",
                                    reminder: null,
                                    notified: false,
                                    createdAt: 1726935000000
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
