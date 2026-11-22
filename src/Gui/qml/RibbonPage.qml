import QtQuick

// ribbon 单个标签页内容：切换时柔和地淡入淡出 + 轻微上移/缩放。
// 通过 groups 数组驱动，新增工具组只需在 tabs 数据里加一项。
Item {
    id: page
    property bool current: false
    property var groups: []   // [{ name: string, actions: [string], widget?: string }]
    property var viewport: null   // 透传给工具组（如显示模式下拉框）
    property var host: null       // 所属 Ribbon（提供图标映射与动作分发）

    width: parent.width
    height: parent.height

    opacity: current ? 1 : 0
    visible: current || opacity > 0
    scale: current ? 1 : 0.99
    y: current ? 0 : 3
    z: current ? 1 : 0
    transformOrigin: Item.Center

    Behavior on opacity { NumberAnimation { duration: 320; easing.type: Easing.OutQuad } }
    Behavior on scale   { NumberAnimation { duration: 320; easing.type: Easing.OutQuad } }
    Behavior on y       { NumberAnimation { duration: 320; easing.type: Easing.OutQuad } }

    Row {
        id: contentRow
        anchors.fill: parent
        anchors.leftMargin: 10
        anchors.rightMargin: 10
        spacing: 8

        Repeater {
            model: page.groups
            RibbonGroup {
                height: contentRow.height
                title: modelData.name
                actions: modelData.actions ? modelData.actions : []
                widget: modelData.widget ? modelData.widget : ""
                viewport: page.viewport
                host: page.host
                showDivider: index > 0
            }
        }
    }
}
