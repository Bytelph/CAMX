import QtQuick
import QtQuick.Controls
import QtQuick.Window
import CAMX.Theme 1.0

// 刀具库弹窗（独立无边框浮动窗口）：
//   标题栏 → 菜单栏（刀具/探针/刀柄/配置/选项，前三个切换下方按钮区）
//   → 工具按钮区 → 左「刀具装配表」 / 右「3D 刀具装配视图 + 装配信息」→ 底部按钮
// 由 CamxWindow 以 ownerWindow / transientParent 绑定主窗口，首次打开时在主窗口中央弹出。
// M0 阶段仅界面与轻量交互：点击工具按钮回填装配信息并在 3D 视图中预览轮廓、页签切换。
// 真正的刀具数据、装配与全局刀具库由 ToolLib 模块接入后再绑定。
Window {
    id: dlg
    title: "刀具库"
    flags: Qt.Window | Qt.FramelessWindowHint
    color: "#f2f3f5"
    visible: false

    // 首次打开时居中的参考窗口（主文档窗口）
    property var ownerWindow: null
    property bool centered: false

    width: Math.min(1420, Screen.desktopAvailableWidth - 80)
    height: Math.min(900, Screen.desktopAvailableHeight - 80)
    minimumWidth: 1200
    minimumHeight: 720

    property string selectedTool: ""   // 当前点击的工具（回填装配信息「描述」）
    property string selectedKind: ""   // 当前点击工具的轮廓（3D 装配视图预览用）
    property int toolPage: 0           // 按钮区当前页：0=刀具 1=探针 2=刀柄
    property int infoTab: 2            // 装配信息页签：0=偏置 1=寄存 2=装夹

    readonly property color lineColor: "#dde1e6"
    readonly property color textColor: "#2b3038"
    readonly property color textMuted: "#6b7280"
    readonly property color accentBlue: "#2f6fd0"

    // —— 菜单栏：前三个切换按钮区，后两个为占位菜单 ——
    property var menuItems: [
        { text: "刀具", page: 0 },
        { text: "探针", page: 1 },
        { text: "刀柄", page: 2 },
        { text: "配置", page: -1 },
        { text: "选项", page: -2 }
    ]

    // —— 按钮区内容：按菜单页切换；kind 对应 ToolGlyph 轮廓 ——
    property var paletteGroups: [
        // 0：刀具 → 铣刀 / 车刀
        [
            { name: "铣刀", tools: [
                { label: "平底立铣刀",   kind: "flat" },
                { label: "球头立铣刀",   kind: "ball" },
                { label: "圆鼻立铣刀",   kind: "bull" },
                { label: "锥度立铣刀",   kind: "taper" },
                { label: "倒角铣刀",     kind: "chamfer" },
                { label: "钻头",         kind: "drill" },
                { label: "定心钻",       kind: "spot" },
                { label: "燕尾铣刀",     kind: "dovetail" },
                { label: "T型槽铣刀",    kind: "tslot" },
                { label: "螺纹铣刀",     kind: "thread" },
                { label: "锯片铣刀",     kind: "disc" }
            ]},
            { name: "车刀", tools: [
                { label: "外圆车刀",     kind: "insert_diamond" },
                { label: "内孔车刀",     kind: "insert_square" },
                { label: "切槽刀",       kind: "insert_triangle" },
                { label: "螺纹车刀",     kind: "insert_round" }
            ]}
        ],
        // 1：探针
        [
            { name: "探针", tools: [
                { label: "球头探针",     kind: "probe_ball" },
                { label: "雷尼绍探头",   kind: "renishaw" }
            ]}
        ],
        // 2：刀柄
        [
            { name: "刀柄", tools: [
                { label: "参数化刀柄",   kind: "holder_param" },
                { label: "坐标化刀柄",   kind: "holder_coord" }
            ]}
        ]
    ]
    readonly property var currentGroups: paletteGroups[toolPage]

    // 刀具装配表表头（width = -1 表示自适应剩余宽度）
    property var assemblyColumns: [
        { label: "ID",   width: 48 },
        { label: "名称", width: 110 },
        { label: "刀具", width: 110 },
        { label: "刀柄", width: 100 },
        { label: "直径", width: 70 },
        { label: "悬伸", width: 70 },
        { label: "描述", width: -1 },
        { label: "状态", width: 56 }
    ]
    readonly property int fixedColumnWidth: 564   // 上表固定列宽之和
    readonly property int rightColumnWidth: 480   // 右侧「3D 视图 + 装配信息」宽度

    // 打开弹窗：首次打开时相对主窗口居中，之后保留用户拖动的位置
    function open() {
        if (!centered && ownerWindow) {
            x = Math.round(ownerWindow.x + (ownerWindow.width - width) / 2)
            y = Math.round(ownerWindow.y + (ownerWindow.height - height) / 2)
            centered = true
        }
        show()
        raise()
        requestActivate()
    }

    // Windows 11 圆角（与主窗口一致）
    onVisibleChanged: if (visible) WindowController.applyWindowCorners(dlg)

    // Esc 关闭
    Shortcut {
        sequence: StandardKey.Cancel
        context: Qt.WindowShortcut
        onActivated: dlg.close()
    }

    // —— 窗口内容 ——
    Rectangle {
        id: frame
        anchors.fill: parent
        color: "#f2f3f5"
        border.color: "#9aa0a8"
        border.width: 1

        // ================= 标题栏 + 菜单栏 =================
        Rectangle {
            id: headerBlock
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            height: 72
            color: "#ffffff"

            Rectangle {
                anchors.bottom: parent.bottom
                anchors.left: parent.left
                anchors.right: parent.right
                height: 1
                color: dlg.lineColor
            }

            // 标题行（整行可拖动窗口）
            Item {
                id: titleRow
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: parent.right
                height: 44

                MouseArea {
                    id: titleDrag
                    anchors.fill: parent
                    acceptedButtons: Qt.LeftButton

                    property bool dragging: false
                    property real pressX: 0
                    property real pressY: 0

                    onPressed: (mouse) => {
                        dragging = false
                        pressX = mouse.x
                        pressY = mouse.y
                    }
                    onPositionChanged: (mouse) => {
                        if (dragging) return
                        if (Math.abs(mouse.x - pressX) + Math.abs(mouse.y - pressY) > 6) {
                            dragging = true
                            WindowController.startSystemMove(dlg)
                        }
                    }
                    onReleased: dragging = false
                    onCanceled: dragging = false
                }

                Row {
                    anchors.left: parent.left
                    anchors.leftMargin: 14
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 8

                    ToolIcon {
                        name: "toollib"
                        size: 20
                        color: dlg.accentBlue
                    }
                    Text {
                        text: "刀具库"
                        color: "#1f2329"
                        font.pixelSize: 15
                        font.bold: true
                        font.family: Theme.fontFamily
                    }
                }

                // 窗口控制按钮（最小化 / 关闭）
                Row {
                    anchors.right: parent.right
                    anchors.top: parent.top
                    height: 40

                    WindowButton {
                        type: "min"
                        onClicked: WindowController.minimize(dlg)
                    }
                    WindowButton {
                        type: "close"
                        onClicked: dlg.close()
                    }
                }
            }

            // 菜单栏：刀具 / 探针 / 刀柄 / 配置 / 选项
            Row {
                anchors.left: parent.left
                anchors.leftMargin: 8
                anchors.top: titleRow.bottom
                height: 28
                spacing: 2

                Repeater {
                    model: dlg.menuItems

                    Item {
                        width: menuLabel.implicitWidth + 26
                        height: 28
                        readonly property bool active: modelData.page === dlg.toolPage

                        Rectangle {
                            anchors.fill: parent
                            radius: 3
                            color: parent.active ? "#eef4fd"
                                                   : (menuMouse.containsMouse ? "#f2f4f7" : "transparent")
                        }

                        Text {
                            id: menuLabel
                            anchors.centerIn: parent
                            text: modelData.text
                            color: parent.active ? dlg.accentBlue
                                                 : (menuMouse.containsMouse ? "#1f2329" : "#4b5563")
                            font.pixelSize: 12
                            font.family: Theme.fontFamily
                        }

                        Rectangle {
                            anchors.bottom: parent.bottom
                            anchors.horizontalCenter: parent.horizontalCenter
                            width: parent.active ? parent.width - 12 : 0
                            height: 2
                            radius: 1
                            color: dlg.accentBlue
                        }

                        MouseArea {
                            id: menuMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                if (modelData.page >= 0)
                                    dlg.toolPage = modelData.page
                                else
                                    console.log(modelData.text + "菜单（待接入）")
                            }
                        }
                    }
                }
            }
        }

        // ================= 工具按钮区（按菜单页切换） =================
        Rectangle {
            id: toolbar
            anchors.top: headerBlock.bottom
            anchors.left: parent.left
            anchors.right: parent.right
            height: 96
            color: "#f8f9fa"
            clip: true

            Rectangle {
                anchors.bottom: parent.bottom
                anchors.left: parent.left
                anchors.right: parent.right
                height: 1
                color: dlg.lineColor
            }

            Row {
                anchors.left: parent.left
                anchors.leftMargin: 10
                anchors.top: parent.top
                anchors.topMargin: 4
                spacing: 10

                Repeater {
                    model: dlg.currentGroups

                    // 一组按钮：[分类标签 + 按钮排] + 组间分割线
                    Row {
                        spacing: 10

                        Column {
                            spacing: 2

                            Item {
                                width: toolsRow.width
                                height: 16

                                Text {
                                    anchors.right: parent.right
                                    anchors.rightMargin: 2
                                    text: modelData.name
                                    color: "#4b5563"
                                    font.pixelSize: 12
                                    font.bold: true
                                    font.family: Theme.fontFamily
                                }
                            }

                            Row {
                                id: toolsRow
                                spacing: 2

                                Repeater {
                                    model: modelData.tools

                                    Rectangle {
                                        id: toolBtn
                                        width: Math.max(46, toolCaption.implicitWidth + 12)
                                        height: 64
                                        radius: 4
                                        readonly property bool selected: dlg.selectedTool === modelData.label
                                        color: selected ? "#dce8fa"
                                                       : (toolMouse.containsMouse ? "#e9ecef" : "transparent")
                                        border.color: selected ? dlg.accentBlue : "transparent"
                                        border.width: selected ? 1 : 0

                                        Column {
                                            anchors.centerIn: parent
                                            spacing: 2

                                            ToolGlyph {
                                                width: 26
                                                height: 40
                                                x: (toolBtn.width - width) / 2
                                                kind: modelData.kind
                                            }

                                            Text {
                                                id: toolCaption
                                                width: toolBtn.width
                                                text: modelData.label
                                                horizontalAlignment: Text.AlignHCenter
                                                color: toolBtn.selected ? dlg.accentBlue : "#4b5563"
                                                font.pixelSize: 10
                                                font.family: Theme.fontFamily
                                            }
                                        }

                                        ToolTip.visible: toolMouse.containsMouse
                                        ToolTip.text: modelData.label
                                        ToolTip.delay: 400

                                        MouseArea {
                                            id: toolMouse
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: {
                                                dlg.selectedTool = modelData.label
                                                dlg.selectedKind = modelData.kind
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        // 组间分割线（最后一组不画）
                        Rectangle {
                            width: index < dlg.currentGroups.length - 1 ? 1 : 0
                            height: 70
                            color: dlg.lineColor
                        }
                    }
                }
            }
        }

        // ================= 底部按钮 =================
        Rectangle {
            id: footer
            anchors.bottom: parent.bottom
            anchors.left: parent.left
            anchors.right: parent.right
            height: 56
            color: "#ffffff"

            Rectangle {
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: parent.right
                height: 1
                color: dlg.lineColor
            }

            DialogButton {
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.verticalCenter: parent.verticalCenter
                width: 160
                text: "进入全局刀具库"
                onClicked: console.log("进入全局刀具库（待接入）")
            }

            Row {
                anchors.right: parent.right
                anchors.rightMargin: 14
                anchors.verticalCenter: parent.verticalCenter
                spacing: 10

                DialogButton {
                    width: 96
                    text: "确定"
                    primary: true
                    onClicked: {
                        console.log("刀具库 · 确定")
                        dlg.close()
                    }
                }
                DialogButton {
                    width: 96
                    text: "取消"
                    onClicked: dlg.close()
                }
            }
        }

        // ================= 主体：左「刀具装配表」/ 右「3D 视图 + 装配信息」=================
        Item {
            id: body
            anchors.top: toolbar.bottom
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: footer.top

            // —— 左：刀具装配表 ——
            Column {
                id: assemblyPanel
                anchors.left: parent.left
                anchors.leftMargin: 12
                anchors.top: parent.top
                anchors.topMargin: 10
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 12
                width: Math.max(420, body.width - rightColumn.width - 36)

                Text {
                    height: 22
                    text: "刀具装配表"
                    color: dlg.textColor
                    font.pixelSize: 12
                    font.bold: true
                    font.family: Theme.fontFamily
                    verticalAlignment: Text.AlignVCenter
                }

                Rectangle {
                    width: parent.width
                    height: parent.height - 22
                    color: "#ffffff"
                    border.color: "#d3d7dc"
                    border.width: 1
                    radius: 3
                    clip: true

                    // 表头
                    Row {
                        id: tableHeader
                        anchors.top: parent.top
                        anchors.left: parent.left
                        anchors.right: parent.right
                        height: 32

                        Repeater {
                            model: dlg.assemblyColumns

                            Item {
                                width: modelData.width > 0
                                       ? modelData.width
                                       : Math.max(80, tableHeader.width - dlg.fixedColumnWidth)
                                height: tableHeader.height

                                Text {
                                    anchors.left: parent.left
                                    anchors.leftMargin: 8
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: modelData.label
                                    color: "#4b5563"
                                    font.pixelSize: 12
                                    font.family: Theme.fontFamily
                                }
                                Rectangle {
                                    width: 1
                                    anchors.right: parent.right
                                    anchors.top: parent.top
                                    anchors.bottom: parent.bottom
                                    color: "#eceff2"
                                }
                            }
                        }
                    }

                    Rectangle {
                        anchors.top: tableHeader.bottom
                        anchors.left: parent.left
                        anchors.right: parent.right
                        height: 1
                        color: dlg.lineColor
                    }

                    // 空列表区（数据接入后替换为 ListView / TableView）
                    Text {
                        anchors.centerIn: parent
                        text: "暂无刀具装配"
                        color: "#a0a6ae"
                        font.pixelSize: 12
                        font.family: Theme.fontFamily
                    }
                }
            }

            // —— 右：3D 刀具装配视图 + 装配信息 ——
            Item {
                id: rightColumn
                anchors.right: parent.right
                anchors.rightMargin: 12
                anchors.top: parent.top
                anchors.topMargin: 10
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 12
                width: dlg.rightColumnWidth

                Text {
                    id: viewTitle
                    anchors.top: parent.top
                    anchors.left: parent.left
                    anchors.right: parent.right
                    height: 22
                    text: "3D 刀具装配视图"
                    color: dlg.textColor
                    font.pixelSize: 12
                    font.bold: true
                    font.family: Theme.fontFamily
                    verticalAlignment: Text.AlignVCenter
                }

                // 3D 装配视图（深色画布，待接入 Graphics 模块后替换为真实渲染）
                Rectangle {
                    id: view3d
                    anchors.top: viewTitle.bottom
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: infoTitle.top
                    anchors.bottomMargin: 10
                    color: "#3a3d42"
                    radius: 3
                    clip: true

                    // 选中刀具的示意轮廓（真的 3D 装配渲染接入前的占位）
                    ToolGlyph {
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.verticalCenterOffset: -12
                        width: 120
                        height: 180
                        visible: dlg.selectedKind !== ""
                        kind: dlg.selectedKind !== "" ? dlg.selectedKind : "flat"
                    }

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.bottom: parent.bottom
                        anchors.bottomMargin: 12
                        text: dlg.selectedTool !== "" ? dlg.selectedTool : "请选择刀具或刀柄以预览装配"
                        color: dlg.selectedTool !== "" ? "#cfd4da" : "#8f959d"
                        font.pixelSize: 12
                        font.family: Theme.fontFamily
                    }
                }

                Text {
                    id: infoTitle
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: infoBox.top
                    height: 22
                    text: "装配信息"
                    color: dlg.textColor
                    font.pixelSize: 12
                    font.bold: true
                    font.family: Theme.fontFamily
                    verticalAlignment: Text.AlignVCenter
                }

                Rectangle {
                    id: infoBox
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    height: 264
                    color: "#ffffff"
                    border.color: "#d3d7dc"
                    border.width: 1
                    radius: 3
                    clip: true

                    Column {
                        anchors.top: parent.top
                        anchors.topMargin: 12
                        anchors.left: parent.left
                        anchors.leftMargin: 12
                        anchors.right: parent.right
                        anchors.rightMargin: 12
                        spacing: 8

                        FormRow { label: "描述:"; text: dlg.selectedTool }
                        FormRow { label: "刀具号:" }
                        FormRow { label: "ID:" }

                        // 装配信息页签：偏置 / 寄存 / 装夹
                        Item {
                            width: parent.width
                            height: 30

                            Row {
                                anchors.left: parent.left
                                anchors.bottom: parent.bottom
                                spacing: 2

                                Repeater {
                                    model: ["偏置", "寄存", "装夹"]

                                    Item {
                                        width: infoTabLabel.implicitWidth + 26
                                        height: 28

                                        Text {
                                            id: infoTabLabel
                                            anchors.centerIn: parent
                                            text: modelData
                                            color: index === dlg.infoTab ? dlg.accentBlue : dlg.textMuted
                                            font.pixelSize: 12
                                            font.family: Theme.fontFamily
                                        }
                                        Rectangle {
                                            anchors.bottom: parent.bottom
                                            anchors.horizontalCenter: parent.horizontalCenter
                                            width: parent.width
                                            height: 2
                                            color: index === dlg.infoTab ? dlg.accentBlue : "transparent"
                                        }
                                        MouseArea {
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: dlg.infoTab = index
                                        }
                                    }
                                }
                            }

                            Rectangle {
                                anchors.bottom: parent.bottom
                                anchors.left: parent.left
                                anchors.right: parent.right
                                height: 1
                                color: dlg.lineColor
                            }
                        }

                        // 装夹内容（仅「装夹」页签显示）
                        Column {
                            width: parent.width
                            spacing: 6
                            visible: dlg.infoTab === 2
                            height: dlg.infoTab === 2 ? 94 : 0

                            FormRow { label: "装夹点:";   text: "0,0,0 mm" }
                            FormRow { label: "装夹角度:"; text: "0,0,0 °" }

                            Row {
                                spacing: 8
                                DialogButton {
                                    width: 96
                                    text: "自动装夹"
                                    onClicked: console.log("自动装夹（待接入）")
                                }
                                DialogButton {
                                    width: 96
                                    text: "自动对刀"
                                    onClicked: console.log("自动对刀（待接入）")
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // —— 四周缩放把手（无边框窗口手动提供边缘拖拽缩放）——
    WindowResizeHandle { target: dlg; edges: 2;  cursorShape: Qt.SizeVerCursor;  anchors.top: parent.top;       anchors.left: parent.left;   anchors.right: parent.right;  height: 5; z: 100 }
    WindowResizeHandle { target: dlg; edges: 8;  cursorShape: Qt.SizeVerCursor;  anchors.bottom: parent.bottom; anchors.left: parent.left;   anchors.right: parent.right;  height: 5; z: 100 }
    WindowResizeHandle { target: dlg; edges: 1;  cursorShape: Qt.SizeHorCursor;  anchors.left: parent.left;     anchors.top: parent.top;      anchors.bottom: parent.bottom; width: 5;  z: 100 }
    WindowResizeHandle { target: dlg; edges: 4;  cursorShape: Qt.SizeHorCursor;  anchors.right: parent.right;   anchors.top: parent.top;      anchors.bottom: parent.bottom; width: 5;  z: 100 }
    WindowResizeHandle { target: dlg; edges: 3;  cursorShape: Qt.SizeFDiagCursor; anchors.top: parent.top;       anchors.left: parent.left;   width: 8; height: 8; z: 101 }
    WindowResizeHandle { target: dlg; edges: 6;  cursorShape: Qt.SizeBDiagCursor; anchors.top: parent.top;       anchors.right: parent.right;  width: 8; height: 8; z: 101 }
    WindowResizeHandle { target: dlg; edges: 9;  cursorShape: Qt.SizeBDiagCursor; anchors.bottom: parent.bottom; anchors.left: parent.left;   width: 8; height: 8; z: 101 }
    WindowResizeHandle { target: dlg; edges: 12; cursorShape: Qt.SizeFDiagCursor; anchors.bottom: parent.bottom; anchors.right: parent.right;  width: 8; height: 8; z: 101 }
}
