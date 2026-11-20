import QtQuick
import QtQuick.Window
import CAMX.Theme 1.0
import CAMX.WindowManager 1.0

// ribbon 工具组：一排按钮在上、分类标题在下（标题紧贴组的下边框），左侧可选分割线
Item {
    id: group
    property string title: ""
    property var actions: []
    property bool showDivider: false
    property string widget: ""      // "" = 常规按钮组；"displayMode"/"pickMode" = 显示模式/拾取下拉框
    property var viewport: null     // 显示模式/拾取下拉框的目标视口（Viewport）

    implicitWidth: contentArea.width + (group.showDivider ? 13 : 0)

    // 动作文字 → 图标名映射
    function iconForAction(text) {
        switch (text) {
        case "新建项目": return "new"
        case "导入模型": return "import"
        case "保存":     return "save"
        case "另存为":   return "saveas"
        case "导出模型": return "export"
        case "CLData":   return "cldata"

        case "适应":     return "fit"
        case "平移":     return "pan"
        case "旋转":     return "rotate"
        case "缩放":     return "zoom"
        case "网格":     return "grid"
        case "坐标系":   return "axis"
        case "阴影":     return "shade"
        case "线框":     return "wire"
        case "前视":     return "front"
        case "俯视":     return "top"
        case "侧视":     return "side"
        case "等轴测":   return "cube"

        case "新建工序": return "newop"
        case "复制":     return "copy"
        case "粘贴":     return "paste"
        case "删除":     return "delete"
        case "面铣":     return "face"
        case "型腔":     return "pocket"
        case "轮廓":     return "contour"
        case "钻孔":     return "drill"
        case "平行":     return "parallel"
        case "等高":     return "zlevel"
        case "环绕":     return "spiral"
        case "清根":     return "rest"

        case "开始":     return "play"
        case "暂停":     return "pause"
        case "重置":     return "reset"
        case "余量分析": return "stock"
        case "切削力":   return "force"
        case "变形":     return "deform"
        case "温度":     return "temp"
        case "过切":     return "gouge"
        case "碰撞":     return "collide"

        case "单位":     return "units"
        case "语言":     return "lang"
        case "路径":     return "path"
        case "刀具库":   return "toollib"
        case "机床库":   return "machlib"
        case "后处理":   return "post"
        case "默认参数": return "sliders"
        case "公差":     return "tol"

        case "文档":     return "doc"
        case "快捷键":   return "keyboard"
        case "关于":     return "info"
        case "官网":     return "lang"
        case "更新":     return "reset"
        case "反馈":     return "chat"
        default:         return ""
        }
    }

    // 动作点击分发：「新建项目」同进程再开窗口；「导入模型」打开文件选择对话框；
    // 「导出模型」打开保存对话框；其余动作留待接入。
    function onActionClicked(text) {
        if (text === "新建项目")
            WindowManager.openNewWindow()
        else if (text === "导入模型")
            WindowManager.importModel(group.Window.window)
        else if (text === "导出模型")
            WindowManager.exportModel(group.Window.window)
        else
            console.log("操作：" + text + "（待接入）")
    }

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
        width: group.widget === "displayMode" ? displayModeCombo.width
             : (group.widget === "pickMode" ? pickModeCombo.width : buttonsRow.width)
        anchors.left: divider.right
        anchors.leftMargin: group.showDivider ? 12 : 0
        anchors.top: parent.top
        anchors.bottom: parent.bottom

        // 显示模式下拉框（仅「视图」标签的「显示模式」组）
        DisplayModeSelector {
            id: displayModeCombo
            anchors.top: parent.top
            anchors.topMargin: 16
            anchors.horizontalCenter: parent.horizontalCenter
            visible: group.widget === "displayMode"
            viewport: group.viewport
            displayMode: group.viewport ? group.viewport.displayMode : 0
        }

        // 拾取模式下拉框（仅「视图」标签的「拾取」组）
        PickModeSelector {
            id: pickModeCombo
            anchors.top: parent.top
            anchors.topMargin: 16
            anchors.horizontalCenter: parent.horizontalCenter
            visible: group.widget === "pickMode"
            viewport: group.viewport
            pickMode: group.viewport ? group.viewport.pickMode : 0
        }

        // 按钮行（上）—— 常规工具组
        Row {
            id: buttonsRow
            anchors.top: parent.top
            anchors.topMargin: 16
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 2
            visible: group.widget !== "displayMode" && group.widget !== "pickMode"
            Repeater {
                model: group.actions
                RibbonButton {
                    text: modelData
                    icon: group.iconForAction(modelData)
                    onClicked: group.onActionClicked(modelData)
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
