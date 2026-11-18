import QtQuick
import CXCAM.WindowManager 1.0

// 应用入口：本身不是窗口，只是启动时创建第一个 CXCAM 文档窗口。
// 后续「新建项目」由 RibbonGroup 调用 WindowManager.openNewWindow() 在同一进程内再开窗口。
// 应用入口：本身不是窗口，只是启动时创建第一个 CXCAM 文档窗口。
// 后续「新建项目」由 RibbonGroup 调用 WindowManager.openNewWindow() 在同一进程内再开窗口。
QtObject {
    Component.onCompleted: WindowManager.openNewWindow()
}
