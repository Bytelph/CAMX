import QtQuick
import QtQuick.Controls
import CXCAM.Theme 1.0

// 显示模式切换下拉框：位于「视图」标签的 ribbon 工具栏中，切换当前模型的显示模式。
// 由父级绑定 viewport（Viewport）与 displayMode（当前生效模式），用户选择后调用
// viewport.setDisplayMode(mode) 转发给 GraphicsViewport。
// 样式对齐 ribbon 的浅色工具条（白色底、深色文字），与原先悬浮在 3D 视口上的深色样式不同。
ComboBox {
    id: combo

    // 目标视口（Viewport）：用于调用 setDisplayMode
    property var viewport: null
    // 当前显示模式（0..6，对应 Mayo::DisplayMode），由视口回写后同步选中项
    property int displayMode: 0

    width: 176
    height: 30

    model: [
        { text: "形状 · 线框",      mode: 0 },
        { text: "形状 · 隐藏线",    mode: 1 },
        { text: "形状 · 着色",      mode: 2 },
        { text: "形状 · 着色带边",  mode: 3 },
        { text: "网格 · 线框",      mode: 4 },
        { text: "网格 · 着色",      mode: 5 },
        { text: "网格 · 收缩",      mode: 6 }
    ]
    textRole: "text"

    // 视口回写显示模式时同步选中项（用处理器而非绑定，避免与用户选择互相覆盖）
    onDisplayModeChanged: currentIndex = displayMode

    // 组件创建时按初始 displayMode 同步一次选中项
    Component.onCompleted: currentIndex = displayMode

    onActivated: function(index) {
        var item = model[index]
        if (item && viewport && viewport.setDisplayMode)
            viewport.setDisplayMode(item.mode)
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
