#include "Graphics/graphics_shape_writer.h"

#include <Bnd_Box.hxx>
#include <BRep_Builder.hxx>
#include <BRep_Tool.hxx>
#include <BRepBndLib.hxx>
#include <BRepMesh_IncrementalMesh.hxx>
#include <BRepTools.hxx>
#include <IFSelect_ReturnStatus.hxx>
#include <IGESControl_Writer.hxx>
#include <OSD_OpenFile.hxx>
#include <Poly_Triangulation.hxx>
#include <STEPControl_StepModelType.hxx>
#include <STEPControl_Writer.hxx>
#include <StlAPI_Writer.hxx>
#include <TopExp_Explorer.hxx>
#include <TopoDS.hxx>
#include <TopoDS_Face.hxx>
#include <VrmlAPI_RepresentationOfShape.hxx>
#include <VrmlAPI_Writer.hxx>

#include <cmath>
#include <fstream>
#include <iomanip>

namespace Mayo {

namespace {

// 确保 shape 的面已带三角化（OBJ/PLY 等网格导出需要），缺陷大小按包围盒对角线的 1‰。
void triangulateShape(const TopoDS_Shape& shape)
{
    Bnd_Box box;
    BRepBndLib::Add(shape, box);
    double deflection = 0.1;
    if (!box.IsVoid()) {
        double xmin = 0, ymin = 0, zmin = 0, xmax = 0, ymax = 0, zmax = 0;
        box.Get(xmin, ymin, zmin, xmax, ymax, zmax);
        const double diag = std::sqrt(
            (xmax - xmin) * (xmax - xmin) +
            (ymax - ymin) * (ymax - ymin) +
            (zmax - zmin) * (zmax - zmin));
        if (diag > 1e-9)
            deflection = diag * 1e-3;
    }
    BRepMesh_IncrementalMesh mesh(shape, deflection, false, 0.5, true);
    (void)mesh;
}

// 遍历 shape 的所有面三角化，对每个三角形（世界坐标）调用 fn(p1, p2, p3)。
template<typename Fn>
void foreachTriangle(const TopoDS_Shape& shape, Fn fn)
{
    for (TopExp_Explorer ex(shape, TopAbs_FACE); ex.More(); ex.Next()) {
        const TopoDS_Face& face = TopoDS::Face(ex.Current());
        TopLoc_Location loc;
        const Handle(Poly_Triangulation)& tri = BRep_Tool::Triangulation(face, loc);
        if (tri.IsNull())
            continue;
        const gp_Trsf trsf = loc.Transformation();
        for (int i = 1; i <= tri->NbTriangles(); ++i) {
            int n1 = 0, n2 = 0, n3 = 0;
            tri->Triangle(i).Get(n1, n2, n3);
            const gp_Pnt p1 = tri->Node(n1).Transformed(trsf);
            const gp_Pnt p2 = tri->Node(n2).Transformed(trsf);
            const gp_Pnt p3 = tri->Node(n3).Transformed(trsf);
            fn(p1, p2, p3);
        }
    }
}

bool writeStepFile(const TopoDS_Shape& shape, const std::string& filePath, std::string* error)
{
    STEPControl_Writer writer;
    if (writer.Transfer(shape, STEPControl_AsIs) != IFSelect_RetDone) {
        if (error)
            *error = "Transfer 失败（shape 无法转为 STEP）";
        return false;
    }
    if (writer.Write(filePath.c_str()) != IFSelect_RetDone) {
        if (error)
            *error = "写入 STEP 文件失败";
        return false;
    }
    return true;
}

bool writeIgesFile(const TopoDS_Shape& shape, const std::string& filePath, std::string* error)
{
    IGESControl_Writer writer("MM", 0);
    if (!writer.AddShape(shape)) {
        if (error)
            *error = "AddShape 失败（shape 无法转为 IGES）";
        return false;
    }
    if (!writer.Write(filePath.c_str())) {
        if (error)
            *error = "写入 IGES 文件失败";
        return false;
    }
    return true;
}

bool writeBRepFile(const TopoDS_Shape& shape, const std::string& filePath, std::string* error)
{
    if (!BRepTools::Write(shape, filePath.c_str())) {
        if (error)
            *error = "写入 BRep 文件失败";
        return false;
    }
    return true;
}

bool writeStlFile(const TopoDS_Shape& shape, const std::string& filePath, std::string* error)
{
    StlAPI_Writer writer;
    writer.ASCIIMode() = true;
    if (!writer.Write(shape, filePath.c_str())) {
        if (error)
            *error = "写入 STL 文件失败";
        return false;
    }
    return true;
}

bool writeVrmlFile(const TopoDS_Shape& shape, const std::string& filePath, std::string* error)
{
    VrmlAPI_Writer writer;
    writer.SetRepresentation(VrmlAPI_ShadedRepresentation);
    if (!writer.Write(shape, filePath.c_str(), 2)) {
        if (error)
            *error = "写入 VRML 文件失败";
        return false;
    }
    return true;
}

bool writeObjFile(const TopoDS_Shape& shape, const std::string& filePath, std::string* error)
{
    TopoDS_Shape s = shape;
    triangulateShape(s);

    std::ofstream out;
    OSD_OpenStream(out, filePath.c_str(), std::ios::out | std::ios::trunc);
    if (!out) {
        if (error)
            *error = "无法创建文件";
        return false;
    }
    out << std::setprecision(10);
    out << "# CXCAM export (OBJ)\n";

    long idx = 0;
    foreachTriangle(s, [&](const gp_Pnt& p1, const gp_Pnt& p2, const gp_Pnt& p3) {
        out << "v " << p1.X() << ' ' << p1.Y() << ' ' << p1.Z() << '\n';
        out << "v " << p2.X() << ' ' << p2.Y() << ' ' << p2.Z() << '\n';
        out << "v " << p3.X() << ' ' << p3.Y() << ' ' << p3.Z() << '\n';
        out << "f " << (idx + 1) << ' ' << (idx + 2) << ' ' << (idx + 3) << '\n';
        idx += 3;
    });
    return true;
}

bool writePlyFile(const TopoDS_Shape& shape, const std::string& filePath, std::string* error)
{
    TopoDS_Shape s = shape;
    triangulateShape(s);

    long nbVerts = 0;
    long nbFaces = 0;
    foreachTriangle(s, [&](const gp_Pnt&, const gp_Pnt&, const gp_Pnt&) {
        nbVerts += 3;
        nbFaces += 1;
    });

    std::ofstream out;
    OSD_OpenStream(out, filePath.c_str(), std::ios::out | std::ios::trunc);
    if (!out) {
        if (error)
            *error = "无法创建文件";
        return false;
    }
    out << std::setprecision(10);
    out << "ply\n";
    out << "format ascii 1.0\n";
    out << "element vertex " << nbVerts << "\n";
    out << "property float x\nproperty float y\nproperty float z\n";
    out << "element face " << nbFaces << "\n";
    out << "property list uchar int vertex_indices\n";
    out << "end_header\n";

    long vidx = 0;
    foreachTriangle(s, [&](const gp_Pnt& p1, const gp_Pnt& p2, const gp_Pnt& p3) {
        out << p1.X() << ' ' << p1.Y() << ' ' << p1.Z() << '\n';
        out << p2.X() << ' ' << p2.Y() << ' ' << p2.Z() << '\n';
        out << p3.X() << ' ' << p3.Y() << ' ' << p3.Z() << '\n';
        out << "3 " << vidx << ' ' << (vidx + 1) << ' ' << (vidx + 2) << '\n';
        vidx += 3;
    });
    return true;
}

} // namespace

namespace ShapeWriter {

bool write(const TopoDS_Shape& shape, const std::string& filePath, ShapeFormat format, std::string* error)
{
    if (shape.IsNull()) {
        if (error)
            *error = "没有可导出的几何（请先导入模型）";
        return false;
    }

    switch (format) {
    case ShapeFormat::Step: return writeStepFile(shape, filePath, error);
    case ShapeFormat::Iges: return writeIgesFile(shape, filePath, error);
    case ShapeFormat::BRep: return writeBRepFile(shape, filePath, error);
    case ShapeFormat::Stl:  return writeStlFile(shape, filePath, error);
    case ShapeFormat::Obj:  return writeObjFile(shape, filePath, error);
    case ShapeFormat::Ply:  return writePlyFile(shape, filePath, error);
    case ShapeFormat::Vrml: return writeVrmlFile(shape, filePath, error);
    default:
        if (error)
            *error = "不支持的文件格式（无法从扩展名识别）";
        return false;
    }
}

bool write(const TopoDS_Shape& shape, const std::string& filePath, std::string* error)
{
    return write(shape, filePath, shapeFormatFromFileName(filePath), error);
}

} // namespace ShapeWriter

} // namespace Mayo
