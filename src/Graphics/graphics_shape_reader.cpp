#include "Graphics/graphics_shape_reader.h"

#include <BRep_Builder.hxx>
#include <BRepTools.hxx>
#include <IFSelect_ReturnStatus.hxx>
#include <IGESCAFControl_Reader.hxx>
#include <IGESControl_Reader.hxx>
#include <Message_ProgressIndicator.hxx>
#include <Message_ProgressRange.hxx>
#include <Message_ProgressScope.hxx>
#include <OSD_OpenFile.hxx>
#include <Poly_Triangle.hxx>
#include <Poly_Triangulation.hxx>
#include <RWObj.hxx>
#include <RWStl.hxx>
#include <STEPCAFControl_Reader.hxx>
#include <STEPControl_Reader.hxx>
#include <TCollection_ExtendedString.hxx>
#include <TDocStd_Document.hxx>
#include <TopoDS_Face.hxx>
#include <VrmlData_ErrorStatus.hxx>
#include <VrmlData_Scene.hxx>
#include <XCAFDoc_DocumentTool.hxx>

#include <algorithm>
#include <array>
#include <cctype>
#include <cstdint>
#include <cstdlib>
#include <cstring>
#include <fstream>
#include <sstream>
#include <vector>

namespace Mayo {

namespace {

// 把文件路径的扩展名（不含点、转为小写）取出来
std::string fileExtension(const std::string& filePath)
{
    const std::size_t dot = filePath.find_last_of('.');
    if (dot == std::string::npos)
        return {};
    std::string ext = filePath.substr(dot + 1);
    std::transform(ext.begin(), ext.end(), ext.begin(), [](unsigned char c) {
        return static_cast<char>(std::tolower(c));
    });
    return ext;
}

const char* returnStatusText(IFSelect_ReturnStatus status)
{
    switch (status) {
    case IFSelect_RetVoid:  return "RetVoid";
    case IFSelect_RetDone:  return "RetDone";
    case IFSelect_RetError: return "RetError";
    case IFSelect_RetFail:  return "RetFail";
    case IFSelect_RetStop:  return "RetStop";
    default:                return "unknown";
    }
}

// 若提供了进度回调则调用它（0..1）；空回调（MCP / headless 调用）时为空操作。
void notifyProgress(const ProgressCallback& progress, double value)
{
    if (progress)
        progress(value);
}

// 把一个 OCCT 的 Message_ProgressIndicator 桥接为普通回调：Show() 在每次进度更新时被调用，
// 这里读出 GetPosition()（0..1）并转发给用户回调。用它把 TransferRoots 等带进度参数的
// OCCT 操作映射到我们的 ProgressCallback，供 GUI 进度条显示。
class CallbackProgressIndicator : public Message_ProgressIndicator {
public:
    explicit CallbackProgressIndicator(const ProgressCallback& fn)
        : m_fn(fn) {}

protected:
    void Show(const Message_ProgressScope&, const Standard_Boolean) override
    {
        if (m_fn)
            m_fn(GetPosition());
    }

private:
    ProgressCallback m_fn;
};

// 把一个 Poly_Triangulation 包装为「单个 TopoDS_Face + 整块三角剖分」的表示。
// 与 StlAPI_Reader 的「每个三角形一个面」不同：这里只建一个面无底层面几何曲面，
// 供 GraphicsDisplayMode 识别为网格型并用 MeshVS_Mesh 显示 —— 读取与显示都快得多
// （Mayo 也是这么做的：RWStl::ReadFile → Poly_Triangulation → 单面）。
TopoDS_Shape shapeFromTriangulation(const Handle(Poly_Triangulation)& tri)
{
    TopoDS_Shape result;
    if (tri.IsNull() || tri->NbNodes() <= 0 || tri->NbTriangles() <= 0)
        return result;

    BRep_Builder builder;
    TopoDS_Face face;
    builder.MakeFace(face);
    builder.UpdateFace(face, tri);
    return face;
}

TopoDS_Shape readStepFile(const std::string& filePath, std::string* error, const ProgressCallback& progress)
{
    notifyProgress(progress, 0.0);
    STEPControl_Reader reader;
    const IFSelect_ReturnStatus status = reader.ReadFile(filePath.c_str());
    if (status != IFSelect_RetDone) {
        if (error)
            *error = std::string("ReadFile ") + returnStatusText(status) + "（文件不存在或不是有效 STEP）";
        return {};
    }
    notifyProgress(progress, 0.15);

    // TransferRoots 有进度参数（ReadFile 没有），把它的真实进度映射到 0.15..0.95。
    Handle(Message_ProgressIndicator) ind = new CallbackProgressIndicator(
        [progress](double pos) { notifyProgress(progress, 0.15 + pos * 0.80); });
    const Message_ProgressRange range = ind->Start();
    const int nbRoots = reader.TransferRoots(range);
    if (nbRoots <= 0) {
        if (error)
            *error = "TransferRoots 无可转换的几何实体";
        return {};
    }
    notifyProgress(progress, 0.95);
    TopoDS_Shape shape = reader.OneShape();
    notifyProgress(progress, 1.0);
    return shape;
}

TopoDS_Shape readIgesFile(const std::string& filePath, std::string* error, const ProgressCallback& progress)
{
    notifyProgress(progress, 0.0);
    IGESControl_Reader reader;
    const IFSelect_ReturnStatus status = reader.ReadFile(filePath.c_str());
    if (status != IFSelect_RetDone) {
        if (error)
            *error = std::string("ReadFile ") + returnStatusText(status) + "（文件不存在或不是有效 IGES）";
        return {};
    }
    notifyProgress(progress, 0.15);

    // TransferRoots 有进度参数（ReadFile 没有），把它的真实进度映射到 0.15..0.95。
    Handle(Message_ProgressIndicator) ind = new CallbackProgressIndicator(
        [progress](double pos) { notifyProgress(progress, 0.15 + pos * 0.80); });
    const Message_ProgressRange range = ind->Start();
    const int nbRoots = reader.TransferRoots(range);
    if (nbRoots <= 0) {
        if (error)
            *error = "TransferRoots 无可转换的几何实体";
        return {};
    }
    notifyProgress(progress, 0.95);
    TopoDS_Shape shape = reader.OneShape();
    notifyProgress(progress, 1.0);
    return shape;
}

TopoDS_Shape readBRepFile(const std::string& filePath, std::string* error, const ProgressCallback& progress)
{
    notifyProgress(progress, 0.0);
    BRep_Builder builder;
    TopoDS_Shape shape;
    if (!BRepTools::Read(shape, filePath.c_str(), builder)) {
        if (error)
            *error = "无法读取 BRep 文件";
        return {};
    }
    notifyProgress(progress, 1.0);
    return shape;
}

TopoDS_Shape readStlFile(const std::string& filePath, std::string* error, const ProgressCallback& progress)
{
    notifyProgress(progress, 0.0);
    // 用 RWStl::ReadFile 直接把 STL（自动识别 ASCII / 二进制）读成单个 Poly_Triangulation，
    // 再包成单面。StlAPI_Reader 会为每个三角形建一个 TopoDS_Face（大文件要十几秒），
    // 而单三角化 + 单面是 Mayo 的做法，读取快几个数量级。
    // 合并角度取 pi/2（与 RWStl::ReadFile 默认一致），即不按法向合并顶点。
    constexpr double stlMergeAngle = 1.57079632679489661923;   // M_PI / 2
    Handle(Message_ProgressIndicator) ind = new CallbackProgressIndicator(progress);
    const Message_ProgressRange range = ind->Start();
    const Handle(Poly_Triangulation) tri = RWStl::ReadFile(filePath.c_str(), stlMergeAngle, range);
    if (tri.IsNull() || tri->NbNodes() <= 0 || tri->NbTriangles() <= 0) {
        if (error)
            *error = "无法读取 STL 文件";
        return {};
    }
    notifyProgress(progress, 0.95);
    TopoDS_Shape shape = shapeFromTriangulation(tri);
    notifyProgress(progress, 1.0);
    return shape;
}

TopoDS_Shape readObjFile(const std::string& filePath, std::string* error, const ProgressCallback& progress)
{
    notifyProgress(progress, 0.0);
    const Handle(Poly_Triangulation) tri = RWObj::ReadFile(filePath.c_str());
    if (tri.IsNull() || tri->NbNodes() <= 0 || tri->NbTriangles() <= 0) {
        if (error)
            *error = "无法读取 OBJ 文件（或其中没有可用的三角网格）";
        return {};
    }
    notifyProgress(progress, 0.9);
    TopoDS_Shape shape = shapeFromTriangulation(tri);
    notifyProgress(progress, 1.0);
    return shape;
}

// ---------------------------------------------------------------------------
// PLY 读取（OCCT 7.8 没有公开的 PLY 读取器，这里实现一个最小但实用的解析器，
// 支持 ASCII、binary_little_endian、binary_big_endian 三种编码）。
// ---------------------------------------------------------------------------

struct PlyProperty {
    std::string name;
    std::string type;   // 数值类型，或 "list:countType:indexType"
};

struct PlyElement {
    std::string name;
    std::size_t count = 0;
    std::vector<PlyProperty> properties;
};

int plyTypeSize(const std::string& type)
{
    if (type == "char" || type == "int8" || type == "uchar" || type == "uint8") return 1;
    if (type == "short" || type == "int16" || type == "ushort" || type == "uint16") return 2;
    if (type == "int" || type == "int32" || type == "uint" || type == "uint32") return 4;
    if (type == "float" || type == "float32") return 4;
    if (type == "double" || type == "float64") return 8;
    return 0;
}

bool plyTypeIsFloat(const std::string& type)
{
    return type == "float" || type == "float32" || type == "double" || type == "float64";
}

double plyReadNumber(std::istream& in, const std::string& type, bool bigEndian)
{
    const int size = plyTypeSize(type);
    if (size <= 0 || size > 8)
        return 0.0;

    char buf[8] = {0};
    in.read(buf, size);
    if (bigEndian)
        std::reverse(buf, buf + size);

    if (plyTypeIsFloat(type)) {
        if (size == 4) {
            float f = 0.f;
            std::memcpy(&f, buf, 4);
            return double(f);
        }
        double d = 0.0;
        std::memcpy(&d, buf, 8);
        return d;
    }

    if (type == "char" || type == "int8") { int8_t v; std::memcpy(&v, buf, 1); return double(v); }
    if (type == "uchar" || type == "uint8") { uint8_t v; std::memcpy(&v, buf, 1); return double(v); }
    if (type == "short" || type == "int16") { int16_t v; std::memcpy(&v, buf, 2); return double(v); }
    if (type == "ushort" || type == "uint16") { uint16_t v; std::memcpy(&v, buf, 2); return double(v); }
    if (type == "int" || type == "int32") { int32_t v; std::memcpy(&v, buf, 4); return double(v); }
    uint32_t v = 0; std::memcpy(&v, buf, 4); return double(v);   // uint / uint32
}

std::vector<std::string> splitListSpec(const std::string& listSpec)
{
    // listSpec 形如 "list:countType:indexType"
    std::vector<std::string> parts;
    std::size_t start = 5;   // 跳过 "list:"
    while (start <= listSpec.size()) {
        const std::size_t pos = listSpec.find(':', start);
        parts.push_back(listSpec.substr(start, pos == std::string::npos ? std::string::npos : pos - start));
        if (pos == std::string::npos)
            break;
        start = pos + 1;
    }
    return parts;
}

TopoDS_Shape readPlyFile(const std::string& filePath, std::string* error, const ProgressCallback& progress)
{
    notifyProgress(progress, 0.0);
    std::ifstream in;
    OSD_OpenStream(in, filePath.c_str(), std::ios::in | std::ios::binary);
    if (!in) {
        if (error)
            *error = "无法打开文件";
        return {};
    }

    std::string line;
    if (!std::getline(in, line) || line.rfind("ply", 0) != 0) {
        if (error)
            *error = "不是有效的 PLY 文件";
        return {};
    }

    std::string format;
    std::vector<PlyElement> elements;
    PlyElement* current = nullptr;

    while (std::getline(in, line)) {
        if (!line.empty() && line.back() == '\r')
            line.pop_back();
        std::istringstream ls(line);
        std::string keyword;
        if (!(ls >> keyword))
            continue;
        if (keyword == "format") {
            ls >> format;
        }
        else if (keyword == "element") {
            std::string name;
            std::size_t count = 0;
            ls >> name >> count;
            elements.push_back({name, count, {}});
            current = &elements.back();
        }
        else if (keyword == "property" && current) {
            std::string t1;
            ls >> t1;
            if (t1 == "list") {
                std::string countType, indexType, name;
                ls >> countType >> indexType >> name;
                current->properties.push_back({name, "list:" + countType + ":" + indexType});
            }
            else {
                std::string name;
                ls >> name;
                current->properties.push_back({name, t1});
            }
        }
        else if (keyword == "end_header") {
            break;
        }
        // comment / obj_info 等其余行忽略
    }
    notifyProgress(progress, 0.15);

    const PlyElement* vertexEl = nullptr;
    const PlyElement* faceEl = nullptr;
    for (const PlyElement& e : elements) {
        if (e.name == "vertex")
            vertexEl = &e;
        else if (e.name == "face")
            faceEl = &e;
    }
    if (!vertexEl) {
        if (error)
            *error = "PLY 缺少 vertex 元素";
        return {};
    }

    int xIdx = -1, yIdx = -1, zIdx = -1;
    for (std::size_t i = 0; i < vertexEl->properties.size(); ++i) {
        const std::string& n = vertexEl->properties[i].name;
        if (n == "x") xIdx = int(i);
        else if (n == "y") yIdx = int(i);
        else if (n == "z") zIdx = int(i);
    }
    if (xIdx < 0 || yIdx < 0 || zIdx < 0) {
        if (error)
            *error = "PLY 顶点缺少 x/y/z 属性";
        return {};
    }

    int faceListIdx = -1;
    if (faceEl) {
        for (std::size_t i = 0; i < faceEl->properties.size(); ++i) {
            if (faceEl->properties[i].type.rfind("list:", 0) == 0) {
                faceListIdx = int(i);
                break;
            }
        }
    }

    const bool binary = format.rfind("binary", 0) == 0;
    const bool bigEndian = format == "binary_big_endian";

    // 顶点
    std::vector<gp_Pnt> points;
    points.reserve(vertexEl->count);
    for (std::size_t v = 0; v < vertexEl->count; ++v) {
        double xyz[3] = {0.0, 0.0, 0.0};
        for (std::size_t p = 0; p < vertexEl->properties.size(); ++p) {
            const std::string& type = vertexEl->properties[p].type;
            if (int(p) == xIdx || int(p) == yIdx || int(p) == zIdx) {
                double val = 0.0;
                if (binary) {
                    val = plyReadNumber(in, type, bigEndian);
                }
                else {
                    std::string tok;
                    in >> tok;
                    val = std::strtod(tok.c_str(), nullptr);
                }
                if (int(p) == xIdx) xyz[0] = val;
                else if (int(p) == yIdx) xyz[1] = val;
                else xyz[2] = val;
            }
            else if (binary) {
                plyReadNumber(in, type, bigEndian);   // 跳过其余属性
            }
            else {
                std::string tok;
                in >> tok;   // 跳过其余属性
            }
        }
        points.emplace_back(xyz[0], xyz[1], xyz[2]);
    }
    notifyProgress(progress, 0.55);

    // 面（list 属性：先读数量，再读索引；支持多边形扇形三角化）
    std::vector<std::array<int, 3>> triangles;
    if (faceEl && faceListIdx >= 0) {
        const std::vector<std::string> spec = splitListSpec(faceEl->properties[faceListIdx].type);
        const std::string countType = spec.size() > 0 ? spec[0] : "uchar";
        const std::string indexType = spec.size() > 1 ? spec[1] : "int";

        std::vector<int> idx;
        for (std::size_t f = 0; f < faceEl->count; ++f) {
            idx.clear();
            std::size_t n = 0;
            if (binary) {
                n = std::size_t(plyReadNumber(in, countType, bigEndian));
                for (std::size_t i = 0; i < n; ++i)
                    idx.push_back(int(plyReadNumber(in, indexType, bigEndian)));
            }
            else {
                std::size_t nIn = 0;
                in >> nIn;
                n = nIn;
                for (std::size_t i = 0; i < n; ++i) {
                    int k = 0;
                    in >> k;
                    idx.push_back(k);
                }
            }
            for (std::size_t i = 1; i + 1 < idx.size(); ++i)
                triangles.push_back({idx[0], idx[i], idx[i + 1]});
        }
    }

    if (points.empty() || triangles.empty()) {
        if (error)
            *error = "PLY 中没有可用的三角面";
        return {};
    }
    notifyProgress(progress, 0.85);

    Handle(Poly_Triangulation) tri =
        new Poly_Triangulation(int(points.size()), int(triangles.size()), Standard_False);
    for (std::size_t i = 0; i < points.size(); ++i)
        tri->SetNode(int(i + 1), points[i]);
    for (std::size_t i = 0; i < triangles.size(); ++i)
        tri->SetTriangle(int(i + 1),
                         Poly_Triangle(triangles[i][0] + 1, triangles[i][1] + 1, triangles[i][2] + 1));

    TopoDS_Shape shape = shapeFromTriangulation(tri);
    notifyProgress(progress, 1.0);
    return shape;
}

TopoDS_Shape readVrmlFile(const std::string& filePath, std::string* error, const ProgressCallback& progress)
{
    notifyProgress(progress, 0.0);
    std::ifstream in;
    OSD_OpenStream(in, filePath.c_str(), std::ios::in | std::ios::binary);
    if (!in) {
        if (error)
            *error = "无法打开文件";
        return {};
    }

    VrmlData_Scene scene;
    scene << in;
    if (scene.Status() != VrmlData_StatusOK) {
        if (error)
            *error = "不是有效的 VRML 文件（状态码 " + std::to_string(int(scene.Status())) + "）";
        return {};
    }
    notifyProgress(progress, 0.6);

    TopoDS_Shape shape = scene;   // VrmlData_Scene::operator TopoDS_Shape()
    if (shape.IsNull()) {
        if (error)
            *error = "VRML 中无可转换的几何";
        return {};
    }
    notifyProgress(progress, 1.0);
    return shape;
}

// 新建一个空的 XCAF 文档（挂上 XCAFDoc_DocumentTool，它会连带创建 ShapeTool/ColorTool
// 等子工具）。这是 STEPCAFControl_Reader / IGESCAFControl_Reader 写入颜色属性所必需的。
// 直接用 TDocStd_Document + XCAFDoc_DocumentTool::Set 构造，避免依赖 XCAFApp_Application
// 单例及其资源文件（Plugin/格式注册），在无 Draw/资源环境的独立应用中更稳妥。
OccHandle<TDocStd_Document> createXcafDocument()
{
    OccHandle<TDocStd_Document> doc = new TDocStd_Document(TCollection_ExtendedString("BinXCAF"));
    if (doc.IsNull())
        return {};
    XCAFDoc_DocumentTool::Set(doc->Main(), false);
    return doc;
}

// 读取 STEP 为 XCAF 文档（保留颜色/材质属性）。
// STEPCAFControl_Reader 默认开启 ColorMode/NameMode/LayerMode/PropsMode，会把模型原有
// 颜色写入文档的 XCAFDoc_ColorTool，供后续 XCAFPrs_AISObject 自动还原。
OccHandle<TDocStd_Document> readStepXcafDocument(
    const std::string& filePath, TopoDS_Shape* outShape, std::string* error,
    const ProgressCallback& progress)
{
    notifyProgress(progress, 0.0);
    STEPCAFControl_Reader reader;
    const IFSelect_ReturnStatus status = reader.ReadFile(filePath.c_str());
    if (status != IFSelect_RetDone) {
        if (error)
            *error = std::string("ReadFile ") + returnStatusText(status) + "（文件不存在或不是有效 STEP）";
        return {};
    }
    notifyProgress(progress, 0.15);

    OccHandle<TDocStd_Document> doc = createXcafDocument();
    if (doc.IsNull()) {
        if (error)
            *error = "无法创建 XCAF 文档";
        return {};
    }

    Handle(Message_ProgressIndicator) ind = new CallbackProgressIndicator(
        [progress](double pos) { notifyProgress(progress, 0.15 + pos * 0.80); });
    const Message_ProgressRange range = ind->Start();
    if (!reader.Transfer(doc, range)) {
        if (error)
            *error = "Transfer 无可转换的几何实体";
        return {};
    }
    notifyProgress(progress, 0.95);

    if (outShape)
        *outShape = reader.Reader().OneShape();
    notifyProgress(progress, 1.0);
    return doc;
}

// 读取 IGES 为 XCAF 文档（保留颜色属性）。
OccHandle<TDocStd_Document> readIgesXcafDocument(
    const std::string& filePath, TopoDS_Shape* outShape, std::string* error,
    const ProgressCallback& progress)
{
    notifyProgress(progress, 0.0);
    IGESCAFControl_Reader reader;
    const IFSelect_ReturnStatus status = reader.ReadFile(filePath.c_str());
    if (status != IFSelect_RetDone) {
        if (error)
            *error = std::string("ReadFile ") + returnStatusText(status) + "（文件不存在或不是有效 IGES）";
        return {};
    }
    notifyProgress(progress, 0.15);

    OccHandle<TDocStd_Document> doc = createXcafDocument();
    if (doc.IsNull()) {
        if (error)
            *error = "无法创建 XCAF 文档";
        return {};
    }

    Handle(Message_ProgressIndicator) ind = new CallbackProgressIndicator(
        [progress](double pos) { notifyProgress(progress, 0.15 + pos * 0.80); });
    const Message_ProgressRange range = ind->Start();
    if (!reader.Transfer(doc, range)) {
        if (error)
            *error = "Transfer 无可转换的几何实体";
        return {};
    }
    notifyProgress(progress, 0.95);

    if (outShape)
        *outShape = reader.OneShape();
    notifyProgress(progress, 1.0);
    return doc;
}

} // namespace

ShapeFormat shapeFormatFromFileName(const std::string& filePath)
{
    const std::string ext = fileExtension(filePath);
    if (ext == "step" || ext == "stp" || ext == "p21") return ShapeFormat::Step;
    if (ext == "iges" || ext == "igs") return ShapeFormat::Iges;
    if (ext == "brep" || ext == "rle") return ShapeFormat::BRep;
    if (ext == "stl") return ShapeFormat::Stl;
    if (ext == "obj") return ShapeFormat::Obj;
    if (ext == "ply") return ShapeFormat::Ply;
    if (ext == "wrl" || ext == "vrml") return ShapeFormat::Vrml;
    return ShapeFormat::Unknown;
}

const char* shapeFormatName(ShapeFormat format)
{
    switch (format) {
    case ShapeFormat::Step: return "STEP";
    case ShapeFormat::Iges: return "IGES";
    case ShapeFormat::BRep: return "BRep";
    case ShapeFormat::Stl:  return "STL";
    case ShapeFormat::Obj:  return "OBJ";
    case ShapeFormat::Ply:  return "PLY";
    case ShapeFormat::Vrml: return "VRML";
    default:                return "未知";
    }
}

namespace ShapeReader {

TopoDS_Shape read(const std::string& filePath, ShapeFormat format, std::string* error,
                  const ProgressCallback& progress)
{
    switch (format) {
    case ShapeFormat::Step: return readStepFile(filePath, error, progress);
    case ShapeFormat::Iges: return readIgesFile(filePath, error, progress);
    case ShapeFormat::BRep: return readBRepFile(filePath, error, progress);
    case ShapeFormat::Stl:  return readStlFile(filePath, error, progress);
    case ShapeFormat::Obj:  return readObjFile(filePath, error, progress);
    case ShapeFormat::Ply:  return readPlyFile(filePath, error, progress);
    case ShapeFormat::Vrml: return readVrmlFile(filePath, error, progress);
    default:
        if (error)
            *error = "不支持的文件格式（无法从扩展名识别）";
        return {};
    }
}

TopoDS_Shape read(const std::string& filePath, std::string* error, const ProgressCallback& progress)
{
    return read(filePath, shapeFormatFromFileName(filePath), error, progress);
}

OccHandle<TDocStd_Document> readXcafDocument(
    const std::string& filePath, ShapeFormat format,
    TopoDS_Shape* outShape, std::string* error, const ProgressCallback& progress)
{
    switch (format) {
    case ShapeFormat::Step: return readStepXcafDocument(filePath, outShape, error, progress);
    case ShapeFormat::Iges: return readIgesXcafDocument(filePath, outShape, error, progress);
    default:
        if (error)
            *error = "该格式不支持 XCAF 颜色读取（仅 STEP/IGES）";
        return {};
    }
}

} // namespace ShapeReader

} // namespace Mayo
