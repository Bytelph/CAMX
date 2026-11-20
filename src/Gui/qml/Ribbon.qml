import QtQuick
import QtQuick.Controls
import QtQuick.Window
import CAMX.Theme 1.0

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
            { name: "显示", actions: ["网格", "坐标系", "阴影", "线框"] },
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
                            onClicked: tabs.currentIndex = index
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
                    }
                }
            }
        }
    }
}
