#pragma once

#include <QQuickFramebufferObject>
#include <QPointF>
#include <QString>
#include <QUrl>
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
    // 导入结果消息（渲染线程解析文件后经 QueuedConnection 写回，供状态栏显示）
    Q_PROPERTY(QString importStatus READ importStatus WRITE setImportStatus NOTIFY importStatusChanged)
    // 导出结果消息（渲染线程写文件后经 QueuedConnection 写回，供状态栏显示）
    Q_PROPERTY(QString exportStatus READ exportStatus WRITE setExportStatus NOTIFY exportStatusChanged)
    // 导入进度（-1 = 空闲/隐藏；0..1 = 进行中），由渲染线程读取期间经 QueuedConnection 写回，
    // 供状态栏右侧进度条显示。
    Q_PROPERTY(qreal importProgress READ importProgress WRITE setImportProgress NOTIFY importProgressChanged)
    // 当前模型显示模式（0..7，对应 Mayo::DisplayMode 枚举），由渲染线程在导入/切换后写回，
    // 供 QML 显示模式下拉框回显。
    Q_PROPERTY(int displayMode READ displayMode NOTIFY displayModeChanged)
    // 当前模型是否为网格型（STL/OBJ/PLY 读入后为 MeshVS_Mesh，否则为 AIS_Shape）。
    Q_PROPERTY(bool isMeshModel READ isMeshModel NOTIFY isMeshModelChanged)
    // 当前拾取模式（0..4，对应 PickMode 枚举）：无 / 体 / 面 / 边 / 点。
    Q_PROPERTY(int pickMode READ pickMode NOTIFY pickModeChanged)
public:
    // 显示模式枚举（与 Mayo::DisplayMode 数值一一对应）
    enum DisplayMode {
        ShapeWireframe = 0,
        ShapeHiddenLineRemoval,
        ShapeShaded,
        ShapeShadedWithEdges,
        MeshWireframe,
        MeshShaded,
        MeshSolid,
        MeshShrink
    };
    Q_ENUM(DisplayMode)

    // 拾取模式（视图工具栏「拾取」下拉框）：无 / 体 / 面 / 边 / 点。
    enum PickMode {
        PickNone = 0,   // 无（默认：左键旋转，不拾取）
        PickBody,       // 体
        PickFace,       // 面
        PickEdge,       // 边
        PickPoint       // 点
    };
    Q_ENUM(PickMode)

    explicit GraphicsViewport(QQuickItem* parent = nullptr);
    ~GraphicsViewport() override;

    Renderer* createRenderer() const override;

    // 由渲染线程经 QMetaObject::invokeMethod(QueuedConnection) 调用：在 GUI 线程上启动/重启
    // 相机动画的 QVariantAnimation。帧节奏由 GUI 线程的动画定时器驱动（每个 valueChanged 触发
    // update()），渲染线程只负责按进度插值相机 —— 避免在渲染线程里直接调用 update() 造成卡死。
    void startCameraAnimation();

    QString cursorCoordinates() const { return m_cursorCoordinates; }
    void setCursorCoordinates(const QString& coords);

    QString importStatus() const { return m_importStatus; }
    void setImportStatus(const QString& status);

    QString exportStatus() const { return m_exportStatus; }
    void setExportStatus(const QString& status);

    qreal importProgress() const { return m_importProgress; }
    void setImportProgress(qreal progress);

    int displayMode() const { return m_displayMode; }
    bool isMeshModel() const { return m_isMeshModel; }
    int pickMode() const { return m_pickMode; }

    // 由渲染线程经 QueuedConnection 调用：写回当前生效的显示模式/模型类型，供 QML 回显。
    void updateDisplayMode(int mode);
    void updateIsMeshModel(bool mesh);
    void updatePickMode(int mode);

    // 导入模型（QML「导入模型」调用）：把文件路径交给渲染线程解析并替换当前显示几何。
    // 支持 STEP/IGES/BRep/STL/OBJ/PLY/VRML（按扩展名识别）。
    Q_INVOKABLE void importFile(const QUrl& url);

    // 导出模型（QML「导出模型」调用）：把当前显示几何交给渲染线程写入指定格式文件。
    Q_INVOKABLE void exportFile(const QUrl& url);

    // 切换显示模式（QML 显示模式下拉框调用）：0..7 对应 DisplayMode 枚举。
    Q_INVOKABLE void setDisplayMode(int mode);

    // 切换拾取模式（QML 拾取下拉框调用）：0..4 对应 PickMode 枚举。
    Q_INVOKABLE void setPickMode(int mode);

signals:
    void cursorCoordinatesChanged();
    void importStatusChanged();
    void exportStatusChanged();
    void importProgressChanged();
    void displayModeChanged();
    void isMeshModelChanged();
    void pickModeChanged();

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
        QString importPath;              // 待导入文件的本地绝对路径（GUI 线程写入，渲染线程消费后清空）
        QString exportPath;              // 待导出文件的本地绝对路径（GUI 线程写入，渲染线程消费后清空）
        int pendingDisplayMode = -1;     // 待切换的显示模式（0..7，GUI 线程写入，渲染线程消费后置 -1）
        int pendingPickMode = -1;        // 待切换的拾取模式（0..4，GUI 线程写入，渲染线程消费后置 -1）
    };

    std::unique_ptr<Input> m_input;
    QVariantAnimation m_cameraAnim;      // 相机过渡动画（GUI 线程驱动，缓动 OutExpo，时长 1s）
    QString m_cursorCoordinates;         // 鼠标指向的 3D 坐标文本（"X: .. Y: .. Z: .."），空串表示无命中
    QString m_importStatus;              // 最近一次模型导入的结果消息（"已导入：xxx" / "导入失败：…"）
    QString m_exportStatus;              // 最近一次模型导出的结果消息（"已导出：xxx" / "导出失败：…"）
    qreal m_importProgress = -1.0;       // 模型导入进度：-1 = 空闲/隐藏，0..1 = 进行中
    int m_displayMode = 0;               // 当前显示模式（0..7，对应 DisplayMode 枚举，默认线框）
    bool m_isMeshModel = false;          // 当前模型是否为网格型（MeshVS_Mesh）
    int m_pickMode = 0;                  // 当前拾取模式（0..4，对应 PickMode 枚举，默认无）
};
