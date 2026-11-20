pragma Singleton
import QtQuick
import QtQuick.Dialogs

// 窗口管理器（QML 单例，CAMX.WindowManager.WindowManager）：
// 在同一进程内动态创建多个 CAMX 文档窗口，避免「新建项目」冷启动一个新进程（加载 Qt/OCCT
// DLL + 重新初始化 OpenGL/AIS），新窗口近乎即时弹出。新窗口在原窗口位置基础上级联错开。
QtObject {
    id: manager

    property int cascadeOffset: 28
    property var windows: []
    property var importTarget: null   // 发起「导入模型」的窗口（onAccepted 时回传选中文件）
    property var exportTarget: null   // 发起「导出模型」的窗口（onAccepted 时回传保存路径）

    // QtObject 没有默认属性，组件须以「属性绑定」形式声明，否则会被当作子对象赋值而报错
    property Component windowComponent: CamxWindow { }

    // 「导入模型」文件选择对话框（STEP/IGES/BRep/STL/PLY/VRML/OBJ）。
    // 选中文件后回传给发起窗口的 3D 视口，由 GraphicsViewport 在渲染线程解析几何。
    property FileDialog fileDialog: FileDialog {
        title: "导入模型"
        fileMode: FileDialog.OpenFile
        nameFilters: [
            "所有支持格式 (*.step *.stp *.iges *.igs *.brep *.stl *.ply *.wrl *.vrml *.obj)",
            "STEP (*.step *.stp)",
            "IGES (*.iges *.igs)",
            "BRep (*.brep)",
            "STL (*.stl)",
            "PLY (*.ply)",
            "VRML (*.wrl *.vrml)",
            "OBJ (*.obj)"
        ]
        onAccepted: {
            // 把选中的文件交给发起请求的窗口的 3D 视口导入
            if (manager.importTarget && manager.importTarget.importFile)
                manager.importTarget.importFile(selectedFile)
        }
    }

    // 「导出模型」文件保存对话框：把当前几何写入用户指定格式文件。
    property FileDialog exportDialog: FileDialog {
        title: "导出模型"
        fileMode: FileDialog.SaveFile
        nameFilters: [
            "STEP (*.step)",
            "IGES (*.iges)",
            "BRep (*.brep)",
            "STL (*.stl)",
            "OBJ (*.obj)",
            "PLY (*.ply)",
            "VRML (*.wrl)"
        ]
        onAccepted: {
            // 用户可能不输入扩展名：按所选过滤器补全，否则 ShapeWriter 无法从扩展名识别格式
            var path = manager.ensureExtension(selectedFile, selectedNameFilter)
            if (manager.exportTarget && manager.exportTarget.exportFile)
                manager.exportTarget.exportFile(path)
        }
    }

    // 打开「导入模型」对话框；window 用于将原生对话框与对应窗口关联（模态/居中），
    // 并在选中文件后回传给该窗口的 3D 视口。
    function importModel(window) {
        importTarget = window
        if (window)
            fileDialog.parentWindow = window
        fileDialog.open()
    }

    // 打开「导出模型」对话框，选中保存路径后回传给该窗口的 3D 视口写文件。
    function exportModel(window) {
        exportTarget = window
        if (window)
            exportDialog.parentWindow = window
        exportDialog.open()
    }

    // 若 selectedFile 缺少扩展名，按 nameFilter（形如 "STEP (*.step)"）补全对应的首个扩展名。
    function ensureExtension(file, nameFilter) {
        var path = file.toString()
        // 已含扩展名则原样返回
        if (/\.\w+$/.test(path))
            return file

        var m = /\(\*\.([\w]+)/.exec(nameFilter)
        if (!m)
            return file
        return path + "." + m[1]
    }

    function openNewWindow() {
        var win = windowComponent.createObject(null)
        if (!win)
            return null

        // 级联错开：相对上一个窗口右下偏移，避免与原窗口完全重叠
        if (windows.length > 0) {
            var last = windows[windows.length - 1]
            win.x = last.x + manager.cascadeOffset
            win.y = last.y + manager.cascadeOffset
        }

        // 窗口关闭后从列表移除，释放引用（最后一个窗口关闭时由 QGuiApplication 自动退出）
        win.closing.connect(function() {
            var idx = windows.indexOf(win)
            if (idx >= 0)
                windows.splice(idx, 1)
        })

        windows.push(win)
        win.show()
        return win
    }
}
