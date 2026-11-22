import QtQuick
import QtQuick.Controls
import CAMX.Theme 1.0

// 拾取模式切换：5 个图标按钮（无/体/面/边/点），当前项高亮。
// 由父级绑定 viewport（Viewport）与 pickMode（当前生效模式），点击后调用
// viewport.setPickMode(mode) 转发给 GraphicsViewport。取代原来的下拉框（图标更直观、更紧凑）。
Item {
    id: root

    // 目标视口（Viewport）：用于调用 setPickMode
    property var viewport: null
    // 当前拾取模式（0..4，对应 PickMode 枚举），由视口回写后同步高亮；默认面选择（2）。
    property int pickMode: 2

    width: row.implicitWidth
    height: row.implicitHeight

    Row {
        id: row
        spacing: 2

        Repeater {
            model: [
                { text: "无", mode: 0, icon: "pick_none" },
                { text: "体", mode: 1, icon: "pick_body" },
                { text: "面", mode: 2, icon: "pick_face" },
                { text: "边", mode: 3, icon: "pick_edge" },
                { text: "点", mode: 4, icon: "pick_point" }
            ]

            delegate: Rectangle {
                id: btn
                width: 34
                height: 34
                radius: 4
                readonly property bool selected: root.pickMode === modelData.mode

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
                ToolTip.text: modelData.text
                ToolTip.delay: 400

                MouseArea {
                    id: btnMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        if (root.viewport && root.viewport.setPickMode)
                            root.viewport.setPickMode(modelData.mode)
                    }
                }
            }
        }
    }
}
