import QtQuick
import QtQuick.Controls
import CAMX.Theme 1.0

// 显示模式切换：图标按钮组（形状 4 项 + 网格 4 项），当前项琥珀色高亮。
// 由父级绑定 viewport（Viewport）、displayMode（当前生效模式 0..7）以及
// shapeModes / meshModes（Ribbon 上的模式列表，每项含 { text, mode, icon }），
// 点击后调用 viewport.setDisplayMode(mode) 转发给 GraphicsViewport。取代原来的下拉框。
Item {
    id: root

    property var viewport: null
    // 当前显示模式（0..7，对应 Mayo::DisplayMode），由视口回写后同步高亮
    property int displayMode: 0
    property var shapeModes: []   // [{ text, mode, icon }] 形状 0..3
    property var meshModes: []    // [{ text, mode, icon }] 网格 4..7

    width: col.implicitWidth
    height: col.implicitHeight

    Column {
        id: col
        spacing: 2

        // —— 形状行 ——
        Row {
            spacing: 4
            Text {
                text: "形状"
                width: 22
                anchors.verticalCenter: parent.verticalCenter
                color: Theme.textMuted
                font.pixelSize: 10
                font.family: Theme.fontFamily
            }
            Repeater {
                model: root.shapeModes
                delegate: Rectangle {
                    width: 34
                    height: 34
                    radius: 4
                    readonly property bool selected: root.displayMode === modelData.mode
                    color: selected ? "#fdf3e3" : (btnMouse.containsMouse ? Theme.bgElevated : "transparent")
                    border.color: selected ? "#d97706" : "transparent"
                    border.width: selected ? 1 : 0
                    Behavior on color { ColorAnimation { duration: 120 } }

                    ToolIcon {
                        anchors.centerIn: parent
                        name: modelData.icon
                        size: 20
                        color: selected ? "#d97706" : (btnMouse.containsMouse ? Theme.textBright : Theme.textDim)
                    }

                    ToolTip.visible: btnMouse.containsMouse
                    ToolTip.text: "形状 · " + modelData.text
                    ToolTip.delay: 400

                    MouseArea {
                        id: btnMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            if (root.viewport && root.viewport.setDisplayMode)
                                root.viewport.setDisplayMode(modelData.mode)
                        }
                    }
                }
            }
        }

        // —— 网格行 ——
        Row {
            spacing: 4
            Text {
                text: "网格"
                width: 22
                anchors.verticalCenter: parent.verticalCenter
                color: Theme.textMuted
                font.pixelSize: 10
                font.family: Theme.fontFamily
            }
            Repeater {
                model: root.meshModes
                delegate: Rectangle {
                    width: 34
                    height: 34
                    radius: 4
                    readonly property bool selected: root.displayMode === modelData.mode
                    color: selected ? "#fdf3e3" : (btnMouse.containsMouse ? Theme.bgElevated : "transparent")
                    border.color: selected ? "#d97706" : "transparent"
                    border.width: selected ? 1 : 0
                    Behavior on color { ColorAnimation { duration: 120 } }

                    ToolIcon {
                        anchors.centerIn: parent
                        name: modelData.icon
                        size: 20
                        color: selected ? "#d97706" : (btnMouse.containsMouse ? Theme.textBright : Theme.textDim)
                    }

                    ToolTip.visible: btnMouse.containsMouse
                    ToolTip.text: "网格 · " + modelData.text
                    ToolTip.delay: 400

                    MouseArea {
                        id: btnMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            if (root.viewport && root.viewport.setDisplayMode)
                                root.viewport.setDisplayMode(modelData.mode)
                        }
                    }
                }
            }
        }
    }
}
