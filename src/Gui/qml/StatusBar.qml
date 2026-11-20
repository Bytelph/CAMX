import QtQuick
import QtQuick.Controls
import CAMX.Theme 1.0

// 底部状态栏
Rectangle {
    id: bar
    height: 24
    color: Theme.bgPanelAlt
    border.color: Theme.border

    // 由 Main.qml 传入：鼠标指向的 3D 世界坐标（悬停在模型上时更新，空白处为空串）
    property string cursorCoordinates: ""
    // 最近一次模型导入的结果消息（"已导入：xxx" / "导入失败：…"）
    property string importStatus: ""
    // 最近一次模型导出的结果消息（"已导出：xxx" / "导出失败：…"）
    property string exportStatus: ""
    // 模型导入进度（-1 = 隐藏，0..1 = 进行中），由 CamxWindow 从视口透传
    property real importProgress: -1

    // 中间栏显示最近一次导入/导出结果（导入优先；两者皆空则留白）
    readonly property string lastResult: bar.importStatus !== "" ? bar.importStatus : bar.exportStatus

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

    // 中间：导入/导出结果消息
    Text {
        text: bar.lastResult
        color: bar.lastResult.indexOf("失败") >= 0 ? "#d04a4a" : Theme.textDim
        font.pixelSize: 11
        font.family: Theme.fontFamily
        anchors.horizontalCenter: parent.horizontalCenter
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

    // 模型导入进度条：中等宽度，位于状态栏右侧（导入期间显示，完成/空闲时隐藏）。
    // 用普通 Rectangle 而非 ProgressBar 控件：当前 Qt Quick Controls 样式不支持自定义
    // ProgressBar 的 background/contentItem（会打印 "does not support customization" 警告并
    // 忽略自定义外观，导致进度条按默认样式渲染或不可见），故这里直接画轨道 + 填充条。
    Item {
        id: importBar
        width: 280
        height: 14
        visible: bar.importProgress >= 0
        anchors.right: unitText.left
        anchors.rightMargin: 12
        anchors.verticalCenter: parent.verticalCenter

        // 轨道
        Rectangle {
            anchors.fill: parent
            radius: 7
            color: Theme.borderLight
        }
        // 填充
        Rectangle {
            width: Math.max(0, Math.min(1, bar.importProgress)) * importBar.width
            height: importBar.height
            radius: 7
            color: "#3b82f6"
        }
    }
}
