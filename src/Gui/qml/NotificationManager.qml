pragma Singleton
import QtQuick

// 消息通知管理器（QML 单例，CXCAM.NotificationManager.NotificationManager）：
// 统一的消息通知入口。notify(type, title, message) 广播给所有已打开的 CXCAM 窗口，
// 各窗口顶部 ToastLayer 以「手机推送」式气泡展示。
// type: "info" / "success" / "warning" / "error"
QtObject {
    id: manager

    signal notify(string type, string title, string message)

    function push(type, title, message) {
        manager.notify(type, title, message)
    }
}
