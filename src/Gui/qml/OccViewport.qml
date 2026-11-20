import QtQuick
import CAMX.Graphics 1.0

// 原生 OCCT AIS 视口（QQuickFramebufferObject 承载）
// 仅在 CAMX_WITH_OCCT=ON 时由 Viewport.qml 动态加载，避免无 OCCT 构建下解析失败
GraphicsViewport {
    anchors.fill: parent
}
