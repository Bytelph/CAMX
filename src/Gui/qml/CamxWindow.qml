import QtQuick
import QtQuick.Controls
import QtQuick.Window
import CAMX.Theme 1.0
import CAMX.NotificationManager 1.0

// 单个 CAMX 文档窗口：由 WindowManager 在同一进程内动态创建（「新建项目」即再开一个）。
// 每个窗口拥有独立的 ribbon / 3D 视口 / 状态栏 / 项目树与无边框窗口控制。
ApplicationWindow {
    id: root
    width: 1440
    height: 900
    title: "CAMX — 计算机辅助制造"
    color: Theme.bg

    // 无边框窗口
    flags: Qt.Window | Qt.FramelessWindowHint

    // Windows 11 圆角：普通状态圆角，最大化/全屏不圆角（Win10 无此 API 自动回退）
    onVisibleChanged: if (visible) WindowController.applyWindowCorners(root)
    onVisibilityChanged: WindowController.applyWindowCorners(root)

    // 「导入模型」：把选中的文件转发给中央 3D 视口（Viewport 再转发到 GraphicsViewport）
    function importFile(url) {
        mainViewport.importFile(url)
    }

    // 「导出模型」：把保存路径转发给中央 3D 视口写文件
    function exportFile(url) {
        mainViewport.exportFile(url)
    }

    // 主内容区：用显式锚点纵向堆叠（而非 ColumnLayout）。中央视口区直接锚在 ribbon 底部，
    // ribbon 收起/展开的高度动画会同步带动 3D 视口与项目树平滑向上填满 / 向下回缩，
    // 避免 ColumnLayout 重新布局时逐帧跳变（那会导致过渡时出现空隙）。
    Ribbon {
        id: mainRibbon
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        target: root
        viewport: mainViewport
    }

    StatusBar {
        id: statusBar
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        cursorCoordinates: mainViewport.cursorCoordinates
        importStatus: mainViewport.importStatus
        exportStatus: mainViewport.exportStatus
        importProgress: mainViewport.importProgress
    }

    Item {
        id: viewportArea
        anchors.top: mainRibbon.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: statusBar.top

        // 3D 视口铺满中央区域（左右通铺，右侧属性面板已移除）
        Viewport {
            id: mainViewport
            anchors.fill: parent
        }

        // 消息通知气泡：悬浮在 3D 视口顶部（ribbon 正下方），像手机推送一样弹出
        ToastLayer {
            id: toastLayer
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            height: 0
            z: 200
        }

        // 全局消息通知（NotificationManager.push 广播）→ 本窗口气泡
        Connections {
            target: NotificationManager
            function onNotify(type, title, message) { toastLayer.push(type, title, message) }
        }

        // 模型导入结果 → 按类型弹出气泡（正在导入的中间态不弹，避免刷屏）
        Connections {
            target: mainViewport
            function onImportStatusChanged() {
                var s = mainViewport.importStatus
                if (s.indexOf("失败") >= 0)
                    toastLayer.push("error", "导入失败", s.replace("导入失败：", ""))
                else if (s.indexOf("已导入") === 0)
                    toastLayer.push("success", "导入成功", s.replace("已导入：", ""))
            }
        }

        // 模型导出结果 → 按类型弹出气泡（正在导出的中间态不弹）
        Connections {
            target: mainViewport
            function onExportStatusChanged() {
                var s = mainViewport.exportStatus
                if (s.indexOf("失败") >= 0)
                    toastLayer.push("error", "导出失败", s.replace("导出失败：", ""))
                else if (s.indexOf("已导出") === 0)
                    toastLayer.push("success", "导出成功", s.replace("已导出：", ""))
            }
        }

        // 项目树：半透明悬浮在视口左侧（上下边距一致）
        ProjectPanel {
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.bottom: parent.bottom
            anchors.topMargin: 12
            anchors.leftMargin: 12
            anchors.bottomMargin: 12
            width: 260
        }
    }

    // —— 四周缩放把手（无边框窗口手动提供边缘拖拽缩放）——
    WindowResizeHandle { target: root; edges: 2;  cursorShape: Qt.SizeVerCursor;  anchors.top: parent.top;       anchors.left: parent.left;   anchors.right: parent.right;  height: 5; z: 100 }
    WindowResizeHandle { target: root; edges: 8;  cursorShape: Qt.SizeVerCursor;  anchors.bottom: parent.bottom; anchors.left: parent.left;   anchors.right: parent.right;  height: 5; z: 100 }
    WindowResizeHandle { target: root; edges: 1;  cursorShape: Qt.SizeHorCursor;  anchors.left: parent.left;     anchors.top: parent.top;      anchors.bottom: parent.bottom; width: 5;  z: 100 }
    WindowResizeHandle { target: root; edges: 4;  cursorShape: Qt.SizeHorCursor;  anchors.right: parent.right;   anchors.top: parent.top;      anchors.bottom: parent.bottom; width: 5;  z: 100 }
    WindowResizeHandle { target: root; edges: 3;  cursorShape: Qt.SizeFDiagCursor; anchors.top: parent.top;       anchors.left: parent.left;   width: 8; height: 8; z: 101 }
    WindowResizeHandle { target: root; edges: 6;  cursorShape: Qt.SizeBDiagCursor; anchors.top: parent.top;       anchors.right: parent.right;  width: 8; height: 8; z: 101 }
    WindowResizeHandle { target: root; edges: 9;  cursorShape: Qt.SizeBDiagCursor; anchors.bottom: parent.bottom; anchors.left: parent.left;   width: 8; height: 8; z: 101 }
    WindowResizeHandle { target: root; edges: 12; cursorShape: Qt.SizeFDiagCursor; anchors.bottom: parent.bottom; anchors.right: parent.right;  width: 8; height: 8; z: 101 }
}
