import QtQuick
import QtQuick.Controls
import CAMX.Theme 1.0

// 拾取模式切换下拉框：位于「视图」标签的 ribbon 工具栏中，选择拾取对象类型（无/体/面/边/点）。
// 由父级绑定 viewport（Viewport）与 pickMode（当前生效模式），用户选择后调用
// viewport.setPickMode(mode) 转发给 GraphicsViewport。
// 样式与 DisplayModeSelector 一致：白色底、深色文字，匹配 ribbon 的浅色工具条。
ComboBox {
    id: combo

    // 目标视口（Viewport）：用于调用 setPickMode
    property var viewport: null
    // 当前拾取模式（0..4，对应 PickMode 枚举），由视口回写后同步选中项
    property int pickMode: 0

    width: 96
    height: 30

    model: [
        { text: "无", mode: 0 },
        { text: "体", mode: 1 },
        { text: "面", mode: 2 },
        { text: "边", mode: 3 },
        { text: "点", mode: 4 }
    ]
    textRole: "text"

    // 视口回写拾取模式时同步选中项（用处理器而非绑定，避免与用户选择互相覆盖）
    onPickModeChanged: currentIndex = pickMode

    // 组件创建时按初始 pickMode 同步一次选中项
    Component.onCompleted: currentIndex = pickMode

    onActivated: function(index) {
        var item = model[index]
        if (item && viewport && viewport.setPickMode)
            viewport.setPickMode(item.mode)
    }

    // 浅色圆角背景（匹配 ribbon 白色工具条）
    background: Rectangle {
        radius: 4
        color: combo.activeFocus ? "#ffffff" : "#fdfdfd"
        border.color: combo.activeFocus ? "#d97706" : "#c8c8c8"
        border.width: 1
    }

    contentItem: Text {
        leftPadding: 12
        rightPadding: combo.indicator.width + 10
        text: combo.displayText
        color: "#2a2a2a"
        font.pixelSize: 12
        font.family: Theme.fontFamily
        verticalAlignment: Text.AlignVCenter
        elide: Text.ElideRight
    }

    indicator: Canvas {
        x: combo.width - width - 10
        y: (combo.height - height) / 2
        width: 10
        height: 6
        onPaint: {
            var ctx = getContext("2d")
            ctx.strokeStyle = "#777777"
            ctx.lineWidth = 1.5
            ctx.beginPath()
            ctx.moveTo(1, 1)
            ctx.lineTo(5, 5)
            ctx.lineTo(9, 1)
            ctx.stroke()
        }
    }

    popup: Popup {
        y: combo.height + 4
        width: combo.width
        padding: 4
        implicitHeight: contentItem.implicitHeight

        contentItem: ListView {
            clip: true
            implicitHeight: contentHeight
            model: combo.popup.visible ? combo.delegateModel : null
            currentIndex: combo.highlightedIndex
        }

        background: Rectangle {
            radius: 6
            color: "#ffffff"
            border.color: "#d0d0d0"
            border.width: 1
        }
    }

    delegate: ItemDelegate {
        width: combo.width - 8
        height: 28
        highlighted: combo.highlightedIndex === index

        contentItem: Text {
            text: modelData.text
            color: highlighted ? "#d97706" : "#2a2a2a"
            font.pixelSize: 12
            font.family: Theme.fontFamily
            verticalAlignment: Text.AlignVCenter
            elide: Text.ElideRight
        }

        background: Rectangle {
            radius: 4
            color: highlighted ? "#fdf3e3" : "transparent"
        }
    }
}
