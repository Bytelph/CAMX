import QtQuick
import QtQuick.Controls
import CAMX.Theme 1.0

// ribbon 工具按钮：仅图标（悬停高亮 + 气泡提示文字）
Rectangle {
    id: btn
    property string text: ""
    property string icon: ""
    signal clicked()

    width: 40
    height: 40
    radius: 4
    color: mouse.containsMouse ? Theme.bgElevated : "transparent"
    Behavior on color { ColorAnimation { duration: 120 } }

    ToolIcon {
        anchors.centerIn: parent
        name: btn.icon
        size: 22
        color: mouse.containsMouse ? Theme.textBright : Theme.textDim
    }

    ToolTip.visible: mouse.containsMouse && btn.text !== ""
    ToolTip.text: btn.text
    ToolTip.delay: 400

    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: btn.clicked()
    }
}
