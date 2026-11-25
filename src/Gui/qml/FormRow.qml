import QtQuick
import QtQuick.Controls
import CAMX.Theme 1.0

// 表单行：右对齐标签 + 输入框（刀具库 / 机床库等对话框复用）。
Item {
    id: row
    property string label: ""
    property alias text: field.text
    property string placeholder: ""
    property int labelWidth: 62

    implicitHeight: 26
    width: parent ? parent.width : 0

    Text {
        id: labelText
        width: row.labelWidth
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        text: row.label
        color: "#4b5563"
        font.pixelSize: 12
        font.family: Theme.fontFamily
        horizontalAlignment: Text.AlignRight
        elide: Text.ElideRight
    }

    TextField {
        id: field
        anchors.left: labelText.right
        anchors.leftMargin: 8
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        height: 26
        placeholderText: row.placeholder
        color: "#2b3038"
        placeholderTextColor: "#9aa0a8"
        font.pixelSize: 12
        font.family: Theme.fontFamily
        verticalAlignment: TextInput.AlignVCenter
        leftPadding: 8
        rightPadding: 8
        selectByMouse: true

        background: Rectangle {
            radius: 3
            color: "#ffffff"
            border.color: field.activeFocus ? "#2f6fd0" : "#c8ccd2"
            border.width: 1
        }
    }
}
