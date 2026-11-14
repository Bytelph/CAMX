import QtQuick
import QtQuick.Controls
import CXCAM.Theme 1.0

// 顶部菜单栏图标按钮（保存/撤销/重做等）：悬停高亮 + 提示文字 + 点击信号。
// M0 阶段仅提供 UI 与信号，具体动作待 App 模块（文档/撤销重做）接入后再连接。
Rectangle {
    id: btn

    property string icon: ""
    property string tooltip: ""
    signal clicked()

    width: 34
    height: 34
    radius: 4
    color: mouse.containsMouse ? Theme.bgElevated : "transparent"
    Behavior on color { ColorAnimation { duration: 120 } }

    ToolIcon {
        anchors.centerIn: parent
        name: btn.icon
        size: 18
        color: mouse.containsMouse ? Theme.textBright : Theme.textDim
    }

    ToolTip.visible: mouse.containsMouse && btn.tooltip !== ""
    ToolTip.text: btn.tooltip
    ToolTip.delay: 400

    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: btn.clicked()
    }
}
