#include "Gui/GraphicsViewport.h"
#include "Gui/qtopengl_utils.h"

#include "Graphics/base/occ_handle.h"
#include "Graphics/graphics_create_driver.h"
#include "Graphics/graphics_display_modes.h"
#include "Graphics/graphics_scene.h"
#include "Graphics/graphics_shape_reader.h"
#include "Graphics/graphics_shape_writer.h"
#include "Graphics/graphics_utils.h"
#include "Graphics/opengl_utils.h"

#include <AIS_DisplayMode.hxx>
#include <AIS_Shape.hxx>
#include <AIS_Trihedron.hxx>
#include <AIS_ViewCube.hxx>
#include <Aspect_GridDrawMode.hxx>
#include <Aspect_GridType.hxx>
#include <Aspect_NeutralWindow.hxx>
#include <Aspect_TypeOfLine.hxx>
#include <Aspect_TypeOfTriedronPosition.hxx>
#include <Aspect_TypeOfHighlightMethod.hxx>
#include <Bnd_Box.hxx>
#include <BRepBndLib.hxx>
#include <BRepBuilderAPI_MakeFace.hxx>
#include <Graphic3d_AspectFillArea3d.hxx>
#include <Graphic3d_Camera.hxx>
#include <Graphic3d_CLight.hxx>
#include <Graphic3d_MaterialAspect.hxx>
#include <Graphic3d_NameOfMaterial.hxx>
#include <Graphic3d_RenderingParams.hxx>
#include <Graphic3d_TransformPers.hxx>
#include <Graphic3d_TransModeFlags.hxx>
#include <Graphic3d_TypeOfLightSource.hxx>
#include <Graphic3d_ZLayerId.hxx>
#include <Geom_Axis2Placement.hxx>
#include <gp.hxx>
#include <gp_Pln.hxx>
#include <NCollection_Vec2.hxx>
#include <MeshVS_Mesh.hxx>
#include <MeshVS_SelectionModeFlags.hxx>
#include <OpenGl_Context.hxx>
#include <OpenGl_GraphicDriver.hxx>
#include <Prs3d_DatumAspect.hxx>
#include <Prs3d_Drawer.hxx>
#include <Prs3d_LineAspect.hxx>
#include <Prs3d_ShadingAspect.hxx>
#include <Prs3d_TypeOfHighlight.hxx>
#include <Quantity_Color.hxx>
#include <StdSelect_ViewerSelector3d.hxx>
#include <TDocStd_Document.hxx>
#include <TopoDS_Face.hxx>
#include <V3d_TypeOfOrientation.hxx>
#include <V3d_View.hxx>
#include <V3d_Viewer.hxx>

#include <QEasingCurve>
#include <QFileInfo>
#include <QHoverEvent>
#include <QImage>
#include <QMetaObject>
#include <QMouseEvent>
#include <QOpenGLContext>
#include <QOpenGLFramebufferObject>
#include <QOpenGLFunctions>
#include <QQuickWindow>
#include <QSurfaceFormat>
#include <QWheelEvent>

#include <algorithm>
#include <cmath>
#include <exception>
#include <mutex>
#include <thread>
#include <vector>

namespace {

// Qt Quick 场景图负责 FBO 与 buffer swap，故 OCCT 驱动关闭自有 swap / system buffer
Mayo::OccHandle<Graphic3d_GraphicDriver> createQmlGraphicsDriver()
{
    auto driver = Mayo::makeOccHandle<OpenGl_GraphicDriver>(
        Mayo::GraphicsUtils::AspectDisplayConnection_create(), false /*dontInit*/
    );
    driver->ChangeOptions().buffersNoSwap = true;
    driver->ChangeOptions().buffersOpaqueAlpha = true;
    driver->ChangeOptions().useSystemBuffer = false;

    // 匹配 Qt 默认的 CompatibilityProfile GL 上下文（否则 OCCT 按 Core Profile 处理，
    // 产生 GL_INVALID_ENUM 并导致后续 FBO 包装失败）
    Mayo::QtOpenGlUtils::setCapsFromSurfaceFormat(
        driver->ChangeOptions(), QSurfaceFormat::defaultFormat());

    const static bool isGpuAccel = Mayo::OpenGlUtils::isHardwareAccelerationAvailable();
    driver->ChangeOptions().contextNoAccel = !isGpuAccel;

    return driver;
}

// 把 QML 拾取模式映射为 AIS/MeshVS 的选择模式。
// AIS_Shape（实体）：AIS_Shape::SelectionMode(TopAbs_*)（0=体/整形状，4=面，2=边，1=点）。
// MeshVS_Mesh（STL 等网格）：MeshVS_SMF_Mesh/Node/Link/Face（体/点/边/面）。
// 返回 -1 表示该对象不支持该拾取模式（此时不激活任何选择模式）。
int pickSelectionMode(const Mayo::GraphicsObjectPtr& object, GraphicsViewport::PickMode pick)
{
    const auto mesh = Mayo::OccHandle<MeshVS_Mesh>::DownCast(object);
    if (!mesh.IsNull()) {
        switch (pick) {
        case GraphicsViewport::PickBody:  return int(MeshVS_SMF_Mesh);
        case GraphicsViewport::PickFace:  return int(MeshVS_SMF_Face);
        case GraphicsViewport::PickEdge:  return int(MeshVS_SMF_Link);
        case GraphicsViewport::PickPoint: return int(MeshVS_SMF_Node);
        default:                          return -1;
        }
    }

    const auto shape = Mayo::OccHandle<AIS_Shape>::DownCast(object);
    if (!shape.IsNull()) {
        switch (pick) {
        case GraphicsViewport::PickBody:  return AIS_Shape::SelectionMode(TopAbs_SHAPE);
        case GraphicsViewport::PickFace:  return AIS_Shape::SelectionMode(TopAbs_FACE);
        case GraphicsViewport::PickEdge:  return AIS_Shape::SelectionMode(TopAbs_EDGE);
        case GraphicsViewport::PickPoint: return AIS_Shape::SelectionMode(TopAbs_VERTEX);
        default:                          return -1;
        }
    }

    return -1;
}

} // namespace

// ---------------------------------------------------------------------------
// Renderer
// ---------------------------------------------------------------------------

class GraphicsViewportRenderer : public QQuickFramebufferObject::Renderer {
public:
    QOpenGLFramebufferObject* createFramebufferObject(const QSize& size) override
    {
        QOpenGLFramebufferObjectFormat fmt;
        fmt.setAttachment(QOpenGLFramebufferObject::CombinedDepthStencil);
        m_size = size;
        m_fbo = new QOpenGLFramebufferObject(size, fmt);
        return m_fbo;
    }

    ~GraphicsViewportRenderer() override
    {
        // 回收后台读取线程，避免其在本对象析构后继续访问成员
        if (m_importThread.joinable())
            m_importThread.join();
    }

    void synchronize(QQuickFramebufferObject* item) override
    {
        auto* viewport = static_cast<GraphicsViewport*>(item);
        m_viewport = viewport;
        m_input = *viewport->m_input;
        // Qt 鼠标事件是逻辑像素，而 OCCT 视口/FBO 用设备像素（高 DPI 下相差 devicePixelRatio 倍），
        // 这里读取当前 DPR 供 render() 中的坐标换算使用。
        if (viewport->window())
            m_input.devicePixelRatio = viewport->window()->devicePixelRatio();
        viewport->m_input->wheelDelta = 0;   // 消费累计的滚轮增量
        viewport->m_input->importPath.clear();   // 消费待导入请求
        viewport->m_input->exportPath.clear();   // 消费待导出请求
        viewport->m_input->pendingDisplayMode = -1;   // 消费待切换显示模式请求
        viewport->m_input->pendingPickMode = -1;      // 消费待切换拾取模式请求
        viewport->m_input->pendingGridVisible = -1;   // 消费待切换网格显示请求
        viewport->m_input->pendingOriginVisible = -1; // 消费待切换坐标系显示请求
    }

    void render() override
    {
        if (m_initFailed)
            return;

        if (!m_scene)
            this->initOcct();

        if (m_view.IsNull())
            return;

        // 处理「导入模型」请求：把文件读取放到后台线程执行（渲染线程不阻塞），
        // 这样状态栏进度条（由场景图渲染线程绘制）才能在读取期间持续刷新。
        if (!m_input.importPath.isEmpty()) {
            this->startImport(m_input.importPath);
            m_input.importPath.clear();
        }

        // 若后台读取已完成，在渲染线程应用解析结果（替换显示几何 / 写回状态栏）
        this->applyImportResultIfReady();

        // 处理「导出模型」请求：在渲染线程把当前几何写入指定文件
        if (!m_input.exportPath.isEmpty()) {
            this->exportFile(m_input.exportPath);
            m_input.exportPath.clear();
        }

        // 处理「切换显示模式」请求（QML 下拉框写入，渲染线程应用后回写生效模式）
        if (m_input.pendingDisplayMode >= 0) {
            this->applyDisplayModeInternal(m_input.pendingDisplayMode);
            m_input.pendingDisplayMode = -1;
        }

        // 处理「切换拾取模式」请求（QML 下拉框写入，渲染线程应用后回写生效模式）
        if (m_input.pendingPickMode >= 0) {
            this->applyPickModeInternal(m_input.pendingPickMode);
            m_input.pendingPickMode = -1;
        }

        // 处理「显示」开关（网格 / 坐标系）请求（QML 写入，渲染线程应用后回写生效状态）
        if (m_input.pendingGridVisible >= 0) {
            this->applyGridVisibility(m_input.pendingGridVisible != 0);
            m_input.pendingGridVisible = -1;
        }
        if (m_input.pendingOriginVisible >= 0) {
            this->applyOriginVisibility(m_input.pendingOriginVisible != 0);
            m_input.pendingOriginVisible = -1;
        }

        this->applyNavigation();

        // Qt 6 的 QQuickFramebufferObject 不会在 render() 前自动绑定 FBO（GL_FRAMEBUFFER_BINDING==0），
        // OCCT 的 initializeGlFramebufferObject 依赖当前已绑定的 FBO，因此这里显式绑定。
        if (m_fbo)
            m_fbo->bind();

        Mayo::QtOpenGlUtils::initializeGlFramebufferObject(m_view);
        Mayo::QtOpenGlUtils::resetGlStateBeforeOcct(m_view);

        // 视图切换相机动画（Mayo 式：Graphic3d_CameraLerp + OutExpo 缓动），
        // 每帧推进一步并触发连续重绘，保证过渡丝滑。
        if (m_animating)
            this->advanceCameraAnimation();
        m_view->Redraw();

        // TEMP 诊断：导入模型后截取一帧，用于定位「着色带边」边线虚线问题。
        // camx_fbo_dump.png = OCCT 实际渲染进 FBO 的画面（即 Qt Quick 采样显示的纹理）；
        // camx_occt_dump.png = 同一 GL 上下文下 OCCT 自己的离屏渲染，用于对比二者是否一致。
        if (m_debugDumpFrame) {
            m_debugDumpFrame = false;
            if (m_fbo) {
                const QImage img = m_fbo->toImage();
                img.save(QStringLiteral("C:/Users/BYTELPH/Desktop/CAMX/build/camx_fbo_dump.png"));
            }
            m_debugDumpOcct = true;
        }

        Mayo::QtOpenGlUtils::resetGlStateAfterOcct(m_view);

        if (m_fbo)
            m_fbo->release();

        if (m_debugDumpOcct) {
            m_debugDumpOcct = false;
            if (!m_view.IsNull())
                m_view->Dump("C:/Users/BYTELPH/Desktop/CAMX/build/camx_occt_dump.png");
        }

        m_renderedOnce = true;
    }

private:
    void initOcct()
    {
        Mayo::setFunctionCreateGraphicsDriver(&createQmlGraphicsDriver);

        m_scene = std::make_unique<Mayo::GraphicsScene>();
        m_view = m_scene->createV3dView();

        // 用当前（场景图）GL 上下文包装 OCCT 视口
        if (!Mayo::OpenGlUtils::initializeGlWindow(
                m_view,
                static_cast<Aspect_Drawable>(0),
                NCollection_Vec2<int>(m_size.width(), m_size.height()),
                1.0))
        {
            m_initFailed = true;
            return;
        }

        // 3D 视口背景：淡灰色（#f3f3f3），与功能区第二/三行的背景一致。
        // OCCT 把背景色当作线性值、显示时再做 sRGB 编码（会变亮），故这里按 sRGB→线性反算：
        // sRGB #f3 (243/255=0.9529) → 线性 0.8963。
        m_view->SetBackgroundColor(
            Quantity_Color(0.8963f, 0.8963f, 0.8963f, Quantity_TOC_RGB));

        // 右上角视图立方体 + 坐标轴（参考 Mayo，使用 OCCT AIS_ViewCube）
        this->addViewCube();

        // 原点坐标系（参考 Mayo 的原点坐标轴 AIS_Trihedron）：X 红 / Y 绿 / Z 蓝的着色三轴
        this->addOriginTrihedron();

        // 拾取高亮样式（悬停 / 选中均为青色）
        this->configureHighlightStyles();

        m_view->MustBeResized();
        m_view->Invalidate();
    }

    // 配置拾取高亮样式（参考 Mayo：用 COLOR 着色高亮，而非 OCCT 默认的 BOUNDBOX 包络框）。
    // 按拾取对象类型区分：
    //   · 体（整对象，走 Selected/Dynamic）：着色面（青色）+ 原色边（黑，与对象自身边色一致）；
    //   · 面（子形状，走 LocalSelected/LocalDynamic）：显示「面」，青色 —— 着色方式填充面片。
    // OCCT 默认的 LocalDynamic 样式在 Topmost 层且深度独立（无视遮挡画到最前面，把悬停面片
    // 顶到最前遮挡后面的几何）；这里统一改成 UNKNOWN（与对象同层、正常深度），取消「放在最前面」。
    void configureHighlightStyles()
    {
        // 体（整对象）高亮：整对象走 PrsMgr_PresentationManager::Color → Graphic3d_Structure::Highlight
        // 的「均匀重着色」路径 —— 边与面都取高亮样式的 ColorRGBA()（即 SetColor 设置的基本色）。
        // 若只用 SetColor(青)，边会被一起染成青色。参考 Mayo 的做法：用 SetBasicFillAreaAspect 给
        // 「面」单独指定填充材质（OpenGl_Context::SetShadingMaterial 里，存在 BasicFillAreaAspect 时
        // 用它的材质渲染面，不再用 ColorRGBA 重着色面），同时把基本色 SetColor(黑) 让边保持黑色。
        const auto configureBodyStyle = [this](Prs3d_TypeOfHighlight style) {
            const auto& drawer = m_scene->drawerHighlight(style);
            if (drawer.IsNull())
                return;

            // 以默认 shading aspect 为起点构造填充面外观（继承对象自身的材质/光照等设置）
            auto fillArea = Mayo::makeOccHandle<Graphic3d_AspectFillArea3d>();
            const auto& defaultShadingAspect = m_scene->drawerDefault()->ShadingAspect();
            if (!defaultShadingAspect.IsNull() && !defaultShadingAspect->Aspect().IsNull())
                *fillArea = *defaultShadingAspect->Aspect();

            const Quantity_Color cyan(0.0f, 1.0f, 1.0f, Quantity_TOC_RGB);   // 面内部：青色
            fillArea->SetInteriorColor(cyan);
            Graphic3d_MaterialAspect fillMaterial(Graphic3d_NOM_PLASTER);
            fillMaterial.SetColor(cyan);
            fillArea->SetFrontMaterial(fillMaterial);
            fillArea->SetBackMaterial(fillMaterial);

            drawer->SetColor(Quantity_Color(Quantity_NOC_BLACK));   // 边：黑色（EdgeColor()→ColorRGBA）
            drawer->SetDisplayMode(AIS_Shaded);
            drawer->SetBasicFillAreaAspect(fillArea);
        };

        // 面（子形状）高亮：子形状走 StdSelect_BRepOwner::HilightWithColor → StdPrs_ShadedShape 重算
        // 路径，尊重 SetColor / SetDisplayMode / SetZLayer / SetFaceBoundaryDraw，故用原有方式即可。
        const auto configureFaceStyle = [this](Prs3d_TypeOfHighlight style) {
            const auto& drawer = m_scene->drawerHighlight(style);
            if (drawer.IsNull())
                return;
            drawer->SetMethod(Aspect_TOHM_COLOR);
            drawer->SetDisplayMode(AIS_Shaded);
            drawer->SetColor(Quantity_Color(0.0f, 1.0f, 1.0f, Quantity_TOC_RGB));
            drawer->SetZLayer(Graphic3d_ZLayerId_UNKNOWN);
            drawer->SetFaceBoundaryDraw(false);
        };

        // 体（整对象）：着色面（青色）+ 原色边（黑） —— 悬停 Dynamic / 选中 Selected
        configureBodyStyle(Prs3d_TypeOfHighlight_Dynamic);
        configureBodyStyle(Prs3d_TypeOfHighlight_Selected);

        // 面（子形状）：着色面、青色 —— 悬停 LocalDynamic / 选中 LocalSelected
        configureFaceStyle(Prs3d_TypeOfHighlight_LocalDynamic);
        configureFaceStyle(Prs3d_TypeOfHighlight_LocalSelected);
    }

    // 清除当前所有显示对象（并释放 XCAF 文档引用）。
    void clearCurrentObjects()
    {
        for (const auto& object : m_currentObjects) {
            if (!object.IsNull())
                m_scene->eraseObject(object);
        }
        m_currentObjects.clear();
        m_document = Mayo::OccHandle<TDocStd_Document>();
    }

    // 把单个显示对象加入场景并登记（供显示模式切换 / 清除）。
    void addDisplayObject(const Mayo::GraphicsObjectPtr& object)
    {
        if (object.IsNull())
            return;
        m_scene->addObject(object);
        m_currentObjects.push_back(object);
    }

    // 替换当前显示的几何为指定 shape：按网格型/实体型创建对应的 AIS 显示对象，
    // 应用默认显示模式，并把生效的模式/类型写回 GUI 线程供下拉框回显。
    void setShape(const TopoDS_Shape& shape)
    {
        if (shape.IsNull())
            return;

        this->clearCurrentObjects();
        m_currentShape = shape;
        m_isMesh = Mayo::isMeshShape(shape);
        this->addDisplayObject(Mayo::createDisplayObject(shape));
        if (m_currentObjects.empty()) {
            m_currentShape = TopoDS_Shape();
            return;
        }

        // 默认显示模式：实体 → 着色带边；网格 → 着色。同时清掉上一个模型遗留的 HLR 状态。
        const int defaultMode = m_isMesh
            ? int(Mayo::DisplayMode::MeshShaded)
            : int(Mayo::DisplayMode::ShapeShadedWithEdges);
        this->applyDisplayModeInternal(defaultMode);

        // 导入会重置各对象的选择模式为默认整体，这里按当前拾取模式重新激活对应选择模式
        this->applyPickSelectionModes();

        m_view->FitAll(0.1, false);
        m_view->ZFitAll();
        m_view->Invalidate();
    }

    // 替换当前显示的几何为 XCAF 文档（STEP/IGES 路径）：每个顶层自由形状建一个带颜色的
    // XCAFPrs_AISObject。文档需在本对象生命周期内保持存活（保存于 m_document）。
    void setDocument(const Mayo::OccHandle<TDocStd_Document>& document, const TopoDS_Shape& wholeShape)
    {
        if (document.IsNull())
            return;

        this->clearCurrentObjects();
        m_document = document;
        m_currentShape = wholeShape;
        m_isMesh = false;

        const std::vector<Mayo::GraphicsObjectPtr> objects = Mayo::createDisplayObjects(document);
        for (const auto& object : objects)
            this->addDisplayObject(object);
        if (m_currentObjects.empty()) {
            m_document = Mayo::OccHandle<TDocStd_Document>();
            m_currentShape = TopoDS_Shape();
            return;
        }

        const int defaultMode = int(Mayo::DisplayMode::ShapeShadedWithEdges);
        this->applyDisplayModeInternal(defaultMode);

        this->applyPickSelectionModes();

        m_view->FitAll(0.1, false);
        m_view->ZFitAll();
        m_view->Invalidate();
    }

    // 在渲染线程应用显示模式（int → Mayo::DisplayMode，按对象类型过滤不适用项），
    // 并把生效后的模式/类型写回 GUI 线程（即使选择不适用也会回写，让下拉框回弹）。
    void applyDisplayModeInternal(int mode)
    {
        if (m_currentObjects.empty())
            return;
        if (mode < 0 || mode > int(Mayo::DisplayMode::MeshShrink))
            return;

        const Mayo::DisplayMode dm = Mayo::DisplayMode(mode);
        const bool applicable = m_isMesh
            ? dm >= Mayo::DisplayMode::MeshWireframe
            : dm <= Mayo::DisplayMode::ShapeShadedWithEdges;

        if (applicable) {
            for (const auto& object : m_currentObjects)
                Mayo::applyDisplayMode(object, dm);
        }

        // 所有显示对象类型一致、模式同步，读取首个对象即可得到生效模式。
        const int effective = int(Mayo::currentDisplayMode(m_currentObjects.front()));
        this->reportDisplayMode(effective);
        this->reportIsMesh(m_isMesh);
    }

    // 在渲染线程切换拾取模式（无 / 体 / 面 / 边 / 点）：更新本渲染器的拾取模式，
    // 重新激活各显示对象的对应选择模式，并把生效模式写回 GUI 线程供下拉框回显。
    void applyPickModeInternal(int mode)
    {
        if (mode < 0 || mode > int(GraphicsViewport::PickPoint))
            return;
        m_pickMode = mode;
        this->applyPickSelectionModes();
        this->reportPickMode(m_pickMode);
    }

    // 清空所有模型对象当前激活的选择模式，再按 m_pickMode 激活对应模式（体/面/边/点）。
    // 同时清掉已固定的选中项，避免切换模式后残留上一种模式的高亮。
    void applyPickSelectionModes()
    {
        if (m_currentObjects.empty())
            return;

        for (const auto& object : m_currentObjects)
            m_scene->deactivateObjectSelection(object);
        m_scene->clearSelection();

        const GraphicsViewport::PickMode pick = GraphicsViewport::PickMode(m_pickMode);
        if (pick == GraphicsViewport::PickNone)
            return;

        for (const auto& object : m_currentObjects) {
            const int selMode = pickSelectionMode(object, pick);
            if (selMode >= 0)
                m_scene->activateObjectSelection(object, selMode);
        }
    }

    // 把生效的拾取模式跨线程写回 GUI 线程，供拾取下拉框回显
    void reportPickMode(int mode)
    {
        if (m_viewport)
            QMetaObject::invokeMethod(m_viewport, [vp = m_viewport, mode]() {
                vp->updatePickMode(mode);
            }, Qt::QueuedConnection);
    }

    // 启动后台线程读取模型文件（不阻塞渲染线程）。解析完成后由 applyImportResultIfReady()
    // 在渲染线程应用结果。支持 STEP/IGES/BRep/STL/OBJ/PLY/VRML（按扩展名自动识别）。
    void startImport(const QString& path)
    {
        // 同一时刻只允许一个导入
        {
            std::lock_guard<std::mutex> lock(m_importMutex);
            if (m_importBusy)
                return;
            m_importBusy = true;
            m_importReady = false;
        }

        // 一次性捕获工作线程所需数据（m_viewport 在渲染线程写入，拷贝出来避免数据竞争）
        GraphicsViewport* viewport = m_viewport;
        // OCCT 7.8 的窄字符文件 API 在 Windows 下期望 UTF-8（内部经 _wfopen 转 UTF-16），
        // 故用 toUtf8()；用 toLocal8Bit()（GBK）会导致含中文的路径被误判为无效 UTF-8 而打不开文件。
        const std::string utf8Path = path.toUtf8().toStdString();
        const QString fileName = QFileInfo(path).fileName();

        // 上一轮导入线程（若尚未回收）先回收
        if (m_importThread.joinable())
            m_importThread.join();

        m_importThread = std::thread([this, viewport, utf8Path, fileName]() {
            TopoDS_Shape shape;
            Mayo::OccHandle<TDocStd_Document> document;
            std::string error;
            try {
                const Mayo::ShapeFormat format = Mayo::shapeFormatFromFileName(utf8Path);
                // 进度回调运行在后台线程：经 QueuedConnection 写回 GUI 线程更新进度条
                const auto reportProgress = [viewport](double p) {
                    if (viewport)
                        QMetaObject::invokeMethod(viewport, [vp = viewport, p]() {
                            vp->setImportProgress(p);
                        }, Qt::QueuedConnection);
                };

                // STEP/IGES 走 XCAF 读取以保留模型原始颜色；其余格式走裸几何读取。
                if (format == Mayo::ShapeFormat::Step || format == Mayo::ShapeFormat::Iges) {
                    document = Mayo::ShapeReader::readXcafDocument(
                        utf8Path, format, &shape, &error, reportProgress);
                }
                else {
                    shape = Mayo::ShapeReader::read(utf8Path, format, &error, reportProgress);
                }

                // 预三角化（对齐 Mayo）：显示对象关闭自动三角化、按三角化计算等值线，
                // 这里在后台线程先算好三角剖分，避免渲染线程阻塞，并让「着色带边」的
                // 边线/轮廓线由连续三角化计算而非原始曲面上的破碎线段（虚线）。
                // 网格型（STL/OBJ/PLY）自带三角化，跳过（其面没有底层曲面，无需也不应重算）。
                if (document.IsNull()) {
                    if (!shape.IsNull() && !Mayo::isMeshShape(shape))
                        Mayo::meshShape(shape);
                }
                else {
                    Mayo::meshDocument(document);
                }
            }
            catch (const std::exception& e) {
                error = e.what();
            }
            catch (...) {
                error = "未知异常";
            }

            {
                std::lock_guard<std::mutex> lock(m_importMutex);
                m_importedShape = shape;
                m_importedDocument = document;
                m_importedError = std::move(error);
                m_importedFileName = fileName;
                m_importReady = true;
            }

            // 请求一次重绘，让渲染线程在下一次 render() 中应用结果
            if (viewport)
                QMetaObject::invokeMethod(viewport, [vp = viewport]() {
                    vp->update();
                }, Qt::QueuedConnection);
        });
    }

    // 渲染线程每帧调用：若后台读取已完成，应用结果并回写状态栏。
    void applyImportResultIfReady()
    {
        TopoDS_Shape shape;
        Mayo::OccHandle<TDocStd_Document> document;
        std::string error;
        QString fileName;
        {
            std::lock_guard<std::mutex> lock(m_importMutex);
            if (!m_importReady)
                return;
            shape = m_importedShape;
            document = m_importedDocument;
            error = m_importedError;
            fileName = m_importedFileName;
            m_importedShape = TopoDS_Shape();   // 释放句柄
            m_importedDocument = Mayo::OccHandle<TDocStd_Document>();
            m_importedError.clear();
            m_importedFileName.clear();
            m_importReady = false;
            m_importBusy = false;
        }

        // 结束后隐藏进度条（成功/失败都先归 -1；结果文字随后由 reportImportStatus 给出）
        this->reportProgress(-1.0);

        if (document.IsNull() && shape.IsNull()) {
            const QString msg = QStringLiteral("导入失败：%1（%2）")
                .arg(fileName, QString::fromStdString(error));
            qWarning("Model import failed: %s (%s)", qUtf8Printable(fileName), error.c_str());
            this->reportImportStatus(msg);
            return;
        }

        if (!document.IsNull())
            this->setDocument(document, shape);
        else
            this->setShape(shape);
        m_debugDumpFrame = true;   // TEMP 诊断：导入后下一帧截取渲染结果
        this->reportImportStatus(QStringLiteral("已导入：%1").arg(fileName));
    }

    // 导出当前几何到指定文件（渲染线程内执行），并把结果写回状态栏。
    void exportFile(const QString& path)
    {
        const QString fileName = QFileInfo(path).fileName();
        if (m_currentShape.IsNull()) {
            this->reportExportStatus(QStringLiteral("导出失败：没有可导出的模型"));
            return;
        }

        std::string error;
        const bool ok = Mayo::ShapeWriter::write(
            m_currentShape, path.toUtf8().constData(), &error);
        if (!ok) {
            const QString msg = QStringLiteral("导出失败：%1（%2）")
                .arg(fileName, QString::fromStdString(error));
            qWarning("Model export failed: %s (%s)", qUtf8Printable(path), error.c_str());
            this->reportExportStatus(msg);
            return;
        }
        this->reportExportStatus(QStringLiteral("已导出：%1").arg(fileName));
    }

    // 把导入结果消息跨线程写回 GUI 线程（经 QueuedConnection，避免在渲染线程直接改 QML 属性）
    void reportImportStatus(const QString& msg)
    {
        if (m_viewport)
            QMetaObject::invokeMethod(m_viewport, [vp = m_viewport, msg]() {
                vp->setImportStatus(msg);
            }, Qt::QueuedConnection);
    }

    // 把导出结果消息跨线程写回 GUI 线程
    void reportExportStatus(const QString& msg)
    {
        if (m_viewport)
            QMetaObject::invokeMethod(m_viewport, [vp = m_viewport, msg]() {
                vp->setExportStatus(msg);
            }, Qt::QueuedConnection);
    }

    // 把导入进度（-1 = 隐藏，0..1 = 进行中）跨线程写回 GUI 线程，供状态栏进度条显示
    void reportProgress(qreal p)
    {
        if (m_viewport)
            QMetaObject::invokeMethod(m_viewport, [vp = m_viewport, p]() {
                vp->setImportProgress(p);
            }, Qt::QueuedConnection);
    }

    // 把生效的显示模式跨线程写回 GUI 线程，供显示模式下拉框回显
    void reportDisplayMode(int mode)
    {
        if (m_viewport)
            QMetaObject::invokeMethod(m_viewport, [vp = m_viewport, mode]() {
                vp->updateDisplayMode(mode);
            }, Qt::QueuedConnection);
    }

    // 把当前模型类型（网格/实体）跨线程写回 GUI 线程
    void reportIsMesh(bool mesh)
    {
        if (m_viewport)
            QMetaObject::invokeMethod(m_viewport, [vp = m_viewport, mesh]() {
                vp->updateIsMeshModel(mesh);
            }, Qt::QueuedConnection);
    }

    // 在渲染线程应用网格显示状态：激活/停用 V3d_Viewer 的矩形网格（铺在 XY 平面）。
    void applyGridVisibility(bool on)
    {
        if (m_scene) {
            const auto& viewer = m_scene->v3dViewer();
            if (!viewer.IsNull()) {
                if (on) {
                    // 先设值再激活，避免依赖 V3d_Viewer 默认网格参数。
                    viewer->SetRectangularGridValues(0.0, 0.0, 10.0, 10.0, 0.0);
                    viewer->SetRectangularGridGraphicValues(1000.0, 1000.0, 0.0);
                    viewer->ActivateGrid(Aspect_GT_Rectangular, Aspect_GDM_Lines);
                }
                else {
                    viewer->DeactivateGrid();
                }
            }
        }
        if (!m_view.IsNull())
            m_view->Invalidate();
        this->reportGridVisible(on);
    }

    // 在渲染线程应用原点坐标系显示状态：显示/隐藏原点 AIS_Trihedron。
    void applyOriginVisibility(bool on)
    {
        if (m_scene && !m_originTrihedron.IsNull())
            m_scene->setObjectVisible(m_originTrihedron, on);
        if (!m_view.IsNull())
            m_view->Invalidate();
        this->reportOriginVisible(on);
    }

    // 把生效的网格显示状态跨线程写回 GUI 线程，供「显示」工具栏「网格」开关回显
    void reportGridVisible(bool on)
    {
        if (m_viewport)
            QMetaObject::invokeMethod(m_viewport, [vp = m_viewport, on]() {
                vp->updateGridVisible(on);
            }, Qt::QueuedConnection);
    }

    // 把生效的原点坐标系显示状态跨线程写回 GUI 线程
    void reportOriginVisible(bool on)
    {
        if (m_viewport)
            QMetaObject::invokeMethod(m_viewport, [vp = m_viewport, on]() {
                vp->updateOriginVisible(on);
            }, Qt::QueuedConnection);
    }

    // 在视口右上角显示视图立方体（含 XYZ 坐标轴），点击切换视角（参考 Mayo 的 AIS_ViewCube）
    void addViewCube()
    {
        const double dpr = m_input.devicePixelRatio > 0.0 ? m_input.devicePixelRatio : 1.0;

        m_viewCube = Mayo::makeOccHandle<AIS_ViewCube>();
        m_viewCube->SetSize(46. * dpr);
        m_viewCube->SetFontHeight(10. * dpr);
        // 视角切换由我们在 tryPickViewCube() 中依据 AIS_ViewCubeOwner 手动完成，
        // 关掉 cube 在检测/高亮时自动转动相机的行为（参考 Mayo：手动拾取时需关闭自动动画）。
        m_viewCube->SetAutoStartAnimation(false);

        // 外观对齐 Mayo：浅灰立方体（GRAY75），隐藏 X/Y/Z 轴字母标签（轴颜色本身已标识轴向）
        m_viewCube->SetBoxColor(Quantity_Color(Quantity_NOC_GRAY75));
        m_viewCube->SetAxesLabels("", "", "");

        // 三轴配色（对齐 Mayo）：X 红 / Y 绿 / Z 蓝，用 OCCT 命名色 RED2/GREEN2/BLUE2。
        const Prs3d_DatumParts axisParts[3] = {
            Prs3d_DatumParts_XAxis, Prs3d_DatumParts_YAxis, Prs3d_DatumParts_ZAxis
        };
        const Prs3d_DatumParts arrowParts[3] = {
            Prs3d_DatumParts_XArrow, Prs3d_DatumParts_YArrow, Prs3d_DatumParts_ZArrow
        };
        const Quantity_Color axisColors[3] = {
            Quantity_Color(Quantity_NOC_RED2),
            Quantity_Color(Quantity_NOC_GREEN2),
            Quantity_Color(Quantity_NOC_BLUE2)
        };
        // AIS_ViewCube 默认没有自有 DatumAspect（Attributes()->DatumAspect() 为空句柄），
        // 直接 ->LineAspect()/->ShadingAspect() 会空指针崩溃。必须先复制出自有 datum 外观再着色。
        m_viewCube->Attributes()->SetOwnDatumAspects();
        const auto& datum = m_viewCube->Attributes()->DatumAspect();
        if (!datum.IsNull()) {
            for (int i = 0; i < 3; ++i) {
                // 轴本体：优先 ShadingAspect（Mayo 用着色圆柱），同时补 LineAspect 兼容线状轴
                const auto& axisShading = datum->ShadingAspect(axisParts[i]);
                if (!axisShading.IsNull())
                    axisShading->SetColor(axisColors[i]);

                const auto& axisLine = datum->LineAspect(axisParts[i]);
                if (!axisLine.IsNull())
                    axisLine->SetColor(axisColors[i]);

                // 箭头锥体
                const auto& arrowShading = datum->ShadingAspect(arrowParts[i]);
                if (!arrowShading.IsNull())
                    arrowShading->SetColor(axisColors[i]);
            }
        }

        // 固定在右上角（TriedronPers 模式），离上边/右边各留出 90 逻辑像素间距（按 DPR 换算，同 Mayo）
        m_viewCube->SetTransformPersistence(
            new Graphic3d_TransformPers(
                Graphic3d_TMF_TriedronPers,
                Aspect_TOTP_RIGHT_UPPER,
                Graphic3d_Vec2i(int(90 * dpr), int(90 * dpr))));

        m_scene->addObject(m_viewCube);
    }

    // 在原点建立坐标系（参考 Mayo 的原点坐标轴 AIS_Trihedron）：X 红 / Y 绿 / Z 蓝的线框三轴，
    // 无箭头、大小固定不随视图缩放（ZoomPers 变换持久化），标识工件的基准坐标系。
    void addOriginTrihedron()
    {
        const double dpr = m_input.devicePixelRatio > 0.0 ? m_input.devicePixelRatio : 1.0;

        m_originTrihedron = Mayo::makeOccHandle<AIS_Trihedron>(
            Mayo::makeOccHandle<Geom_Axis2Placement>(gp::XOY()));
        m_originTrihedron->SetDatumDisplayMode(Prs3d_DM_WireFrame);
        m_originTrihedron->SetDrawArrows(false);
        // 大小不随视图缩放：ZoomPers 变换持久化，把三轴锚定在世界原点，长度单位按像素（同 Mayo）。
        m_originTrihedron->SetTransformPersistence(
            new Graphic3d_TransformPers(Graphic3d_TMF_ZoomPers, gp_Pnt(0., 0., 0.)));
        m_originTrihedron->SetSize(40.0 * dpr);   // 像素单位，按 DPR 换算保持逻辑尺寸一致

        // 三轴配色（对齐视图立方体 / Mayo）：X 红 / Y 绿 / Z 蓝，用 OCCT 命名色 RED2/GREEN2/BLUE2。
        // 线框模式下只画轴线（LineAspect），无箭头故无需给 arrow 着色。
        const Prs3d_DatumParts axisParts[3] = {
            Prs3d_DatumParts_XAxis, Prs3d_DatumParts_YAxis, Prs3d_DatumParts_ZAxis
        };
        const Quantity_Color axisColors[3] = {
            Quantity_Color(Quantity_NOC_RED2),
            Quantity_Color(Quantity_NOC_GREEN2),
            Quantity_Color(Quantity_NOC_BLUE2)
        };
        // AIS_Trihedron 默认没有自有 DatumAspect，需先 SetOwnDatumAspects 再按轴着色（否则空指针崩溃）。
        m_originTrihedron->Attributes()->SetOwnDatumAspects();
        const auto& datum = m_originTrihedron->Attributes()->DatumAspect();
        if (!datum.IsNull()) {
            for (int i = 0; i < 3; ++i) {
                const auto& axisLine = datum->LineAspect(axisParts[i]);
                if (!axisLine.IsNull())
                    axisLine->SetColor(axisColors[i]);
            }
        }

        m_scene->addObject(m_originTrihedron);
    }

    // 拾取右上角视图立方体：命中则切换到对应视角并返回 true
    bool tryPickViewCube(int px, int py)
    {
        if (!m_viewCube)
            return false;

        m_scene->highlightAt(px, py, m_view);
        const Mayo::GraphicsOwnerPtr owner = m_scene->currentHighlightedOwner();
        m_scene->clearSelection();  // 清除检测/高亮，避免残留

        const auto cubeOwner = Mayo::OccHandle<AIS_ViewCubeOwner>::DownCast(owner);
        if (!cubeOwner)
            return false;

        // 参考 Mayo 的 V3dViewCameraAnimation：先记录起始相机，再应用目标视角得到终点相机，
        // 然后恢复起始相机；随后的过渡由 advanceCameraAnimation() 每帧用
        // Graphic3d_CameraLerp + OutExpo 缓动插值完成（而不是瞬时的 SetProj）。
        const bool wasImmediateUpdate = m_view->SetImmediateUpdate(false);
        m_animStartCamera = Mayo::makeOccHandle<Graphic3d_Camera>();
        m_animStartCamera->Copy(m_view->Camera());
        m_view->SetProj(cubeOwner->MainOrientation());
        m_view->FitAll(0.1, false);
        m_view->ZFitAll();
        m_animEndCamera = Mayo::makeOccHandle<Graphic3d_Camera>();
        m_animEndCamera->Copy(m_view->Camera());
        m_view->Camera()->Copy(m_animStartCamera);   // 恢复起始相机，等待逐帧插值
        m_view->SetImmediateUpdate(wasImmediateUpdate);

        m_animating = true;
        // 关键：立即把渲染线程自己的进度副本归零。否则本次 render 同帧就会跑 advanceCameraAnimation()，
        // 而此时 GUI 线程的 startCameraAnimation()（QueuedConnection）还没执行，m_input.cameraAnimProgress
        // 仍是上一次动画 finished 留下的 1.0 —— 导致首帧直接插值到终点相机，表现为“无过渡直接跳转”。
        m_input.cameraAnimProgress = 0.0;
        // 通知 GUI 线程启动 QVariantAnimation 以驱动逐帧重绘。必须走 QueuedConnection 把调用
        // 排队到 GUI 线程事件循环，绝不能在渲染线程里直接调用 m_viewport->update()（那会造成卡死）。
        if (m_viewport)
            QMetaObject::invokeMethod(m_viewport, [vp = m_viewport]() { vp->startCameraAnimation(); }, Qt::QueuedConnection);
        return true;
    }

    // 悬停拾取：命中视图立方体则高亮对应部位；命中模型则把鼠标处的 3D 世界坐标发回 GUI 线程
    // 更新状态栏；空白处清空坐标。坐标经 QueuedConnection 写回，避免在渲染线程直接改 GUI 状态。
    void hoverAt(int px, int py)
    {
        m_scene->highlightAt(px, py, m_view);
        const Mayo::GraphicsOwnerPtr owner = m_scene->currentHighlightedOwner();
        const auto cubeOwner = Mayo::OccHandle<AIS_ViewCubeOwner>::DownCast(owner);

        QString coord;
        if (!cubeOwner) {
            // 参考 Mayo：用主选择器做一次「静默拾取」，拿到鼠标处模型表面上的真实 3D 点。
            // 命中模型时用 PickedPoint(1)（表面实际坐标）；否则退回 V3dView_to3dPosition
            // 的视图中心平面投影。这样状态栏显示的 XYZ 才是模型表面真实坐标，而非中心平面投影。
            const auto& selector = m_scene->mainSelector();
            selector->Pick(px, py, m_view);
            const gp_Pnt p = selector->NbPicked() > 0
                ? selector->PickedPoint(1)
                : Mayo::GraphicsUtils::V3dView_to3dPosition(m_view, px, py);

            if (!owner.IsNull())
                coord = QString("X: %1    Y: %2    Z: %3")
                            .arg(p.X(), 0, 'f', 3)
                            .arg(p.Y(), 0, 'f', 3)
                            .arg(p.Z(), 0, 'f', 3);
            // 非视图立方体：无拾取模式时清除 MoveTo 触发的动态高亮（模型/坐标轴悬停不高亮）。
            // 拾取模式下保留动态高亮（橙色），作为「鼠标拾上去高亮」的提示，不在此清除。
            // 悬停在视图立方体上时不调用 clearSelection —— 保留检测状态，让 AIS_ViewCube
            // 自动高亮鼠标指向的那个面/方向（AIS_ViewCubeOwner 对应具体朝向）。
            if (m_pickMode == int(GraphicsViewport::PickNone))
                m_scene->clearSelection();
        }
        // 悬停在视图立方体或空白处时 coord 为空 —— 不显示坐标

        if (m_viewport)
            QMetaObject::invokeMethod(m_viewport, [vp = m_viewport, coord]() {
                vp->setCursorCoordinates(coord);
            }, Qt::QueuedConnection);
    }

    // 左键点击拾取（拾取模式下）：把当前检测到的模型对象固定为选中（持久红色高亮）。
    // 点击空白处则取消固定选中；点击视图立方体由 tryPickViewCube 拦截，不走这里。
    void pickAt(int px, int py)
    {
        m_scene->highlightAt(px, py, m_view);
        const Mayo::GraphicsOwnerPtr owner = m_scene->currentHighlightedOwner();
        const auto cubeOwner = Mayo::OccHandle<AIS_ViewCubeOwner>::DownCast(owner);
        if (cubeOwner)
            return;   // 视图立方体：由 tryPickViewCube 处理，不参与模型拾取

        if (owner.IsNull()) {
            // 空白处：取消固定选中（悬停动态高亮由后续 hoverAt 更新）
            m_scene->clearSelection();
            return;
        }

        // 把当前检测到的 owner 设为选中（替换之前的选中，实现「点击固定高亮」）。
        // 场景选择模式为 Single 时等价于 SelectDetected(AIS_SelectionScheme_Replace)。
        m_scene->select();
    }

    // 视图切换相机动画：每帧推进一次（Mayo 的 V3dViewCameraAnimation::updateCurrentTime 逻辑）。
    // 进度来自 GUI 线程 QVariantAnimation 写入的 m_input.cameraAnimProgress（已含 OutExpo 缓动），
    // 这里只负责用 Graphic3d_CameraLerp 在起止相机间插值并每帧 ZFitAll。
    // 帧节奏完全由 GUI 线程的动画定时器驱动，渲染线程不再自行调度下一帧（那会导致卡死）。
    void advanceCameraAnimation()
    {
        if (!m_animating)
            return;

        const double t = std::clamp(m_input.cameraAnimProgress, 0.0, 1.0);

        const Graphic3d_CameraLerp lerp(m_animStartCamera, m_animEndCamera);
        Mayo::OccHandle<Graphic3d_Camera> camera = m_view->Camera();
        const bool prevImmediateUpdate = m_view->SetImmediateUpdate(false);
        lerp.Interpolate(t, camera);
        m_view->SetCamera(camera);
        m_view->ZFitAll();
        m_view->SetImmediateUpdate(prevImmediateUpdate);

        if (t >= 1.0)
            m_animating = false;
    }

    void applyNavigation()
    {
        const bool left = m_input.buttons.testFlag(Qt::LeftButton);
        const bool right = m_input.buttons.testFlag(Qt::RightButton);
        const bool middle = m_input.buttons.testFlag(Qt::MiddleButton);

        // Qt 鼠标事件使用逻辑像素，而 OCCT 视口/FBO 使用设备像素（高 DPI 下相差 devicePixelRatio 倍）。
        // 必须先按 DPR 换算，否则拾取/旋转/平移坐标整体偏移，点击视图立方体将无法命中。
        const qreal dpr = m_input.devicePixelRatio > 0.0 ? m_input.devicePixelRatio : 1.0;
        const int px = qRound(m_input.pos.x() * dpr);
        const int py = qRound(m_input.pos.y() * dpr);

        const bool prevLeft = m_prevButtons.testFlag(Qt::LeftButton);
        const bool prevRight = m_prevButtons.testFlag(Qt::RightButton);
        const bool prevMiddle = m_prevButtons.testFlag(Qt::MiddleButton);

        // 左键按下：先尝试拾取右上角视图立方体（点击切换视角）。拾取模式下左键不再独占为「拾取」，
        // 而是与旋转共存（不限旋转）：原地点击 = 拾取，按住拖动超过阈值 = 旋转。
        // V3d_View::Convert/StartRotation/Rotation 的像素输入都采用“左上角为原点”（与 Qt 一致），
        // 因此这里直接传 py，不做 y 翻转（y 翻转会导致视图立方体永远命中不了）。
        const bool pickMode = m_pickMode != int(GraphicsViewport::PickNone);
        if (left && !prevLeft) {
            m_viewCubeHit = this->tryPickViewCube(px, py);
            m_pickPressPos = m_input.pos;   // 记录按下位置（逻辑像素），用于点击/拖动判定
            m_pickDragRotating = false;
            if (!m_viewCubeHit && !pickMode)
                m_view->StartRotation(px, py);
        }
        else if (left && prevLeft) {
            if (!m_viewCubeHit) {
                if (!pickMode) {
                    m_view->Rotation(px, py);
                }
                else if (m_pickDragRotating) {
                    m_view->Rotation(px, py);   // 已判定为拖动：继续旋转
                }
                else if ((m_input.pos - m_pickPressPos).manhattanLength() >= 4.0) {
                    m_pickDragRotating = true;  // 移动超过阈值：进入拖动旋转
                    m_view->StartRotation(px, py);
                    m_view->Rotation(px, py);
                }
            }
        }
        else if (!left && prevLeft) {
            // 左键松开：拾取模式下若未发生拖动（原地点击），执行固定高亮拾取
            if (!m_viewCubeHit && pickMode && !m_pickDragRotating)
                this->pickAt(px, py);
        }

        // 右键 / 中键：平移。V3d_View::Pan 的 y 差量采用“向上为正”（与 Qt 的向下为正相反），
        // 故这里对 dy 取反；dx 不需要取反。
        if ((right || middle) && (prevRight || prevMiddle)) {
            const int dx = qRound((m_input.pos.x() - m_prevPos.x()) * dpr);
            const int dy = qRound((m_input.pos.y() - m_prevPos.y()) * dpr);
            m_view->Pan(dx, -dy);
        }

        // 滚轮：缩放
        if (m_input.wheelDelta != 0) {
            const double factor = std::exp(double(m_input.wheelDelta) / 240.0);
            m_view->SetZoom(factor);
        }

        // 悬停：未按键时高亮命中的视图立方体部位（拾取提示）。
        // 悬停事件由 hoverEnterEvent/hoverMoveEvent 更新（无按键移动走的是 hover 事件而非 mouseMoveEvent）。
        // 只在鼠标位置变化时拾取一次，避免每帧反复 MoveTo/ClearDetected ——
        // 每帧重复拾取会污染 OCCT 的检测/选择状态，渲染阶段会崩溃。
        if (m_renderedOnce && !left && !right && !middle) {
            if (m_input.hoverActive) {
                if (m_input.pos != m_lastHoverPos) {
                    m_lastHoverPos = m_input.pos;
                    this->hoverAt(px, py);
                }
            }
            else {
                // 鼠标已离开视口：清除残留的高亮（坐标文本在 GUI 线程的 hoverLeaveEvent 中清空）。
                // 拾取模式下保留已固定的选中（红色），只清除悬停高亮（橙色）。
                if (m_pickMode == int(GraphicsViewport::PickNone))
                    m_scene->clearSelection();
                else
                    m_scene->clearDetected();
            }
        }

        m_prevButtons = m_input.buttons;
        m_prevPos = m_input.pos;
    }

    // 后台模型读取线程及其结果交接（互斥保护）。读取在后台线程执行，渲染线程在
    // applyImportResultIfReady() 中取走结果并应用到 AIS 场景。
    std::thread m_importThread;
    std::mutex m_importMutex;
    bool m_importBusy = false;
    bool m_importReady = false;
    TopoDS_Shape m_importedShape;
    Mayo::OccHandle<TDocStd_Document> m_importedDocument;   // STEP/IGES 导入的 XCAF 文档（带颜色）
    std::string m_importedError;
    QString m_importedFileName;

    std::unique_ptr<Mayo::GraphicsScene> m_scene;
    Mayo::OccHandle<V3d_View> m_view;
    TopoDS_Shape m_currentShape;                                // 原始几何（供导出）
    Mayo::OccHandle<TDocStd_Document> m_document;               // 当前 STEP/IGES 的 XCAF 文档（保活供着色）
    std::vector<Mayo::GraphicsObjectPtr> m_currentObjects;      // AIS 显示对象（AIS_Shape / MeshVS_Mesh / XCAFPrs_AISObject）
    bool m_isMesh = false;                          // 当前模型是否为网格型
    Mayo::OccHandle<AIS_ViewCube> m_viewCube;
    Mayo::OccHandle<AIS_Trihedron> m_originTrihedron;
    QSize m_size;
    bool m_initFailed = false;
    bool m_viewCubeHit = false;
    bool m_pickDragRotating = false;    // 拾取模式下左键拖动是否已超过阈值进入旋转
    QPointF m_pickPressPos;             // 拾取模式下左键按下位置（逻辑像素），用于点击/拖动判定
    bool m_renderedOnce = false;
    bool m_debugDumpFrame = false;   // TEMP 诊断：导入模型后截取一帧 FBO 渲染
    bool m_debugDumpOcct = false;    // TEMP 诊断：FBO 截图后再补一张 OCCT 离屏渲染用于对比
    int m_pickMode = int(GraphicsViewport::PickFace);   // 当前拾取模式（0..4，对应 PickMode 枚举，默认面）

    // 视图切换相机动画（Mayo 式平滑过渡）：起止相机在渲染线程计算，进度由 GUI 线程动画驱动。
    GraphicsViewport* m_viewport = nullptr;                         // 用于经 QueuedConnection 触发 GUI 线程动画
    Mayo::OccHandle<Graphic3d_Camera> m_animStartCamera;
    Mayo::OccHandle<Graphic3d_Camera> m_animEndCamera;
    bool m_animating = false;

    // Qt 场景图持有该 FBO 的所有权（createFramebufferObject 返回值），此处仅保存指针用于在
    // render() 中显式绑定（Qt 6 不会自动绑定，GL_FRAMEBUFFER_BINDING==0 会导致 OCCT FBO 包装失败）。
    QOpenGLFramebufferObject* m_fbo = nullptr;

    GraphicsViewport::Input m_input;
    Qt::MouseButtons m_prevButtons;
    QPointF m_prevPos;
    QPointF m_lastHoverPos{-1., -1.};  // 无效哨兵，确保首次进入时执行一次拾取
};

// ---------------------------------------------------------------------------
// GraphicsViewport (QML item)
// ---------------------------------------------------------------------------

GraphicsViewport::GraphicsViewport(QQuickItem* parent)
    : QQuickFramebufferObject(parent),
      m_input(std::make_unique<Input>())
{
    setFlag(ItemHasContents, true);
    setAcceptedMouseButtons(Qt::AllButtons);
    setAcceptHoverEvents(true);
    // OCCT 以 OpenGL 约定渲染（原点在左下角），而 Qt Quick 场景图按左上角采样 FBO 纹理，
    // 必须垂直镜像，否则画面上下颠倒（模型、AIS_ViewCube 的 Y 标签等都会反）。
    setMirrorVertically(true);

    // 相机过渡动画（Mayo 式 QtAnimationBackend 的等价实现）：QVariantAnimation 运行在 GUI 线程，
    // 用 OutExpo 缓动把 0→1 的进度写入 m_input.cameraAnimProgress，每个 valueChanged 触发一次
    // update() 请求重绘。渲染线程在 render()/advanceCameraAnimation() 中按该进度插值相机，
    // 这样帧节奏由 GUI 线程事件循环驱动，彻底避免在渲染线程里直接 update() 造成的卡死。
    m_cameraAnim.setDuration(1000);  // 与 Mayo 默认一致（1 秒）
    m_cameraAnim.setStartValue(0.0);
    m_cameraAnim.setEndValue(1.0);
    m_cameraAnim.setEasingCurve(QEasingCurve(QEasingCurve::OutExpo));
    QObject::connect(&m_cameraAnim, &QVariantAnimation::valueChanged, this, [this](const QVariant& value) {
        m_input->cameraAnimProgress = value.toDouble();
        update();
    });
    // 动画结束时把进度补足到 1.0，保证最终相机精确停在目标视角（最后一次 valueChanged 可能略小于 1）
    QObject::connect(&m_cameraAnim, &QVariantAnimation::finished, this, [this]() {
        m_input->cameraAnimProgress = 1.0;
        update();
    });
}

GraphicsViewport::~GraphicsViewport() = default;

QQuickFramebufferObject::Renderer* GraphicsViewport::createRenderer() const
{
    return new GraphicsViewportRenderer;
}

void GraphicsViewport::startCameraAnimation()
{
    // GUI 线程：重启相机过渡动画（渲染线程拾取到视图立方体后经 QueuedConnection 触发）。
    // 动画立即把进度归零并重新计时，随后每个 valueChanged 更新进度并请求重绘。
    m_cameraAnim.stop();
    m_input->cameraAnimProgress = 0.0;
    m_cameraAnim.start();
}

void GraphicsViewport::setCursorCoordinates(const QString& coords)
{
    if (m_cursorCoordinates == coords)
        return;
    m_cursorCoordinates = coords;
    emit cursorCoordinatesChanged();
}

void GraphicsViewport::setImportStatus(const QString& status)
{
    if (m_importStatus == status)
        return;
    m_importStatus = status;
    emit importStatusChanged();
}

void GraphicsViewport::setExportStatus(const QString& status)
{
    if (m_exportStatus == status)
        return;
    m_exportStatus = status;
    emit exportStatusChanged();
}

void GraphicsViewport::setImportProgress(qreal progress)
{
    if (m_importProgress == progress)
        return;
    m_importProgress = progress;
    emit importProgressChanged();
}

void GraphicsViewport::updateDisplayMode(int mode)
{
    if (m_displayMode == mode)
        return;
    m_displayMode = mode;
    emit displayModeChanged();
}

void GraphicsViewport::updateIsMeshModel(bool mesh)
{
    if (m_isMeshModel == mesh)
        return;
    m_isMeshModel = mesh;
    emit isMeshModelChanged();
}

void GraphicsViewport::updatePickMode(int mode)
{
    if (m_pickMode == mode)
        return;
    m_pickMode = mode;
    emit pickModeChanged();
}

void GraphicsViewport::updateGridVisible(bool on)
{
    if (m_gridVisible == on)
        return;
    m_gridVisible = on;
    emit gridVisibleChanged();
}

void GraphicsViewport::updateOriginVisible(bool on)
{
    if (m_originVisible == on)
        return;
    m_originVisible = on;
    emit originVisibleChanged();
}

void GraphicsViewport::setDisplayMode(int mode)
{
    // QML 下拉框请求切换：写入待处理值并触发渲染线程应用。
    m_input->pendingDisplayMode = mode;
    update();
}

void GraphicsViewport::setPickMode(int mode)
{
    // QML 拾取下拉框请求切换：写入待处理值并触发渲染线程应用。
    m_input->pendingPickMode = mode;
    update();
}

void GraphicsViewport::setGridVisible(bool on)
{
    // QML「显示」工具栏「网格」开关：写入待处理值并触发渲染线程应用。
    m_input->pendingGridVisible = on ? 1 : 0;
    update();
}

void GraphicsViewport::setOriginVisible(bool on)
{
    // QML「显示」工具栏「坐标系」开关：写入待处理值并触发渲染线程应用。
    m_input->pendingOriginVisible = on ? 1 : 0;
    update();
}

void GraphicsViewport::importFile(const QUrl& url)
{
    const QString path = url.toLocalFile();
    if (path.isEmpty()) {
        setImportStatus(QStringLiteral("导入失败：无法从 %1 获取本地文件路径").arg(url.toString()));
        return;
    }
    setImportStatus(QStringLiteral("正在导入：%1 …").arg(QFileInfo(path).fileName()));
    setImportProgress(0.0);   // 立即显示进度条（0），随后渲染线程在读取期间持续更新
    m_input->importPath = path;
    update();   // 触发渲染线程在 synchronize() 中读取并解析
}

void GraphicsViewport::exportFile(const QUrl& url)
{
    const QString path = url.toLocalFile();
    if (path.isEmpty()) {
        setExportStatus(QStringLiteral("导出失败：无法从 %1 获取本地文件路径").arg(url.toString()));
        return;
    }
    setExportStatus(QStringLiteral("正在导出：%1 …").arg(QFileInfo(path).fileName()));
    m_input->exportPath = path;
    update();   // 触发渲染线程在 synchronize() 中读取并写文件
}

void GraphicsViewport::mousePressEvent(QMouseEvent* event)
{
    m_input->buttons = event->buttons();
    m_input->pos = event->position();
    update();
    event->accept();
}

void GraphicsViewport::mouseMoveEvent(QMouseEvent* event)
{
    m_input->buttons = event->buttons();
    m_input->pos = event->position();
    update();
    event->accept();
}

void GraphicsViewport::mouseReleaseEvent(QMouseEvent* event)
{
    m_input->buttons = event->buttons();
    m_input->pos = event->position();
    update();
    event->accept();
}

void GraphicsViewport::wheelEvent(QWheelEvent* event)
{
    m_input->wheelDelta += event->angleDelta().y();
    update();
    event->accept();
}

void GraphicsViewport::hoverEnterEvent(QHoverEvent* event)
{
    m_input->hoverActive = true;
    m_input->pos = event->position();
    update();
}

void GraphicsViewport::hoverMoveEvent(QHoverEvent* event)
{
    m_input->hoverActive = true;
    m_input->pos = event->position();
    update();
}

void GraphicsViewport::hoverLeaveEvent(QHoverEvent* event)
{
    m_input->hoverActive = false;
    setCursorCoordinates("");   // 鼠标离开视口：清空状态栏坐标
    update();
}
