import QtQuick
import CAMX.Theme 1.0

// 对话框按钮：普通（灰边）/ 主按钮（蓝边），供刀具库、机床库等模态对话框复用。
Rectangle {
    id: btn
    property string text: ""
    property bool primary: false
    signal clicked()

    implicitWidth: label.implicitWidth + 32
    implicitHeight: 30
    height: implicitHeight
    radius: 4
    color: primary ? (mouse.containsMouse ? "#eaf2fe" : "#ffffff")
                   : (mouse.containsMouse ? "#eef0f3" : "#ffffff")
    border.color: primary ? "#2f6fd0" : "#b9bec6"
    border.width: 1

    Text {
        id: label
        anchors.centerIn: parent
        text: btn.text
        color: btn.primary ? "#2f6fd0" : "#33383f"
        font.pixelSize: 12
        font.family: Theme.fontFamily
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: btn.clicked()
    }
}
