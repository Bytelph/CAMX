import QtQuick
import CAMX.Theme 1.0

// 单条消息通知气泡。类型决定左侧色条与图标颜色；进场淡入 + 轻微放大，到期淡出后
// 通过 expired(toastKey) 通知 ToastLayer 移除自身。
Item {
    id: root

    property var toastKey
    property string toastType: "info"
    property string title: ""
    property string message: ""

    signal expired()

    // 各类型强调色 / 图标 / 停留时长
    property color accentColor: {
        switch (toastType) {
        case "success": return "#2e9e5b"
        case "warning": return "#e0913a"
        case "error":   return "#d04a4a"
        default:        return "#3a7bd5"
        }
    }
    property string iconText: {
        switch (toastType) {
        case "success": return "✓"
        case "warning": return "!"
        case "error":   return "✕"
        default:        return "i"
        }
    }
    property int duration: toastType === "error" ? 6000 : (toastType === "warning" ? 5000 : 4000)

    width: 380
    height: body.height

    Rectangle {
        id: body
        width: parent.width
        height: Math.max(46, column.implicitHeight + 20)
        radius: 6
        color: Theme.dark ? "#2e2e2e" : "#ffffff"
        border.color: Theme.dark ? "#4a4a4a" : "#d8dde3"
        border.width: 1

        // 左侧类型色条
        Rectangle {
            width: 4
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            anchors.left: parent.left
            anchors.leftMargin: 4
            radius: 2
            color: root.accentColor
        }

        // 图标圆点
        Rectangle {
            id: iconDot
            width: 20; height: 20; radius: 10
            color: root.accentColor
            anchors.left: parent.left
            anchors.leftMargin: 16
            anchors.verticalCenter: parent.verticalCenter
            Text {
                anchors.centerIn: parent
                text: root.iconText
                color: "#ffffff"
                font.pixelSize: 12
                font.bold: true
            }
        }

        Column {
            id: column
            anchors.left: parent.left
            anchors.leftMargin: 46
            anchors.right: parent.right
            anchors.rightMargin: 14
            anchors.verticalCenter: parent.verticalCenter
            spacing: 2
            Text {
                width: parent.width
                text: root.title
                color: Theme.text
                font.pixelSize: 12
                font.bold: true
                font.family: Theme.fontFamily
                elide: Text.ElideRight
                visible: root.title.length > 0
            }
            Text {
                width: parent.width
                text: root.message
                color: Theme.textDim
                font.pixelSize: 11
                font.family: Theme.fontFamily
                wrapMode: Text.Wrap
                maximumLineCount: 3
                elide: Text.ElideRight
                visible: root.message.length > 0
            }
        }
    }

    // 进场：淡入 + 轻微放大
    Component.onCompleted: {
        root.opacity = 0
        body.scale = 0.96
        enterAnim.start()
        lifetime.start()
    }

    SequentialAnimation {
        id: enterAnim
        ParallelAnimation {
            NumberAnimation { target: root; property: "opacity"; from: 0; to: 1; duration: 200; easing.type: Easing.OutCubic }
            NumberAnimation { target: body; property: "scale"; from: 0.96; to: 1; duration: 200; easing.type: Easing.OutCubic }
        }
    }

    // 到期：淡出后通知 layer 移除
    Timer {
        id: lifetime
        interval: root.duration
        onTriggered: exitAnim.start()
    }

    NumberAnimation {
        id: exitAnim
        target: root
        property: "opacity"
        from: 1; to: 0
        duration: 180
        onStopped: root.expired()
    }
}
