import UIKit

/// Modelo intermedio del informe: una lista plana de bloques que el paginador
/// va colocando. Separar «qué se dice» de «cómo se dibuja» es lo que permite
/// que el paginador reparta el contenido entre páginas sin que el compositor
/// tenga que saber dónde acaba cada hoja.
enum ReportBlock {
    case pageBreak
    case sectionTitle(String)
    case subheading(String)
    case paragraph(String)
    case lead(String)
    case bullets([String])
    case numbered([String])
    case keyValues([(String, String)])
    case table(TableSpec)
    case chart(ChartSpec)
    case callout(title: String, body: String, color: UIColor)
    case quote(text: String, attribution: String)
    case metricTiles([MetricTile])
    case tableOfContents([String])
    case caption(String)
    case divider
    case spacer(CGFloat)
}

struct MetricTile {
    var value: String
    var label: String
    var footnote: String
}

struct TableColumn {
    var title: String
    var widthFraction: CGFloat
    var alignment: NSTextAlignment = .left
}

struct TableCell {
    var text: String
    /// Punto de color a la izquierda del texto. Siempre acompaña a una etiqueta
    /// escrita: el color no informa por sí solo.
    var dotColor: UIColor?

    init(_ text: String, dotColor: UIColor? = nil) {
        self.text = text
        self.dotColor = dotColor
    }
}

struct TableSpec {
    var title: String
    var columns: [TableColumn]
    var rows: [[TableCell]]
    var note: String?
}

/// Formas de gráfica que sabe dibujar el informe. Cada una responde a un
/// trabajo distinto: magnitud comparada, composición, evolución y posición en
/// una matriz.
enum ChartSpec {
    /// Barras horizontales: comparar magnitudes entre categorías.
    case horizontalBars(title: String,
                        subtitle: String,
                        items: [(label: String, value: Double, valueLabel: String)],
                        useSequentialRamp: Bool)
    /// Barras apiladas por estado: composición con la paleta de estado.
    case stackedBars(title: String,
                     subtitle: String,
                     categories: [(label: String, segments: [(name: String, value: Double, color: UIColor)])])
    /// Línea temporal de una sola serie.
    case line(title: String,
              subtitle: String,
              points: [(x: Double, y: Double)],
              yRange: ClosedRange<Double>,
              xAxisLabel: String,
              zeroBaseline: Bool)
    /// Matriz probabilidad × impacto para los riesgos.
    case riskMatrix(title: String, subtitle: String, risks: [Risk])
    /// Cronología de acontecimientos marcados sobre el eje de tiempo.
    case timeline(title: String, subtitle: String, events: [TimelineEvent], duration: TimeInterval)

    var preferredHeight: CGFloat {
        switch self {
        case .horizontalBars(_, _, let items, _):
            return 52 + CGFloat(items.count) * 22
        case .stackedBars(_, _, let categories):
            return 76 + CGFloat(categories.count) * 26
        case .line:
            return 190
        case .riskMatrix:
            return 250
        case .timeline:
            return 150
        }
    }

    var title: String {
        switch self {
        case .horizontalBars(let title, _, _, _): return title
        case .stackedBars(let title, _, _): return title
        case .line(let title, _, _, _, _, _): return title
        case .riskMatrix(let title, _, _): return title
        case .timeline(let title, _, _, _): return title
        }
    }
}
