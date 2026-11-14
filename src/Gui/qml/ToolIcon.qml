import QtQuick
import QtQuick.Shapes
import CXCAM.Theme 1.0

// 线性矢量图标（保存/撤销/重做等）。
// 用 Shape + PathSvg 直接绘制 SVG 路径，无需外部图片资源；图标按 24×24 设计稿绘制，再缩放到 size。
Item {
    id: root

    property string name: ""
    property color color: Theme.textDim
    property real size: 18

    width: size
    height: size

    // 24×24 设计稿下的 SVG 路径（Material Design Icons，Apache-2.0）
    readonly property string pathData: {
        switch (name) {
        case "save":
            // 软盘：外壳 + 写保护窗 + 标签
            return "M17 3H5c-1.11 0-2 .9-2 2v14c0 1.1.89 2 2 2h14c1.1 0 2-.9 2-2V7l-4-4zm-5 16c-1.66 0-3-1.34-3-3s1.34-3 3-3 3 1.34 3 3-1.34 3-3 3zm3-10H5V5h10v4z"
        case "undo":
            // 逆时针回退箭头
            return "M12.5 8c-2.65 0-5.05.99-6.9 2.6L2 7v9h9l-3.62-3.62c1.39-1.16 3.16-1.88 5.12-1.88 3.54 0 6.55 2.31 7.6 5.5l2.37-.78C21.08 11.03 17.15 8 12.5 8z"
        case "redo":
            // 顺时针重做箭头
            return "M18.4 10.6C16.55 8.99 14.15 8 11.5 8c-4.65 0-8.58 3.03-9.96 7.22L3.9 16c1.05-3.19 4.05-5.5 7.6-5.5 1.95 0 3.73.72 5.12 1.88L13 16h9V7l-3.6 3.6z"
        case "search":
            // 放大镜
            return "M9.5,3A6.5,6.5 0 0,1 16,9.5C16,11.11 15.41,12.59 14.44,13.73L14.71,14H15.5L20.5,19L19,20.5L14,15.5V14.71L13.73,14.44C12.59,15.41 11.11,16 9.5,16A6.5,6.5 0 0,1 3,9.5A6.5,6.5 0 0,1 9.5,3M9.5,5C7,5 5,7 5,9.5C5,12 7,14 9.5,14C12,14 14,12 14,9.5C14,7 12,5 9.5,5Z"
        default:
            return ""
        }
    }

    Shape {
        anchors.fill: parent

        ShapePath {
            scale: Qt.size(root.size / 24, root.size / 24)
            fillColor: "transparent"
            strokeColor: root.color
            strokeWidth: 2
            capStyle: ShapePath.RoundCap
            joinStyle: ShapePath.RoundJoin
            PathSvg { path: root.pathData }
        }
    }
}
