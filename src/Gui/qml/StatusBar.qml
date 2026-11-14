import QtQuick
import CXCAM.Theme 1.0

// 底部状态栏
Rectangle {
    id: bar
    height: 24
    color: Theme.bgPanelAlt
    border.color: Theme.border

    // 由 Main.qml 传入：鼠标指向的 3D 世界坐标（悬停在模型上时更新，空白处为空串）
    property string cursorCoordinates: ""

    // 左边：鼠标坐标值
    Text {
        text: bar.cursorCoordinates
        color: Theme.textDim
        font.pixelSize: 11
        font.family: Theme.fontFamily
        anchors.left: parent.left
        anchors.leftMargin: 10
        anchors.verticalCenter: parent.verticalCenter
    }

    Text {
        id: unitText
        text: "单位: mm"
        color: Theme.textDim
        font.pixelSize: 11
        font.family: Theme.fontFamily
        anchors.right: parent.right
        anchors.rightMargin: 10
        anchors.verticalCenter: parent.verticalCenter
    }
}
