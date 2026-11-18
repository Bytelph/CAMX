#pragma once

#include "Graphics/graphics_shape_reader.h"   // Mayo::ShapeFormat 与 shapeFormatFromFileName()

#include <TopoDS_Shape.hxx>

#include <string>

// OpenCASCADE 几何 → CAD 文件（Qt-free）：供 GUI、MCP server、headless/batch 复用。

namespace Mayo {
namespace ShapeWriter {

// 把 shape 导出为指定格式。失败返回 false，并在 error（若非空）中写入原因。
bool write(const TopoDS_Shape& shape, const std::string& filePath, ShapeFormat format,
           std::string* error = nullptr);

// 自动按扩展名识别格式。
bool write(const TopoDS_Shape& shape, const std::string& filePath, std::string* error = nullptr);

} // namespace ShapeWriter
} // namespace Mayo
