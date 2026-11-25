import QtQuick
import QtQuick.Shapes
import CAMX.Theme 1.0

// 简化刀具示意图：灰色刀柄 + 彩色刀头，按 kind 选择轮廓。
// 设计坐标 32×48（与 ToolIcon 的 24×24 设计稿同理），再缩放到实际尺寸。
Item {
    id: root
    property string kind: "flat"
    property real iconWidth: 26
    property real iconHeight: 40

    width: iconWidth
    height: iconHeight

    // body = 刀柄 / 夹持部分（灰），tip = 刀头（按刀具类型着色），detail = 细节线条
    readonly property var spec: {
        switch (kind) {
        // —— 铣刀（黄色刀头）——
        case "flat":
            // 平底立铣刀
            return { body: "M10,2H22V22H10Z", tip: "M6,22H26V42H6Z", tipColor: "#f2c41c" }
        case "ball":
            // 球头立铣刀
            return { body: "M10,2H22V22H10Z", tip: "M6,22H26V33A10,10 0 0 1 6,33Z", tipColor: "#f2c41c" }
        case "bull":
            // 圆鼻立铣刀
            return { body: "M10,2H22V22H10Z", tip: "M6,22H26V38Q26,42 22,42H10Q6,42 6,38Z", tipColor: "#f2c41c" }
        case "taper":
            // 锥度立铣刀
            return { body: "M10,2H22V22H10Z", tip: "M9,22H23L26,42H6Z", tipColor: "#f2c41c" }
        case "chamfer":
            // 倒角铣刀
            return { body: "M10,2H22V22H10Z", tip: "M7,22H25L22,42H10Z", tipColor: "#f2c41c" }
        case "drill":
            // 钻头
            return { body: "M10,2H22V22H10Z", tip: "M7,22H25V33L16,45L7,33Z", tipColor: "#f2c41c" }
        case "spot":
            // 定心钻
            return { body: "M10,2H22V22H10Z", tip: "M10,22H22V36L16,43L10,36Z", tipColor: "#f2c41c" }
        case "dovetail":
            // 燕尾铣刀
            return { body: "M10,2H22V22H10Z", tip: "M12,22H20L26,42H6Z", tipColor: "#f2c41c" }
        case "tslot":
            // T 型槽铣刀
            return { body: "M10,2H22V30H10Z", tip: "M13,30H19V33H26V42H6V33H13Z", tipColor: "#f2c41c" }
        case "thread":
            // 螺纹铣刀
            return { body: "M10,2H22V22H10Z", tip: "M8,22H24V42H8Z", tipColor: "#f2c41c",
                     detail: "M8,26L24,30M8,32L24,36M8,38L24,42", detailColor: "#b39000", detailWidth: 0.9 }
        case "disc":
            // 锯片铣刀
            return { body: "M10,2H22V23H10Z", tip: "M16,22A10,10 0 1 1 16,42A10,10 0 1 1 16,22Z", tipColor: "#f2c41c" }

        // —— 车刀（橙色刀片 + 灰色刀杆）——
        case "insert_diamond":
            // 外圆车刀（菱形刀片）
            return { body: "M18,36H32V42H18Z", tip: "M14,26L25,34L14,42L3,34Z", tipColor: "#e8912b" }
        case "insert_square":
            // 内孔车刀（方形刀片）
            return { body: "M18,36H32V42H18Z", tip: "M5,26H23V42H5Z", tipColor: "#e8912b" }
        case "insert_triangle":
            // 切槽刀（三角刀片）
            return { body: "M18,36H32V42H18Z", tip: "M14,25L25,42H3Z", tipColor: "#e8912b" }
        case "insert_round":
            // 螺纹车刀（圆形刀片）
            return { body: "M18,36H32V42H18Z", tip: "M14,26A8,8 0 1 1 14,42A8,8 0 1 1 14,26Z", tipColor: "#e8912b" }

        // —— 探针（粉色测头）——
        case "probe_ball":
            // 球形探针
            return { body: "M14,3H18V27H14Z", tip: "M16,26A7,7 0 1 1 16,40A7,7 0 1 1 16,26Z", tipColor: "#e0559b" }
        case "probe_star":
            // 星形探针
            return { body: "M14,3H18V25H14Z", tip: "M16,27A3.5,3.5 0 1 1 16,34A3.5,3.5 0 1 1 16,27Z", tipColor: "#e0559b",
                     detail: "M16,30.5L6,41M16,30.5L26,41M16,30.5V44", detailColor: "#e0559b", detailWidth: 2 }
        case "probe_cyl":
            // 圆柱探针
            return { body: "M14,3H18V26H14Z", tip: "M11,26H21V39A5,5 0 0 1 11,39Z", tipColor: "#e0559b" }
        case "renishaw":
            // 雷尼绍探头：测头模块 + 红宝石测针
            return { body: "M9,3H23V20Q23,23 20,23H12Q9,23 9,20Z", tip: "M14,23H18V31H14Z M16,31A5.5,5.5 0 1 1 16,42A5.5,5.5 0 1 1 16,31Z",
                     tipColor: "#e0417f" }

        // —— 刀柄（钢蓝色）——
        case "holder_param":
            // 参数化刀柄：法兰 + 锥柄 + 夹头螺母
            return { body: "M5,3H27V11H22L18,30H14L10,11H5Z", tip: "M13,30H19V38H13Z", tipColor: "#8fa0b5",
                     detail: "M5,11H27", detailColor: "#8b929a", detailWidth: 1 }
        case "holder_coord":
            // 坐标化刀柄：刀柄 + 坐标十字
            return { body: "M5,3H27V11H22L18,30H14L10,11H5Z", tip: "M13,30H19V38H13Z", tipColor: "#8fa0b5",
                     detail: "M16,14V44M6,24H26", detailColor: "#d97706", detailWidth: 1.2 }

        // —— 激光（红色光束）——
        case "laser":
            // 激光切割头
            return { body: "M11,3H21V26H11Z", tip: "M14,27H18L24,46H8Z", tipColor: "#e5484d" }
        case "laser2":
            // 激光熔覆头
            return { body: "M11,3H21V23H11Z", tip: "M12,24H20V46H12Z", tipColor: "#e5484d" }

        default:
            return { body: "", tip: "", tipColor: "#f2c41c", detail: "" }
        }
    }

    Shape {
        anchors.fill: parent

        // 刀柄 / 夹持部分
        ShapePath {
            fillColor: "#b6bcc4"
            strokeColor: "#8b929a"
            strokeWidth: 0.8
            scale: Qt.size(root.width / 32, root.height / 48)
            PathSvg { path: root.spec.body }
        }

        // 刀头
        ShapePath {
            fillColor: root.spec.tipColor
            strokeColor: Qt.darker(root.spec.tipColor, 1.3)
            strokeWidth: 0.8
            scale: Qt.size(root.width / 32, root.height / 48)
            PathSvg { path: root.spec.tip }
        }

        // 细节线条（螺纹、探针支臂等）
        ShapePath {
            fillColor: "transparent"
            strokeColor: root.spec.detail ? (root.spec.detailColor || "#8b929a") : "transparent"
            strokeWidth: root.spec.detailWidth || 1.2
            capStyle: ShapePath.RoundCap
            joinStyle: ShapePath.RoundJoin
            scale: Qt.size(root.width / 32, root.height / 48)
            PathSvg { path: root.spec.detail || "" }
        }
    }
}
