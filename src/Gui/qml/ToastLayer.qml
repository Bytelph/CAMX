import QtQuick

// 消息通知层：悬浮在 3D 视口顶部（ribbon 正下方），像手机推送一样自上而下叠加气泡。
// push(type, title, message) 添加一条；type: "info" / "success" / "warning" / "error"。
// 用 ListView 的 displaced 过渡让「某条消失后其余气泡平滑上滑补位」可靠生效。
Item {
    id: toastLayer

    function push(type, title, message) {
        toastModel.append({
            key: Date.now().toString() + "_" + Math.floor(Math.random() * 1000000),
            type: type, title: title, message: message
        })
    }

    function dismiss(key) {
        for (var i = 0; i < toastModel.count; ++i) {
            if (toastModel.get(i).key === key) {
                toastModel.remove(i)
                return
            }
        }
    }

    ListModel { id: toastModel }

    ListView {
        id: stack
        anchors.top: parent.top
        anchors.topMargin: 10
        anchors.horizontalCenter: parent.horizontalCenter
        width: 380
        height: 500
        interactive: false
        clip: false
        spacing: 6

        model: toastModel
        delegate: Toast {
            toastKey: model.key
            toastType: model.type
            title: model.title
            message: model.message
            onExpired: toastLayer.dismiss(toastKey)
        }

        // 某条气泡被移除后，其下方的气泡平滑上滑补位
        displaced: Transition {
            NumberAnimation { properties: "y"; duration: 220; easing.type: Easing.OutCubic }
        }
    }
}
