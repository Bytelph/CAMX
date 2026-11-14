#pragma once

#include <QQuickFramebufferObject>
#include <QPointF>
#include <QString>
#include <QVariantAnimation>

#include <memory>

class QMouseEvent;
class QWheelEvent;
class QHoverEvent;
class GraphicsViewportRenderer;

// 中央 3D 视口：以 QQuickFramebufferObject 承载 OpenCASCADE AIS 渲染
// OCCT 的驱动 / 场景 / 视图等对象全部封装在 GraphicsViewportRenderer（.cpp）中，
// 本头文件保持 Qt 友好、不引入 OCCT 头。
class GraphicsViewport : public QQuickFramebufferObject {
    Q_OBJECT
    // 鼠标当前指向的 3D 世界坐标（悬停在模型上时更新，空白处清空），供状态栏显示。
    // 由渲染线程拾取后经 QueuedConnection 写回 GUI 线程（见 setCursorCoordinates）。
    Q_PROPERTY(QString cursorCoordinates READ cursorCoordinates WRITE setCursorCoordinates NOTIFY cursorCoordinatesChanged)
public:
    explicit GraphicsViewport(QQuickItem* parent = nullptr);
    ~GraphicsViewport() override;

    Renderer* createRenderer() const override;

    // 由渲染线程经 QMetaObject::invokeMethod(QueuedConnection) 调用：在 GUI 线程上启动/重启
    // 相机动画的 QVariantAnimation。帧节奏由 GUI 线程的动画定时器驱动（每个 valueChanged 触发
    // update()），渲染线程只负责按进度插值相机 —— 避免在渲染线程里直接调用 update() 造成卡死。
    void startCameraAnimation();

    QString cursorCoordinates() const { return m_cursorCoordinates; }
    void setCursorCoordinates(const QString& coords);

signals:
    void cursorCoordinatesChanged();

protected:
    void mousePressEvent(QMouseEvent* event) override;
    void mouseMoveEvent(QMouseEvent* event) override;
    void mouseReleaseEvent(QMouseEvent* event) override;
    void hoverEnterEvent(QHoverEvent* event) override;
    void hoverMoveEvent(QHoverEvent* event) override;
    void hoverLeaveEvent(QHoverEvent* event) override;
    void wheelEvent(QWheelEvent* event) override;

private:
    friend class GraphicsViewportRenderer;

    // GUI 线程累积的输入状态，renderer 在 synchronize() 中读取
    struct Input {
        Qt::MouseButtons buttons;
        QPointF pos;
        int wheelDelta = 0;
        qreal devicePixelRatio = 1.0;   // 鼠标坐标（逻辑像素）→ 设备像素的换算系数
        bool hoverActive = false;        // 鼠标是否位于视口内（用于悬停高亮 / 离开时清除）
        double cameraAnimProgress = 0.0; // 相机动画进度 0..1（已含 OutExpo 缓动），由 GUI 线程动画写入
    };

    std::unique_ptr<Input> m_input;
    QVariantAnimation m_cameraAnim;      // 相机过渡动画（GUI 线程驱动，缓动 OutExpo，时长 1s）
    QString m_cursorCoordinates;         // 鼠标指向的 3D 坐标文本（"X: .. Y: .. Z: .."），空串表示无命中
};
