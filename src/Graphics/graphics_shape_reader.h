#pragma once

#include "base/occ_handle.h"
#include <TopoDS_Shape.hxx>

#include <functional>
#include <string>

class TDocStd_Document;

// CAD 文件 → OpenCASCADE 几何（Qt-free）：供 GUI、MCP server、headless/batch 复用。
// 导入（ShapeReader）与导出（ShapeWriter）共用同一个格式枚举 ShapeFormat。

namespace Mayo {

// 支持的 CAD / 网格交换格式
enum class ShapeFormat {
    Unknown,
    Step,   // .step / .stp / .p21
    Iges,   // .iges / .igs
    BRep,   // .brep / .rle（OpenCASCADE 原生格式）
    Stl,    // .stl（ASCII / 二进制）
    Obj,    // .obj（Wavefront OBJ）
    Ply,    // .ply（ASCII / 二进制小端 / 大端）
    Vrml    // .wrl / .vrml（VRML 2.0）
};

// 由文件扩展名（大小写不敏感）推断格式；无法识别返回 ShapeFormat::Unknown。
ShapeFormat shapeFormatFromFileName(const std::string& filePath);

// 格式显示名（"STEP" / "IGES" / "BRep" / "STL" / "OBJ" / "PLY" / "VRML" / "未知"）。
const char* shapeFormatName(ShapeFormat format);

// 读取进度回调：progress 传入 0.0（开始）~1.0（完成）的进度值，用于 GUI 进度条。
// 为空表示不需要进度（MCP / headless 调用）。
using ProgressCallback = std::function<void(double)>;

namespace ShapeReader {

// 读取 CAD 文件为单个 TopoDS_Shape。读取/转换失败返回空 shape（IsNull() == true），
// 并在 error（若非空）中写入原因。progress（若非空）在读取/转换期间被多次调用以报告进度。
TopoDS_Shape read(const std::string& filePath, ShapeFormat format, std::string* error = nullptr,
                  const ProgressCallback& progress = {});

// 自动按扩展名识别格式。
TopoDS_Shape read(const std::string& filePath, std::string* error = nullptr,
                  const ProgressCallback& progress = {});

// 读取 STEP/IGES 为 XCAF 文档（保留模型的原始颜色/材质属性），失败返回空句柄。
// outShape（若非空）写入整个模型的组合几何（供导出 / FitAll）。
// 返回的文档需由调用方持有，供 XCAFPrs_AISObject 在其生命周期内读取颜色。
// 仅 STEP/IGES 支持；其它格式返回空句柄并报错。
OccHandle<TDocStd_Document> readXcafDocument(
    const std::string& filePath, ShapeFormat format,
    TopoDS_Shape* outShape = nullptr,
    std::string* error = nullptr,
    const ProgressCallback& progress = {});

} // namespace ShapeReader

} // namespace Mayo
