import QtQuick
import CAMX.Theme 1.0

// ribbon 工具组：一排按钮在上、分类标题在下（标题紧贴组的下边框），左侧可选分割线。
// 图标映射与动作分发已上移到 Ribbon（host.iconForAction / host.triggerAction），
// 使展开态按钮与收起态下拉菜单共用同一套命令逻辑。
//
// widget 取值：
//   ""        = 常规按钮组（buttonsRow）
//   "displayMode" = 显示模式图标按钮组（形状 + 网格，选项来自 host.shapeModes/host.meshModes）
//   "pickMode"  = 拾取模式图标按钮组（PickModeSelector）
Item {
    id: group
    property string title: ""
    property var actions: []
    property bool showDivider: false
    property string widget: ""      // 见上方注释
    property var viewport: null     // 显示模式/拾取控件的目标视口（Viewport）
    property var host: null         // 所属 Ribbon（提供图标映射与动作分发）

    implicitWidth: contentArea.width + (group.showDivider ? 13 : 0)

    // 组间分割线
    Rectangle {
        id: divider
        width: group.showDivider ? 1 : 0
        color: Theme.borderLight
        anchors.left: parent.left
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.topMargin: 8
        anchors.bottomMargin: 8
    }

    // 内容区：位于分割线右侧，撑满组的高度；按钮靠上、分类标题靠下边框
    Item {
        id: contentArea
        width: group.widget === "displayMode" ? displayModeSelector.width
             : (group.widget === "pickMode" ? pickModeSelector.width : buttonsRow.width)
        anchors.left: divider.right
        anchors.leftMargin: group.showDivider ? 12 : 0
        anchors.top: parent.top
        anchors.bottom: parent.bottom

        // 显示模式图标按钮组（形状 + 网格）
        DisplayModeSelector {
            id: displayModeSelector
            anchors.top: parent.top
            anchors.topMargin: 16
            anchors.horizontalCenter: parent.horizontalCenter
            visible: group.widget === "displayMode"
            viewport: group.viewport
            displayMode: group.viewport ? group.viewport.displayMode : 0
            shapeModes: group.host ? group.host.shapeModes : []
            meshModes: group.host ? group.host.meshModes : []
        }

        // 拾取模式图标按钮组（无/体/面/边/点）
        PickModeSelector {
            id: pickModeSelector
            anchors.top: parent.top
            anchors.topMargin: 16
            anchors.horizontalCenter: parent.horizontalCenter
            visible: group.widget === "pickMode"
            viewport: group.viewport
            pickMode: group.viewport ? group.viewport.pickMode : 2
        }

        // 按钮行（上）—— 常规工具组
        Row {
            id: buttonsRow
            anchors.top: parent.top
            anchors.topMargin: 16
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 2
            visible: group.widget === ""
            Repeater {
                model: group.actions
                RibbonButton {
                    text: modelData
                    icon: group.host ? group.host.iconForAction(modelData) : ""
                    onClicked: if (group.host) group.host.triggerAction(modelData)
                }
            }
        }

        // 分类标题（下，紧贴组的下边框）
        Text {
            text: group.title
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 6
            anchors.horizontalCenter: parent.horizontalCenter
            color: Theme.textMuted
            font.pixelSize: 10
            font.family: Theme.fontFamily
        }
    }
}
