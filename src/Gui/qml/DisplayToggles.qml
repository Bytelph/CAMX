import QtQuick
import QtQuick.Controls
import CAMX.Theme 1.0

// 「显示」开关组：网格 / 坐标系 两个独立开关，勾选态琥珀色高亮。
// 由父级绑定 viewport（Viewport）以及 gridVisible / originVisible，
// 点击后调用 viewport.setGridVisible / setOriginVisible 转发给 GraphicsViewport。
Item {
    id: root

    property var viewport: null
    property bool gridVisible: false
    property bool originVisible: true

    width: row.implicitWidth
    height: row.implicitHeight

    Row {
        id: row
        spacing: 2

        // —— 网格 ——
        Rectangle {
            id: gridBtn
            width: 34
            height: 34
            radius: 4
            readonly property bool checked: root.gridVisible
            color: checked ? "#fdf3e3" : (gridMouse.containsMouse ? Theme.bgElevated : "transparent")
            border.color: checked ? "#d97706" : "transparent"
            border.width: checked ? 1 : 0
            Behavior on color { ColorAnimation { duration: 120 } }

            ToolIcon {
                anchors.centerIn: parent
                name: "grid"
                size: 20
                color: gridBtn.checked ? "#d97706" : (gridMouse.containsMouse ? Theme.textBright : Theme.textDim)
            }

            ToolTip.visible: gridMouse.containsMouse
            ToolTip.text: "网格"
            ToolTip.delay: 400

            MouseArea {
                id: gridMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    if (root.viewport && root.viewport.setGridVisible)
                        root.viewport.setGridVisible(!root.gridVisible)
                }
            }
        }

        // —— 坐标系 ——
        Rectangle {
            id: originBtn
            width: 34
            height: 34
            radius: 4
            readonly property bool checked: root.originVisible
            color: checked ? "#fdf3e3" : (originMouse.containsMouse ? Theme.bgElevated : "transparent")
            border.color: checked ? "#d97706" : "transparent"
            border.width: checked ? 1 : 0
            Behavior on color { ColorAnimation { duration: 120 } }

            ToolIcon {
                anchors.centerIn: parent
                name: "axis"
                size: 20
                color: originBtn.checked ? "#d97706" : (originMouse.containsMouse ? Theme.textBright : Theme.textDim)
            }

            ToolTip.visible: originMouse.containsMouse
            ToolTip.text: "坐标系"
            ToolTip.delay: 400

            MouseArea {
                id: originMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    if (root.viewport && root.viewport.setOriginVisible)
                        root.viewport.setOriginVisible(!root.originVisible)
                }
            }
        }
    }
}
