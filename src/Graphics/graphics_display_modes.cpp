#include "graphics_display_modes.h"

#include "graphics_mesh_data_source.h"

#include <AIS_DisplayMode.hxx>
#include <AIS_InteractiveContext.hxx>
#include <AIS_Shape.hxx>
#include <BRep_TFace.hxx>
#include <BRep_Tool.hxx>
#include <Geom_Surface.hxx>
#include <Graphic3d_MaterialAspect.hxx>
#include <Graphic3d_NameOfMaterial.hxx>
#include <MeshVS_DisplayModeFlags.hxx>
#include <MeshVS_Drawer.hxx>
#include <MeshVS_DrawerAttribute.hxx>
#include <MeshVS_Mesh.hxx>
#include <MeshVS_MeshPrsBuilder.hxx>
#include <MeshVS_MeshSelectionMethod.hxx>
#include <Prs3d_Drawer.hxx>
#include <Prs3d_LineAspect.hxx>
#include <Prs3d_TypeOfHLR.hxx>
#include <Quantity_Color.hxx>
#include <TDocStd_Document.hxx>
#include <TopoDS.hxx>
#include <TopoDS_Face.hxx>
#include <V3d_View.hxx>
#include <V3d_Viewer.hxx>
#include <XCAFDoc_DocumentTool.hxx>
#include <XCAFDoc_ShapeTool.hxx>
#include <XCAFPrs_AISObject.hxx>

namespace Mayo {

namespace {

bool isMeshObject(const GraphicsObjectPtr& object)
{
    return !OccHandle<MeshVS_Mesh>::DownCast(object).IsNull();
}

// 从单个带三角剖分的面创建 MeshVS_Mesh（对齐 GraphicsMeshObjectDriver::createObject，
// 只是输入从 TDF_Label 改为原始 TopoDS_Shape）。
GraphicsObjectPtr createMeshObject(const TopoDS_Shape& shape)
{
    OccHandle<Poly_Triangulation> polyTri;
    const TopoDS_Face& face = TopoDS::Face(shape);
    const auto tface = OccHandle<BRep_TFace>::DownCast(face.TShape());
    if (!tface.IsNull())
        polyTri = tface->Triangulation();

    if (polyTri.IsNull() || polyTri->NbNodes() <= 0 || polyTri->NbTriangles() <= 0)
        return {};

    auto object = makeOccHandle<MeshVS_Mesh>();
    object->SetDataSource(new GraphicsMeshDataSource(polyTri));
    object->AddBuilder(new MeshVS_MeshPrsBuilder(object), true);

    object->GetDrawer()->SetBoolean(MeshVS_DA_ShowEdges, false);
    object->GetDrawer()->SetBoolean(MeshVS_DA_DisplayNodes, false);
    object->GetDrawer()->SetColor(MeshVS_DA_InteriorColor, Quantity_NOC_BISQUE);
    object->GetDrawer()->SetMaterial(
        MeshVS_DA_FrontMaterial, Graphic3d_MaterialAspect(Graphic3d_NOM_PLASTER));
    object->GetDrawer()->SetColor(MeshVS_DA_EdgeColor, Quantity_NOC_BLACK);
    object->GetDrawer()->SetBoolean(MeshVS_DA_ColorReflection, true);
    object->GetDrawer()->SetDouble(MeshVS_DA_ShrinkCoeff, 0.25);

    object->SetDisplayMode(MeshVS_DMF_Shading);
    object->SetMeshSelMethod(MeshVS_MSM_PRECISE);
    return object;
}

// 创建 AIS_Shape（对齐 GraphicsShapeObjectDriver::createObject；此处不预先三角化，
// 交由 AIS 自动三角化，故保留 SetAutoTriangulation 默认 true）。
GraphicsObjectPtr createShapeObject(const TopoDS_Shape& shape)
{
    auto object = makeOccHandle<AIS_Shape>(shape);
    object->SetDisplayMode(AIS_Shaded);
    object->SetMaterial(Graphic3d_MaterialAspect(Graphic3d_NOM_PLASTER));
    object->Attributes()->SetFaceBoundaryDraw(true);
    object->Attributes()->SetFaceBoundaryAspect(
        new Prs3d_LineAspect(Quantity_NOC_BLACK, Aspect_TOL_SOLID, 1.0));
    return object;
}

} // namespace

bool isMeshShape(const TopoDS_Shape& shape)
{
    if (shape.IsNull() || shape.ShapeType() != TopAbs_FACE)
        return false;
    TopLoc_Location loc;
    const Handle(Geom_Surface)& surf = BRep_Tool::Surface(TopoDS::Face(shape), loc);
    return surf.IsNull();
}

GraphicsObjectPtr createDisplayObject(const TopoDS_Shape& shape)
{
    if (shape.IsNull())
        return {};
    return isMeshShape(shape) ? createMeshObject(shape) : createShapeObject(shape);
}

std::vector<GraphicsObjectPtr> createDisplayObjects(const OccHandle<TDocStd_Document>& document)
{
    std::vector<GraphicsObjectPtr> result;
    if (document.IsNull())
        return result;

    const OccHandle<XCAFDoc_ShapeTool> shapeTool = XCAFDoc_DocumentTool::ShapeTool(document->Main());
    if (shapeTool.IsNull())
        return result;

    TDF_LabelSequence freeShapes;
    shapeTool->GetFreeShapes(freeShapes);

    for (const TDF_Label& label : freeShapes) {
        if (!XCAFDoc_ShapeTool::IsShape(label))
            continue;

        // XCAFPrs_AISObject 在 Compute 时经 DispatchStyles 从文档的 XCAFDoc_ColorTool
        // 读取子形状颜色，还原 STEP/IGES 模型原有颜色。SetMaterial 只是给无颜色样式
        // 一个默认材质，不会覆盖 XDE 颜色样式。
        auto object = makeOccHandle<XCAFPrs_AISObject>(label);
        object->SetDisplayMode(AIS_Shaded);
        object->SetMaterial(Graphic3d_MaterialAspect(Graphic3d_NOM_PLASTER));
        object->Attributes()->SetFaceBoundaryDraw(true);
        object->Attributes()->SetFaceBoundaryAspect(
            new Prs3d_LineAspect(Quantity_NOC_BLACK, Aspect_TOL_SOLID, 1.0));
        result.push_back(object);
    }
    return result;
}

void applyDisplayMode(const GraphicsObjectPtr& object, DisplayMode mode)
{
    if (object.IsNull())
        return;

    AIS_InteractiveContext* ctx = object->InteractiveContext();
    if (!ctx)
        return;

    if (isMeshObject(object)) {
        int aisMode = -1;
        bool suppressBackFaces = false;
        switch (mode) {
        case DisplayMode::MeshWireframe: aisMode = MeshVS_DMF_WireFrame; break;
        case DisplayMode::MeshShaded:    aisMode = MeshVS_DMF_Shading;   break;
        case DisplayMode::MeshSolid:     aisMode = MeshVS_DMF_Shading; suppressBackFaces = true; break;
        case DisplayMode::MeshShrink:    aisMode = MeshVS_DMF_Shrink;    break;
        default: return;   // shape 模式不适用于网格
        }

        // 实体 = 背面剔除（只画朝外的面，呈实体外观）；壳 = 双面（默认）。二者都走
        // MeshVS_DMF_Shading 模式，区别只在抽屉属性，故先改属性再 SetDisplayMode，
        // 并显式 Redisplay 让属性变更重算表示（模式未变时 SetDisplayMode 不会重算）。
        auto mesh = OccHandle<MeshVS_Mesh>::DownCast(object);
        if (!mesh.IsNull() && !mesh->GetDrawer().IsNull()) {
            mesh->GetDrawer()->SetBoolean(MeshVS_DA_SupressBackFaces, suppressBackFaces);
        }

        ctx->SetDisplayMode(object, aisMode, false);
        object->Redisplay(true);
        return;
    }

    // 形状（AIS_Shape）—— 与 GraphicsShapeObjectDriver::applyDisplayMode 一致
    if (mode < DisplayMode::ShapeWireframe || mode > DisplayMode::ShapeShadedWithEdges)
        return;

    auto fnSetViewComputedMode = [ctx](bool on) {
        for (auto it = ctx->CurrentViewer()->DefinedViewIterator(); it.More(); it.Next())
            it.Value()->SetComputedMode(on);
    };

    if (mode == DisplayMode::ShapeHiddenLineRemoval) {
        ctx->DefaultDrawer()->SetTypeOfHLR(Prs3d_TOH_PolyAlgo);
        ctx->DefaultDrawer()->EnableDrawHiddenLine();
        fnSetViewComputedMode(true);
    }
    else {
        ctx->DefaultDrawer()->SetTypeOfHLR(Prs3d_TOH_NotSet);
        ctx->DefaultDrawer()->DisableDrawHiddenLine();
        fnSetViewComputedMode(false);

        const AIS_DisplayMode aisMode =
            mode == DisplayMode::ShapeWireframe ? AIS_WireFrame : AIS_Shaded;
        const bool showFaceBounds = mode == DisplayMode::ShapeShadedWithEdges;
        if (object->DisplayMode() != aisMode)
            ctx->SetDisplayMode(object, aisMode, false);
        if (object->Attributes()->FaceBoundaryDraw() != showFaceBounds) {
            object->Attributes()->SetFaceBoundaryDraw(showFaceBounds);
            object->Redisplay(true);
        }
    }
}

DisplayMode currentDisplayMode(const GraphicsObjectPtr& object)
{
    if (object.IsNull())
        return DisplayMode::ShapeShadedWithEdges;

    if (isMeshObject(object)) {
        switch (object->DisplayMode()) {
        case MeshVS_DMF_WireFrame: return DisplayMode::MeshWireframe;
        case MeshVS_DMF_Shrink:    return DisplayMode::MeshShrink;
        default:                   break;
        }

        // Shading 模式下用背面剔除标志区分「实体」与「壳（双面）」
        auto mesh = OccHandle<MeshVS_Mesh>::DownCast(object);
        bool suppressBackFaces = false;
        if (!mesh.IsNull() && !mesh->GetDrawer().IsNull())
            mesh->GetDrawer()->GetBoolean(MeshVS_DA_SupressBackFaces, suppressBackFaces);
        return suppressBackFaces ? DisplayMode::MeshSolid : DisplayMode::MeshShaded;
    }

    AIS_InteractiveContext* ctx = object->InteractiveContext();
    if (ctx && ctx->DrawHiddenLine())
        return DisplayMode::ShapeHiddenLineRemoval;

    const int dm = object->DisplayMode();
    if (dm == AIS_WireFrame)
        return DisplayMode::ShapeWireframe;
    if (dm == AIS_Shaded) {
        return object->Attributes()->FaceBoundaryDraw()
            ? DisplayMode::ShapeShadedWithEdges
            : DisplayMode::ShapeShaded;
    }
    return DisplayMode::ShapeShadedWithEdges;
}

} // namespace Mayo
