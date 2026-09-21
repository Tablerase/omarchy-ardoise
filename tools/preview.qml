// =============================================================================
// preview.qml
//
// Headless offscreen render for Ardoise marketplace preview and screenshots.
// Uses Quickshell offscreen mode to capture pixel-perfect QML artwork.
// Inspired by Carmine Paolino's OmaTasks render pipeline.
// =============================================================================

import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.Commons
import qs.Ui
import "plugin" as Plugin

ShellRoot {
    FloatingWindow {
        id: win
        visible: true
        implicitWidth: 1600
        implicitHeight: 900
        color: "#0b0f19"

        Item {
            id: artwork
            anchors.fill: parent

            // Deep slate background with radial lighting
            Canvas {
                anchors.fill: parent
                onPaint: {
                    var ctx = getContext("2d");
                    var g = ctx.createRadialGradient(1100, 450, 50, 1100, 450, 900);
                    g.addColorStop(0, "#172554");
                    g.addColorStop(0.5, "#0f172a");
                    g.addColorStop(1, "#090d16");
                    ctx.fillStyle = g;
                    ctx.fillRect(0, 0, width, height);
                }
            }

            // Left Side: Branding & Features
            Column {
                x: 100
                y: 90
                spacing: 24
                width: 620

                Row {
                    spacing: 12
                    Rectangle {
                        width: 10; height: 10; radius: 5
                        color: "#38bdf8"
                        anchors.verticalCenter: parent.verticalCenter
                    }
                    Text {
                        text: "ARDOISE / TABLERASE"
                        color: "#38bdf8"
                        font.pixelSize: 16
                        font.bold: true
                        font.letterSpacing: 3
                    }
                }

                Text {
                    text: "Your task slate,\nright in the bar."
                    color: "#f8fafc"
                    font.pixelSize: 64
                    font.bold: true
                    lineHeight: 1.08
                }

                Text {
                    text: "Instant capture, profile tags, and background reminders.\nWipe the slate clean when you are done."
                    color: "#94a3b8"
                    font.pixelSize: 20
                    lineHeight: 1.4
                }

                Item { width: 1; height: 10 }

                Column {
                    spacing: 16
                    Repeater {
                        model: [
                            "Reactive local storage (~/.config/omarchy/todos.json)",
                            "Auto-hiding tag filters with smooth scrollbar",
                            "24/7 headless background reminder notifications",
                            "Dedicated completion archive (todos-archive.json)",
                            "Fast global Quick Add modal (SUPER + SHIFT + T)"
                        ]
                        Row {
                            spacing: 12
                            Text {
                                text: "•"
                                color: "#38bdf8"
                                font.pixelSize: 22
                            }
                            Text {
                                text: modelData
                                color: "#cbd5e1"
                                font.pixelSize: 17
                            }
                        }
                    }
                }

                Item { width: 1; height: 16 }

                Rectangle {
                    width: 540; height: 1
                    color: "#1e293b"
                }

                Text {
                    text: "Ardoise — Minimalist task slate. Native to Omarchy Quattro."
                    color: "#64748b"
                    font.pixelSize: 15
                }
            }

            // Right Side: Bar Widget & Open Panel Scene
            Item {
                x: 820
                y: 50
                width: 680
                height: 800

                // Simulated Bar Widget
                Rectangle {
                    anchors.right: panelCard.right
                    y: 10
                    width: barContent.implicitWidth + 24
                    height: 36
                    radius: 18
                    color: "#1e293b"
                    border.color: "#334155"
                    border.width: 1

                    Row {
                        id: barContent
                        anchors.centerIn: parent
                        spacing: 8
                        Plugin.InboxIcon {
                            width: 16; height: 16
                            color: "#f8fafc"
                        }
                        Text {
                            text: "3"
                            color: "#f8fafc"
                            font.bold: true
                            font.pixelSize: 14
                        }
                    }
                }

                // Panel Card
                Rectangle {
                    id: panelCard
                    x: 100
                    y: 60
                    width: 480
                    height: 700
                    radius: 16
                    color: "#0f172a"
                    border.color: "#334155"
                    border.width: 1

                    Column {
                        anchors.fill: parent
                        anchors.margins: 22
                        spacing: 18

                        // Panel Header
                        Row {
                            width: parent.width
                            spacing: 10
                            Plugin.InboxIcon {
                                width: 22; height: 22
                                color: "#38bdf8"
                                anchors.verticalCenter: parent.verticalCenter
                            }
                            Text {
                                text: "Ardoise"
                                color: "#f8fafc"
                                font.bold: true
                                font.pixelSize: 18
                                anchors.verticalCenter: parent.verticalCenter
                            }
                            Item { width: 140; height: 1 }
                            Rectangle {
                                width: 140; height: 26; radius: 13
                                color: "#1e293b"
                                Text {
                                    anchors.centerIn: parent
                                    text: "SUPER + SHIFT + T"
                                    color: "#94a3b8"
                                    font.pixelSize: 11
                                    font.bold: true
                                }
                            }
                        }

                        // Input Box Mockup
                        Rectangle {
                            width: parent.width
                            height: 44
                            radius: 10
                            color: "#1e293b"
                            border.color: "#334155"
                            border.width: 1
                            Row {
                                anchors.fill: parent
                                anchors.leftMargin: 14
                                spacing: 10
                                Text {
                                    text: "Add a task... (#work, #perso, +1h)"
                                    color: "#64748b"
                                    font.pixelSize: 14
                                    anchors.verticalCenter: parent.verticalCenter
                                }
                            }
                        }

                        // Filter Pills Bar
                        Row {
                            spacing: 8
                            Rectangle {
                                width: 68; height: 30; radius: 15
                                color: "#1e293b"
                                border.color: "#334155"
                                Text { anchors.centerIn: parent; text: "󰀉 All 3"; color: "#94a3b8"; font.pixelSize: 12 }
                            }
                            Rectangle {
                                width: 88; height: 30; radius: 15
                                color: "#38bdf8"
                                Text { anchors.centerIn: parent; text: "󰈚 Work 2"; color: "#0f172a"; font.bold: true; font.pixelSize: 12 }
                            }
                            Rectangle {
                                width: 100; height: 30; radius: 15
                                color: "#1e293b"
                                border.color: "#334155"
                                Text { anchors.centerIn: parent; text: "󰀉 Personal 1"; color: "#94a3b8"; font.pixelSize: 12 }
                            }
                        }

                        // Task List Cards
                        Column {
                            width: parent.width
                            spacing: 10

                            // Task 1
                            Rectangle {
                                width: parent.width; height: 72; radius: 10
                                color: "#1e293b"
                                border.color: "#334155"
                                Column {
                                    anchors.fill: parent
                                    anchors.margins: 12
                                    spacing: 6
                                    Row {
                                        spacing: 10
                                        Rectangle {
                                            width: 16; height: 16; radius: 4
                                            color: "transparent"; border.color: "#64748b"; border.width: 2
                                            anchors.verticalCenter: parent.verticalCenter
                                        }
                                        Text {
                                            text: "Finalize Q4 roadmap architecture"
                                            color: "#f8fafc"
                                            font.pixelSize: 14
                                            font.bold: true
                                        }
                                    }
                                    Row {
                                        anchors.left: parent.left; anchors.leftMargin: 26
                                        spacing: 8
                                        Rectangle {
                                            width: 52; height: 18; radius: 4
                                            color: "#334155"
                                            Text { anchors.centerIn: parent; text: "work"; color: "#94a3b8"; font.pixelSize: 10; font.bold: true }
                                        }
                                        Text {
                                            text: "󰀉 Today 18:00"
                                            color: "#38bdf8"
                                            font.pixelSize: 11
                                        }
                                    }
                                }
                            }

                            // Task 2
                            Rectangle {
                                width: parent.width; height: 72; radius: 10
                                color: "#1e293b"
                                border.color: "#334155"
                                Column {
                                    anchors.fill: parent
                                    anchors.margins: 12
                                    spacing: 6
                                    Row {
                                        spacing: 10
                                        Rectangle {
                                            width: 16; height: 16; radius: 4
                                            color: "transparent"; border.color: "#64748b"; border.width: 2
                                            anchors.verticalCenter: parent.verticalCenter
                                        }
                                        Text {
                                            text: "Review pull request for Ardoise plugin"
                                            color: "#f8fafc"
                                            font.pixelSize: 14
                                            font.bold: true
                                        }
                                    }
                                    Row {
                                        anchors.left: parent.left; anchors.leftMargin: 26
                                        spacing: 8
                                        Rectangle {
                                            width: 52; height: 18; radius: 4
                                            color: "#334155"
                                            Text { anchors.centerIn: parent; text: "work"; color: "#94a3b8"; font.pixelSize: 10; font.bold: true }
                                        }
                                        Text {
                                            text: "󰀉 Tomorrow 09:00"
                                            color: "#94a3b8"
                                            font.pixelSize: 11
                                        }
                                    }
                                }
                            }

                            // Task 3
                            Rectangle {
                                width: parent.width; height: 58; radius: 10
                                color: "#1e293b"
                                border.color: "#334155"
                                Row {
                                    anchors.fill: parent
                                    anchors.margins: 12
                                    spacing: 10
                                    Rectangle {
                                        width: 16; height: 16; radius: 4
                                        color: "transparent"; border.color: "#64748b"; border.width: 2
                                        anchors.verticalCenter: parent.verticalCenter
                                    }
                                    Text {
                                        text: "Buy sourdough bread"
                                        color: "#f8fafc"
                                        font.pixelSize: 14
                                        anchors.verticalCenter: parent.verticalCenter
                                    }
                                    Item { width: 140; height: 1 }
                                    Rectangle {
                                        width: 66; height: 18; radius: 4
                                        color: "#334155"
                                        Text { anchors.centerIn: parent; text: "personal"; color: "#94a3b8"; font.pixelSize: 10; font.bold: true }
                                        anchors.verticalCenter: parent.verticalCenter
                                    }
                                }
                            }
                        }

                        Item { width: 1; height: 18 }

                        // Footer
                        Rectangle {
                            width: parent.width; height: 1
                            color: "#1e293b"
                        }
                        Row {
                            width: parent.width
                            Rectangle {
                                width: 120; height: 32; radius: 6
                                color: "#1e293b"
                                border.color: "#334155"
                                Text { anchors.centerIn: parent; text: "󰋚 Archive (14)"; color: "#94a3b8"; font.pixelSize: 12 }
                            }
                            Item { width: 236; height: 1 }
                            Rectangle {
                                width: 80; height: 32; radius: 6
                                color: "#1e293b"
                                border.color: "#334155"
                                Text { anchors.centerIn: parent; text: "󰒲 Clear"; color: "#64748b"; font.pixelSize: 12 }
                            }
                        }
                    }
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
