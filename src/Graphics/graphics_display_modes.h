#pragma once

#include "graphics_object_ptr.h"
#include <TopoDS_Shape.hxx>

#include <vector>

class TDocStd_Document;

// 3D 模型显示模式（Qt-free，供 GUI / MCP / headless 复用）。
// 与 Mayo 的 GraphicsShapeObjectDriver / GraphicsMeshObjectDriver 显示模式一致：
//   - Shape 模式对应 AIS_Shape（BRep 实体，来自 STEP/IGES/BRep）
//   - Mesh 模式对应 MeshVS_Mesh（三角网格，来自 STL/OBJ/PLY）

namespace Mayo {

enum class DisplayMode {
    ShapeWireframe = 0,        // 形状：线框
    ShapeHiddenLineRemoval,    // 形状：隐藏线移除（HLR）
    ShapeShaded,               // 形状：着色
    ShapeShadedWithEdges,      // 形状：着色 + 边线
    MeshWireframe,             // 网格：线框
    MeshShaded,                // 网格：着色（壳 / 双面）
    MeshSolid,                 // 网格：实体（背面剔除）
    MeshShrink                 // 网格：收缩（Shrink）
};

// 判断 shape 是否为「网格型」表示：单个面且无底层几何曲面（BRep_Builder::MakeFace 创建的面）。
// STL/OBJ/PLY 读入后是「一个 Poly_Triangulation + 单个 TopoDS_Face」，其面无曲面；
// BRep 模型（STEP/IGES/BRep）的面都带 Geom_Surface，据此区分。
bool isMeshShape(const TopoDS_Shape& shape);

// 依据 shape 创建 AIS 显示对象：网格型 → MeshVS_Mesh（单三角化，显示快），
// BRep 型 → AIS_Shape。失败返回空句柄。
GraphicsObjectPtr createDisplayObject(const TopoDS_Shape& shape);

// 从 XCAF 文档创建带颜色的显示对象：每个顶层自由形状一个 XCAFPrs_AISObject，
// 由该对象自动从文档的 XCAFDoc_ColorTool 还原 STEP/IGES 原始颜色。
// 文档为空 / 无几何时返回空序列。返回的对象需加入 AIS 场景后显示。
std::vector<GraphicsObjectPtr> createDisplayObjects(const OccHandle<TDocStd_Document>& document);

// 预三角化 shape（对齐 Mayo：显示对象创建前先算好三角剖分，再配合
// SetAutoTriangulation(false) + SetIsoOnTriangulation(true) 使用）。缺陷大小按
// 包围盒对角线的 1‰（与导出路径的 triangulateShape 一致），保证「着色带边」的
// 边线/轮廓线由连续三角化计算，而非在原始曲面上算出的破碎线段（表现为虚线）。
void meshShape(const TopoDS_Shape& shape);

// 预三角化 XCAF 文档中的所有顶层自由形状（供 STEP/IGES 的 XCAFPrs_AISObject 显示）。
void meshDocument(const OccHandle<TDocStd_Document>& document);

// 应用显示模式（对象必须已由 createDisplayObject 创建并加入 AIS 场景）。
// 模式与对象类型不匹配时为空操作（例如对 AIS_Shape 应用 MeshShaded）。
void applyDisplayMode(const GraphicsObjectPtr& object, DisplayMode mode);

// 读取对象当前显示模式（供 UI 回显）。对象为空时返回 ShapeShadedWithEdges。
DisplayMode currentDisplayMode(const GraphicsObjectPtr& object);

} // namespace Mayo
