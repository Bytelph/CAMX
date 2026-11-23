import QtQuick
import QtQuick.Controls
import QtQuick.Window
import QtQml
import CAMX.Theme 1.0
import CAMX.WindowManager 1.0

// 工作区 ribbon（现代 Word 风格）：
//   第一行 = 标题栏（应用名 + 快速操作 + 拖动区 + 窗口控制按钮）
//   第二行 = 标签栏（菜单，独立于快速操作行）
//   第三行 = 当前标签的工具组
// 标签与内容均由下方 tabs 数组驱动，新增标签只需在数组里加一项即可自动扩展。
Rectangle {
    id: ribbon
    property var target: null
    property var viewport: null               // 中央 3D 视口（Viewport），供「视图」标签的显示模式下拉框调用
    property string projectName: "未命名.ccpj"   // 当前项目名（M0 占位，待 App 文档模块接入后绑定真实项目）
    property bool collapsed: false               // ribbon 收起/展开：收起时隐藏第三行工具组
    property var collapsedEntries: []            // 收起态下拉菜单当前标签页的条目（共享菜单的模型）
    height: collapsed ? 68 : 188   // 标题栏 40 + 标签栏 28 + 内容区 120（收起时内容区为 0）
    Behavior on height { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
    // Win11 标题栏风格的清淡纵向渐变（第一二三行共用）
    gradient: Gradient {
        GradientStop { position: 0.0; color: "#f7f9fc" }
        GradientStop { position: 1.0; color: "#e5ebf2" }
    }

    // —— 可扩展标签数据：title = 标签名，groups = 工具组列表 ——
    property var tabs: [
        { title: "文件", groups: [
            { name: "文件操作", actions: ["新建项目", "导入模型", "保存", "另存为"] },
            { name: "数据交换", actions: ["导出模型", "CLData"] }
        ]},
        { title: "视图", groups: [
            { name: "视角", actions: ["适应", "平移", "旋转", "缩放"] },
            { name: "显示模式", widget: "displayMode" },
            { name: "拾取", widget: "pickMode" },
            { name: "显示", widget: "display" },
            { name: "导航", actions: ["前视", "俯视", "侧视", "等轴测"] }
        ]},
        { title: "AICAM", groups: [
            { name: "工序", actions: ["新建工序", "复制", "粘贴", "删除"] },
            { name: "2.5D", actions: ["面铣", "型腔", "轮廓", "钻孔"] },
            { name: "3D", actions: ["平行", "等高", "环绕", "清根"] }
        ]},
        { title: "仿真", groups: [
            { name: "几何仿真", actions: ["开始", "暂停", "重置", "余量分析"] },
            { name: "物理仿真", actions: ["切削力", "变形", "温度"] },
            { name: "检查", actions: ["过切", "碰撞"] }
        ]},
        { title: "配置", groups: [
            { name: "系统", actions: ["单位", "语言", "路径"] },
            { name: "库", actions: ["刀具库", "机床库", "后处理"] },
            { name: "参数", actions: ["默认参数", "公差"] }
        ]},
        { title: "帮助", groups: [
            { name: "帮助", actions: ["文档", "快捷键", "关于"] },
            { name: "在线", actions: ["官网", "更新", "反馈"] }
        ]}
    ]

    // —— 显示/拾取模式选项（显示模式现为图标切换，选项同时供收起态下拉菜单使用）——
    // 显示模式拆成形状（DisplayMode 0..3）与网格（DisplayMode 4..7）两个子类，
    // 收起态菜单里再加「形状 ·」/「网格 ·」前缀以区分来源。
    property var shapeModes: [
        { text: "线框",     mode: 0, icon: "disp_wire" },
        { text: "隐藏线",   mode: 1, icon: "disp_hidden" },
        { text: "着色",     mode: 2, icon: "disp_shaded" },
        { text: "着色带边", mode: 3, icon: "disp_shadeedge" }
    ]
    property var meshModes: [
        { text: "线框", mode: 4, icon: "disp_meshwire" },
        { text: "着色", mode: 5, icon: "disp_meshshade" },
        { text: "实体", mode: 6, icon: "disp_solid" },
        { text: "收缩", mode: 7, icon: "disp_shrink" }
    ]
    property var pickModes: [
        { text: "无", mode: 0 },
        { text: "体", mode: 1 },
        { text: "面", mode: 2 },
        { text: "边", mode: 3 },
        { text: "点", mode: 4 }
    ]

    // 动作文字 → 图标名映射（ribbon 展开态工具按钮与收起态下拉菜单共用）
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

    // 动作点击分发：ribbon 展开态按钮与收起态下拉菜单共用
    function triggerAction(text) {
        if (text === "新建项目")
            WindowManager.openNewWindow()
        else if (text === "导入模型")
            WindowManager.importModel(ribbon.target)
        else if (text === "导出模型")
            WindowManager.exportModel(ribbon.target)
        else
            console.log("操作：" + text + "（待接入）")
    }

    // 「显示」开关当前是否打开（供收起态下拉菜单回显勾选态）
    function isDisplayToggleOn(key) {
        var vp = ribbon.viewport
        if (!vp)
            return false
        if (key === "grid")
            return !!vp.gridVisible
        if (key === "origin")
            return !!vp.originVisible
        return false
    }

    // 切换「显示」开关（收起态下拉菜单与展开态按钮共用）
    function toggleDisplay(key) {
        var vp = ribbon.viewport
        if (!vp)
            return
        if (key === "grid" && vp.setGridVisible)
            vp.setGridVisible(!vp.gridVisible)
        else if (key === "origin" && vp.setOriginVisible)
            vp.setOriginVisible(!vp.originVisible)
    }

    // 把某个标签页的 groups 展平为收起态下拉菜单条目：
    // { type:"header", text } 分组标题；{ type:"action", text } 常规动作；
    // { type:"mode", target, text, mode } 显示/拾取模式项
    function buildMenuModel(tab) {
        var list = []
        for (var g = 0; g < tab.groups.length; g++) {
            var group = tab.groups[g]
            list.push({ type: "header", text: group.name })
            if (group.widget === "displayMode") {
                for (var i = 0; i < ribbon.shapeModes.length; i++)
                    list.push({ type: "mode", target: "displayMode", text: "形状 · " + ribbon.shapeModes[i].text, mode: ribbon.shapeModes[i].mode })
                for (var j = 0; j < ribbon.meshModes.length; j++)
                    list.push({ type: "mode", target: "displayMode", text: "网格 · " + ribbon.meshModes[j].text, mode: ribbon.meshModes[j].mode })
            } else if (group.widget === "pickMode") {
                for (var j = 0; j < ribbon.pickModes.length; j++)
                    list.push({ type: "mode", target: "pickMode", text: ribbon.pickModes[j].text, mode: ribbon.pickModes[j].mode })
            } else if (group.widget === "display") {
                list.push({ type: "toggle", key: "grid", text: "网格" })
                list.push({ type: "toggle", key: "origin", text: "坐标系" })
            } else if (group.actions) {
                for (var a = 0; a < group.actions.length; a++)
                    list.push({ type: "action", text: group.actions[a] })
            }
        }
        return list
    }

    // 测量菜单文字宽度（用于让收起态菜单按最宽条目自适应宽度）
    TextMetrics {
        id: menuMetrics
        font.pixelSize: 12
        font.family: Theme.fontFamily
    }

    // 在标签栏下方弹出收起态菜单：宽度按最宽条目自适应，高度按条目累加（超长时限高内部滚动）
    function showCollapsedMenu(tab, x, y) {
        var entries = ribbon.buildMenuModel(tab)
        collapsedMenu.entries = entries

        // 宽度 = 最宽条目（左留白 8 + [图标 16 + 间距 6] + 文字 + 右留白 10）
        var w = 0
        for (var i = 0; i < entries.length; i++) {
            menuMetrics.text = entries[i].text
            var extra = entries[i].type === "header" ? 0 : (16 + 6)
            var itemW = 8 + extra + menuMetrics.advanceWidth + 10
            if (itemW > w) w = itemW
        }
        collapsedMenu.width = Math.max(120, w) + collapsedMenu.padding * 2

        // 高度 = 各条目累加（标题 16 / 工具项 22）；若超过标签栏下方可用空间则限高（内部滚动）
        var h = 0
        for (var j = 0; j < entries.length; j++)
            h += entries[j].type === "header" ? 16 : 22
        var avail = (ribbon.target && ribbon.target.height) ? ribbon.target.height - y - 12 : 400
        collapsedMenu.height = Math.min(h + collapsedMenu.padding * 2, avail)

        collapsedMenu.x = x
        collapsedMenu.y = y
        collapsedMenu.open()
    }

    Column {
        anchors.fill: parent
        spacing: 0

        // —— 第一行：标题栏（应用名 + 快速操作 + 拖动区 + 窗口控制按钮）——
        Item {
            id: titleRow
            width: parent.width
            height: 40

            // 拖动窗口 / 双击最大化。
            // - 非最大化：原生标题栏拖动（含 Aero 吸附）。
            // - 最大化：向下拖 → 恢复窗口并跟随鼠标移动。
            // （位于按钮之后，只接管空白处）
            MouseArea {
                id: topDrag
                anchors.fill: parent
                acceptedButtons: Qt.LeftButton

                property bool dragging: false
                property bool restoring: false
                property real pressX: 0
                property real pressY: 0
                property real grabRatioX: 0.5
                property int grabLocalY: 20

                onPressed: (mouse) => {
                    dragging = false
                    restoring = false
                    pressX = mouse.x
                    pressY = mouse.y
                    if (ribbon.target && ribbon.target.visibility === Window.Maximized) {
                        grabRatioX = ribbon.target.width > 0 ? mouse.x / ribbon.target.width : 0.5
                        grabLocalY = Math.round(mouse.y)
                    }
                }

                onPositionChanged: (mouse) => {
                    if (!ribbon.target) return
                    if (restoring) {
                        WindowController.followCursor(ribbon.target, grabRatioX, grabLocalY)
                        return
                    }
                    if (dragging) return

                    if (ribbon.target.visibility === Window.Maximized) {
                        // 最大化：向下拖 → 恢复并跟随鼠标
                        if (mouse.y - pressY > 12) {
                            dragging = true
                            restoring = true
                            WindowController.restoreUnderCursor(ribbon.target, grabRatioX, grabLocalY)
                        }
                    } else if (Math.abs(mouse.x - pressX) + Math.abs(mouse.y - pressY) > 6) {
                        // 非最大化：原生标题栏拖动
                        dragging = true
                        WindowController.startSystemMove(ribbon.target)
                    }
                }

                onReleased: { dragging = false; restoring = false }
                onCanceled: { dragging = false; restoring = false }

                onDoubleClicked: if (ribbon.target) WindowController.toggleMaximize(ribbon.target)
            }

            Text {
                id: logo
                text: "CAMX"
                color: Theme.textBright
                font.pixelSize: 13
                font.bold: true
                font.family: Theme.fontFamily
                anchors.left: parent.left
                anchors.leftMargin: 12
                anchors.verticalCenter: parent.verticalCenter
            }

            // —— 快速访问工具栏（QAT）：保存 / 撤销 / 重做 ——
            Row {
                id: quickActions
                anchors.left: logo.right
                anchors.leftMargin: 8
                anchors.verticalCenter: parent.verticalCenter
                spacing: 2

                ToolIconButton { icon: "save"; tooltip: "保存"; onClicked: console.log("保存（待接入 App 文档模块）") }
                ToolIconButton { icon: "undo"; tooltip: "撤销"; onClicked: console.log("撤销（待接入撤销/重做）") }
                ToolIconButton { icon: "redo"; tooltip: "重做"; onClicked: console.log("重做（待接入撤销/重做）") }
            }

            // —— 项目名：居中显示（第一行中间）——
            Text {
                id: projectNameText
                text: ribbon.projectName
                color: Theme.textBright
                font.pixelSize: 13
                font.family: Theme.fontFamily
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.verticalCenter: parent.verticalCenter
            }

            // —— 搜索框：位于窗口控制按钮左侧 ——
            TextField {
                id: searchField
                width: 200
                height: 28
                anchors.right: windowButtons.left
                anchors.rightMargin: 8
                anchors.verticalCenter: parent.verticalCenter
                placeholderText: "搜索命令、工具…"
                placeholderTextColor: Theme.textMuted
                color: Theme.text
                font.pixelSize: 12
                font.family: Theme.fontFamily
                verticalAlignment: TextInput.AlignVCenter
                leftPadding: 30
                rightPadding: 10
                selectByMouse: true

                background: Rectangle {
                    radius: 4
                    color: "#ffffff"
                    border.color: searchField.activeFocus ? Theme.accent : Theme.borderLight
                    border.width: 1
                }

                ToolIcon {
                    anchors.left: parent.left
                    anchors.leftMargin: 9
                    anchors.verticalCenter: parent.verticalCenter
                    name: "search"
                    size: 14
                    color: Theme.textMuted
                }
            }

            // 窗口控制按钮
            Row {
                id: windowButtons
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.bottom: parent.bottom

                WindowButton {
                    type: "min"
                    onClicked: WindowController.minimize(ribbon.target)
                }
                WindowButton {
                    type: (ribbon.target && ribbon.target.visibility === Window.Maximized) ? "restore" : "max"
                    onClicked: WindowController.toggleMaximize(ribbon.target)
                }
                WindowButton {
                    type: "close"
                    onClicked: WindowController.close(ribbon.target)
                }
            }
        }

        // —— 第二行：标签栏（菜单，独立于快速操作行）——
        Item {
            id: tabRow
            width: parent.width
            height: 28

            Row {
                id: tabs
                property int currentIndex: 0
                anchors.left: parent.left
                anchors.leftMargin: 12
                anchors.verticalCenter: parent.verticalCenter
                spacing: 2

                Repeater {
                    model: ribbon.tabs
                    Rectangle {
                        id: tabRect
                        width: tabText.implicitWidth + 28
                        height: 28
                        radius: 4
                        color: tabMouse.containsMouse ? Theme.bgElevated : "transparent"
                        Behavior on color { ColorAnimation { duration: 120 } }

                        Text {
                            id: tabText
                            text: modelData.title
                            color: index === tabs.currentIndex ? Theme.textBright : (tabMouse.containsMouse ? Theme.textBright : Theme.textDim)
                            font.pixelSize: 14
                            font.bold: index === tabs.currentIndex
                            font.family: Theme.fontFamily
                            anchors.centerIn: parent
                        }

                        Rectangle {
                            anchors.bottom: parent.bottom
                            anchors.horizontalCenter: parent.horizontalCenter
                            width: index === tabs.currentIndex ? parent.width : (tabMouse.containsMouse ? parent.width * 0.5 : 0)
                            height: 2
                            color: index === tabs.currentIndex ? Theme.accent : (tabMouse.containsMouse ? Theme.textMuted : "transparent")
                            Behavior on width { NumberAnimation { duration: 120 } }
                            Behavior on color { ColorAnimation { duration: 120 } }
                        }

                        MouseArea {
                            id: tabMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                // 收起时点击标签 → 弹出传统下拉菜单（位于标签栏正下方）；
                                // 展开时 → 切换 ribbon 页。两种情况都更新当前标签，
                                // 使标签栏底部的高亮下划线跟随点击移动。
                                tabs.currentIndex = index
                                if (ribbon.collapsed) {
                                    var p = tabRect.mapToItem(ribbon, 0, tabRect.height)
                                    ribbon.showCollapsedMenu(modelData, p.x, p.y + 8)
                                }
                            }
                        }
                    }
                }
            }

            // —— 收起/展开 ribbon 按钮（标签栏最右）——
            Rectangle {
                id: collapseBtn
                width: 30
                height: 28
                radius: 4
                anchors.right: parent.right
                anchors.rightMargin: 8
                anchors.verticalCenter: parent.verticalCenter
                color: collapseMouse.containsMouse ? Theme.bgElevated : "transparent"
                Behavior on color { ColorAnimation { duration: 120 } }

                Text {
                    anchors.centerIn: parent
                    text: ribbon.collapsed ? "▾" : "▴"
                    color: collapseMouse.containsMouse ? Theme.textBright : Theme.textDim
                    font.pixelSize: 11
                    font.family: Theme.fontFamily
                }

                ToolTip.visible: collapseMouse.containsMouse
                ToolTip.text: ribbon.collapsed ? "展开功能区" : "收起功能区"
                ToolTip.delay: 400

                MouseArea {
                    id: collapseMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: ribbon.collapsed = !ribbon.collapsed
                }
            }
        }

        // —— 第三行：工具组内容区（整条圆角栏，内部工具组保持扁平）——
        // 高度由 ribbon 总高派生（40 标题栏 + 28 标签栏 = 68），与 ribbon.height 的动画保持同步，
        // 收起时自然缩到 0，展开时恢复到 120，无需单独的 Behavior。
        Item {
            id: content
            width: parent.width
            height: ribbon.height - 68
            clip: true

            Rectangle {
                id: contentBar
                anchors.fill: parent
                anchors.leftMargin: 8
                anchors.rightMargin: 8
                anchors.topMargin: 6
                anchors.bottomMargin: 6
                radius: 10
                color: "#ffffff"
                border.color: Theme.borderLight
                border.width: 1

                Repeater {
                    model: ribbon.tabs
                    RibbonPage {
                        current: index === tabs.currentIndex
                        groups: modelData.groups
                        viewport: ribbon.viewport
                        host: ribbon
                    }
                }
            }
        }
    }

    // —— 收起态下拉菜单（传统菜单栏）：单个共享 Popup，位置/尺寸/内容在点击标签时动态设置 ——
    Popup {
        id: collapsedMenu
        property var entries: []
        padding: 2
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside

        background: Rectangle {
            radius: 6
            color: "#ffffff"
            border.color: "#d0d0d0"
            border.width: 1
        }

        contentItem: ListView {
            id: menuList
            clip: true
            model: collapsedMenu.entries
            boundsBehavior: Flickable.StopAtBounds
            delegate: collapsedMenuDelegate
            ScrollBar.vertical: ScrollBar { }
        }
    }

    // 收起态菜单条目：紧凑的一行（图标 + 文字），悬停高亮
    Component {
        id: collapsedMenuDelegate
        Item {
            id: rowItem
            width: collapsedMenu.width - collapsedMenu.padding * 2
            height: modelData.type === "header" ? 16 : 22

            readonly property bool isToggle: modelData.type === "toggle"
            readonly property bool toggleChecked: isToggle && ribbon.isDisplayToggleOn(modelData.key)

            Rectangle {
                anchors.fill: parent
                radius: 3
                color: (modelData.type !== "header" && rowMouse.containsMouse) ? "#fdf3e3" : "transparent"
            }

            Row {
                anchors.left: parent.left
                anchors.leftMargin: 8
                anchors.verticalCenter: parent.verticalCenter
                spacing: 6

                ToolIcon {
                    width: modelData.type === "header" ? 0 : 16
                    height: 16
                    anchors.verticalCenter: parent.verticalCenter
                    name: modelData.type === "action" ? ribbon.iconForAction(modelData.text) : ""
                    color: rowMouse.containsMouse ? "#d97706" : "#6a6a6a"
                }

                Text {
                    visible: rowItem.isToggle
                    width: rowItem.isToggle ? 14 : 0
                    text: rowItem.toggleChecked ? "✓" : ""
                    color: "#d97706"
                    font.pixelSize: 12
                    font.family: Theme.fontFamily
                    verticalAlignment: Text.AlignVCenter
                }

                Text {
                    text: modelData.text
                    color: modelData.type === "header" ? "#888888"
                         : (rowItem.toggleChecked ? "#d97706"
                         : (rowMouse.containsMouse ? "#d97706" : "#2a2a2a"))
                    font.pixelSize: modelData.type === "header" ? 10 : 12
                    font.bold: modelData.type === "header"
                    font.family: Theme.fontFamily
                    verticalAlignment: Text.AlignVCenter
                }
            }

            MouseArea {
                id: rowMouse
                anchors.fill: parent
                hoverEnabled: true
                acceptedButtons: Qt.LeftButton
                cursorShape: Qt.PointingHandCursor
                enabled: modelData.type !== "header"
                onClicked: {
                    if (modelData.type === "action") {
                        ribbon.triggerAction(modelData.text)
                    } else if (modelData.type === "mode") {
                        var vp = ribbon.viewport
                        if (modelData.target === "displayMode" && vp && vp.setDisplayMode)
                            vp.setDisplayMode(modelData.mode)
                        else if (modelData.target === "pickMode" && vp && vp.setPickMode)
                            vp.setPickMode(modelData.mode)
                    } else if (modelData.type === "toggle") {
                        ribbon.toggleDisplay(modelData.key)
                    }
                    collapsedMenu.close()
                }
            }
        }
    }
}
