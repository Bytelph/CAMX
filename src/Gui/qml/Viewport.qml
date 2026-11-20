import QtQuick
import CAMX.Theme 1.0

// 中央 3D 视口：OCCT 可用时加载原生 AIS 视口，否则退回 Canvas 占位
Rectangle {
    id: viewport
    color: "#181b20"

    // 鼠标指向的 3D 坐标（底层 GraphicsViewport 悬停拾取后经 QueuedConnection 写回），
    // 经 Loader 透传给状态栏。空串表示鼠标未命中模型。
    property string cursorCoordinates: ""

    // 最近一次模型导入的结果消息（"已导入：xxx" / "导入失败：…"），透传给状态栏。
    property string importStatus: ""

    // 最近一次模型导出的结果消息（"已导出：xxx" / "导出失败：…"），透传给状态栏。
    property string exportStatus: ""

    // 模型导入进度（-1 = 隐藏，0..1 = 进行中），透传给状态栏进度条。
    property real importProgress: -1

    // 当前显示模式（0..7，对应 Mayo::DisplayMode），由底层 GraphicsViewport 写回，供显示模式下拉框回显。
    property int displayMode: 0

    // 当前模型是否为网格型（STL/OBJ/PLY 为 true，STEP/IGES/BRep 为 false）。
    property bool isMeshModel: false

    // 当前拾取模式（0..4，对应 PickMode 枚举），由底层 GraphicsViewport 写回，供拾取下拉框回显。
    property int pickMode: 0

    // 把「导入模型」请求转发给底层 OCCT 视口（占位 Canvas 无此方法时忽略）
    function importFile(url) {
        if (loader.item && loader.item.importFile)
            loader.item.importFile(url)
    }

    // 把「导出模型」请求转发给底层 OCCT 视口
    function exportFile(url) {
        if (loader.item && loader.item.exportFile)
            loader.item.exportFile(url)
    }

    // 把「切换显示模式」请求转发给底层 OCCT 视口
    function setDisplayMode(mode) {
        if (loader.item && loader.item.setDisplayMode)
            loader.item.setDisplayMode(mode)
    }

    // 把「切换拾取模式」请求转发给底层 OCCT 视口
    function setPickMode(mode) {
        if (loader.item && loader.item.setPickMode)
            loader.item.setPickMode(mode)
    }

    Loader {
        id: loader
        anchors.fill: parent
        // occAvailable 由 main.cpp 注入；避免无 OCCT 构建下解析 CAMX.Graphics 模块失败
        sourceComponent: occAvailable ? occViewport : placeholder
    }

    Connections {
        target: loader.item
        ignoreUnknownSignals: true
        function onCursorCoordinatesChanged() {
            viewport.cursorCoordinates = loader.item ? loader.item.cursorCoordinates : ""
        }
        function onImportStatusChanged() {
            viewport.importStatus = loader.item ? loader.item.importStatus : ""
        }
        function onExportStatusChanged() {
            viewport.exportStatus = loader.item ? loader.item.exportStatus : ""
        }
        function onImportProgressChanged() {
            viewport.importProgress = loader.item ? loader.item.importProgress : -1
        }
        function onDisplayModeChanged() {
            viewport.displayMode = loader.item ? loader.item.displayMode : 0
        }
        function onIsMeshModelChanged() {
            viewport.isMeshModel = loader.item ? loader.item.isMeshModel : false
        }
        function onPickModeChanged() {
            viewport.pickMode = loader.item ? loader.item.pickMode : 0
        }
    }

    Component {
        id: occViewport
        OccViewport { anchors.fill: parent }
    }

    Component {
        id: placeholder
        Canvas {
            id: canvas
            anchors.fill: parent
            onWidthChanged: requestPaint()
            onHeightChanged: requestPaint()

            onPaint: {
                var ctx = getContext("2d")
                var w = canvas.width
                var h = canvas.height

                // 深色渐变背景
                var g = ctx.createLinearGradient(0, 0, 0, h)
                g.addColorStop(0.0, "#2b3038")
                g.addColorStop(0.6, "#20242a")
                g.addColorStop(1.0, "#181b20")
                ctx.fillStyle = g
                ctx.fillRect(0, 0, w, h)

                // 网格
                ctx.strokeStyle = "#3a4048"
                ctx.lineWidth = 1
                ctx.beginPath()
                var step = 40
                for (var x = 0; x < w; x += step) { ctx.moveTo(x + 0.5, 0); ctx.lineTo(x + 0.5, h) }
                for (var y = 0; y < h; y += step) { ctx.moveTo(0, y + 0.5); ctx.lineTo(w, y + 0.5) }
                ctx.stroke()

                // 中心坐标轴（X 红 / Y 绿）
                var cx = w / 2
                var cy = h / 2
                ctx.lineWidth = 2
                ctx.strokeStyle = "#d04a4a"
                ctx.beginPath(); ctx.moveTo(cx - 40, cy); ctx.lineTo(cx + 40, cy); ctx.stroke()
                ctx.strokeStyle = "#4ab04a"
                ctx.beginPath(); ctx.moveTo(cx, cy - 40); ctx.lineTo(cx, cy + 40); ctx.stroke()

                // 标签
                ctx.fillStyle = "#ffffff"
                ctx.font = "12px 'Microsoft YaHei', sans-serif"
                ctx.fillText("X", cx + 44, cy + 4)
                ctx.fillText("Y", cx + 4, cy - 44)

                // 底部提示
                ctx.fillStyle = "#888888"
                ctx.font = "11px 'Microsoft YaHei', sans-serif"
                ctx.fillText("视口占位 — 后续接入 OCCT AIS 渲染", 12, h - 12)
            }
        }
    }

    // 右上角视图立方体 + 坐标系由 OCCT AIS_ViewCube 在 3D 视口内渲染，
    // 不再使用 QML 占位组件。
}
