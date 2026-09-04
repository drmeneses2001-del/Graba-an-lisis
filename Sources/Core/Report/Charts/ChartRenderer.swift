import UIKit

/// Dibujo vectorial de las gráficas del informe.
///
/// Todo se pinta con Core Graphics directamente en el contexto del PDF: no hay
/// mapas de bits intermedios, así que una página con cuatro gráficas cuesta
/// unos pocos kilobytes de memoria y sale nítida a cualquier tamaño de
/// impresión.
///
/// Convenciones que se respetan en todas ellas: un solo eje de valores, marcas
/// finas con el extremo de dato redondeado, 2 pt de separación entre rellenos
/// contiguos, rejilla discreta, etiquetas de valor escritas junto a la marca y
/// leyenda siempre que haya más de una serie.
enum ChartRenderer {

    static let markRadius: CGFloat = 4
    static let markGap: CGFloat = 2

    static func draw(_ spec: ChartSpec, in rect: CGRect, context: CGContext?, draws: Bool) {
        switch spec {
        case .horizontalBars(let title, let subtitle, let items, let sequential):
            drawHorizontalBars(title: title, subtitle: subtitle, items: items,
                               useSequential: sequential, rect: rect, context: context, draws: draws)
        case .stackedBars(let title, let subtitle, let categories):
            drawStackedBars(title: title, subtitle: subtitle, categories: categories,
                            rect: rect, context: context, draws: draws)
        case .line(let title, let subtitle, let points, let yRange, let xAxisLabel, let zeroBaseline):
            drawLine(title: title, subtitle: subtitle, points: points, yRange: yRange,
                     xAxisLabel: xAxisLabel, zeroBaseline: zeroBaseline,
                     rect: rect, context: context, draws: draws)
        case .riskMatrix(let title, let subtitle, let risks):
            drawRiskMatrix(title: title, subtitle: subtitle, risks: risks,
                           rect: rect, context: context, draws: draws)
        case .timeline(let title, let subtitle, let events, let duration):
            drawTimeline(title: title, subtitle: subtitle, events: events, duration: duration,
                         rect: rect, context: context, draws: draws)
        }
    }

    // MARK: - Cabecera común

    @discardableResult
    private static func drawHeader(title: String,
                                   subtitle: String,
                                   rect: CGRect,
                                   draws: Bool) -> CGFloat {
        var y = rect.minY
        if !title.isEmpty {
            PDFTextEngine.drawLine(title,
                                   font: PDFTheme.Font.chartTitle,
                                   color: PDFTheme.textPrimary,
                                   in: CGRect(x: rect.minX, y: y, width: rect.width, height: 15),
                                   draws: draws)
            y += 16
        }
        if !subtitle.isEmpty {
            PDFTextEngine.drawLine(subtitle,
                                   font: PDFTheme.Font.caption,
                                   color: PDFTheme.textSecondary,
                                   in: CGRect(x: rect.minX, y: y, width: rect.width, height: 11),
                                   draws: draws)
            y += 13
        }
        return y + 4
    }

    // MARK: - Barras horizontales

    private static func drawHorizontalBars(title: String,
                                           subtitle: String,
                                           items: [(label: String, value: Double, valueLabel: String)],
                                           useSequential: Bool,
                                           rect: CGRect,
                                           context: CGContext?,
                                           draws: Bool) {
        let top = drawHeader(title: title, subtitle: subtitle, rect: rect, draws: draws)
        guard !items.isEmpty else { return }

        let labelWidth = min(rect.width * 0.34, 150)
        let valueWidth: CGFloat = 52
        let plotX = rect.minX + labelWidth + 8
        let plotWidth = max(20, rect.width - labelWidth - valueWidth - 16)
        let maximum = max(items.map(\.value).max() ?? 1, 0.0001)
        let rowHeight: CGFloat = 22
        let barHeight: CGFloat = 12

        for (index, item) in items.enumerated() {
            let rowY = top + CGFloat(index) * rowHeight
            let barY = rowY + (rowHeight - barHeight) / 2 - markGap / 2

            PDFTextEngine.drawLine(item.label,
                                   font: PDFTheme.Font.chartLabel,
                                   color: PDFTheme.textSecondary,
                                   alignment: .right,
                                   in: CGRect(x: rect.minX, y: rowY, width: labelWidth, height: rowHeight),
                                   draws: draws)

            let fraction = item.value / maximum
            let barWidth = max(2, CGFloat(fraction) * plotWidth)
            let color = useSequential
                ? PDFTheme.sequentialStep(for: 0.35 + 0.65 * fraction)
                : PDFTheme.series[0]

            if draws, let context {
                // Carril de fondo: da referencia de la escala sin necesidad de eje.
                let track = CGRect(x: plotX, y: barY, width: plotWidth, height: barHeight)
                context.setFillColor(PDFTheme.grid.cgColor)
                context.addPath(roundedDataEnd(rect: track, radius: markRadius))
                context.fillPath()

                let bar = CGRect(x: plotX, y: barY, width: barWidth, height: barHeight)
                context.setFillColor(color.cgColor)
                context.addPath(roundedDataEnd(rect: bar, radius: markRadius))
                context.fillPath()
            }

            PDFTextEngine.drawLine(item.valueLabel,
                                   font: PDFTheme.Font.chartValue,
                                   color: PDFTheme.textPrimary,
                                   in: CGRect(x: plotX + plotWidth + 6, y: rowY, width: valueWidth, height: rowHeight),
                                   draws: draws)
        }
    }

    // MARK: - Barras apiladas

    private static func drawStackedBars(title: String,
                                        subtitle: String,
                                        categories: [(label: String, segments: [(name: String, value: Double, color: UIColor)])],
                                        rect: CGRect,
                                        context: CGContext?,
                                        draws: Bool) {
        var top = drawHeader(title: title, subtitle: subtitle, rect: rect, draws: draws)
        guard !categories.isEmpty else { return }

        // Leyenda: obligatoria en cuanto hay más de una serie, y con el nombre
        // escrito porque el color de estado nunca informa solo.
        var legendNames: [(String, UIColor)] = []
        for category in categories {
            for segment in category.segments where !legendNames.contains(where: { $0.0 == segment.name }) {
                legendNames.append((segment.name, segment.color))
            }
        }
        if legendNames.count > 1 {
            var x = rect.minX
            for (name, color) in legendNames {
                if draws, let context {
                    context.setFillColor(color.cgColor)
                    context.addPath(CGPath(roundedRect: CGRect(x: x, y: top + 2, width: 8, height: 8),
                                           cornerWidth: 2, cornerHeight: 2, transform: nil))
                    context.fillPath()
                }
                let width = PDFTextEngine.lineWidth(name, font: PDFTheme.Font.caption) + 4
                PDFTextEngine.drawLine(name,
                                       font: PDFTheme.Font.caption,
                                       color: PDFTheme.textSecondary,
                                       in: CGRect(x: x + 11, y: top, width: width, height: 12),
                                       draws: draws)
                x += 11 + width + 10
                if x > rect.maxX - 60 { break }
            }
            top += 18
        }

        let labelWidth = min(rect.width * 0.30, 130)
        let plotX = rect.minX + labelWidth + 8
        let plotWidth = max(20, rect.width - labelWidth - 50)
        let rowHeight: CGFloat = 26
        let barHeight: CGFloat = 14
        let maximum = max(categories.map { $0.segments.reduce(0) { $0 + $1.value } }.max() ?? 1, 0.0001)

        for (index, category) in categories.enumerated() {
            let rowY = top + CGFloat(index) * rowHeight
            let barY = rowY + (rowHeight - barHeight) / 2

            PDFTextEngine.drawLine(category.label,
                                   font: PDFTheme.Font.chartLabel,
                                   color: PDFTheme.textSecondary,
                                   alignment: .right,
                                   in: CGRect(x: rect.minX, y: rowY, width: labelWidth, height: rowHeight),
                                   draws: draws)

            var x = plotX
            let total = category.segments.reduce(0) { $0 + $1.value }
            for segment in category.segments where segment.value > 0 {
                let width = max(3, CGFloat(segment.value / maximum) * plotWidth)
                if draws, let context {
                    let isLast = segment.name == category.segments.last(where: { $0.value > 0 })?.name
                    let bar = CGRect(x: x, y: barY, width: max(1, width - markGap), height: barHeight)
                    context.setFillColor(segment.color.cgColor)
                    context.addPath(isLast
                                    ? roundedDataEnd(rect: bar, radius: markRadius)
                                    : CGPath(rect: bar, transform: nil))
                    context.fillPath()
                    // Recuento escrito dentro del segmento cuando hay sitio.
                    if width > 22 {
                        PDFTextEngine.drawLine("\(Int(segment.value))",
                                               font: PDFTheme.Font.chartValue,
                                               color: .white,
                                               alignment: .center,
                                               in: CGRect(x: x, y: barY, width: width - markGap, height: barHeight),
                                               draws: draws)
                    }
                }
                x += width
            }

            PDFTextEngine.drawLine("\(Int(total))",
                                   font: PDFTheme.Font.chartValue,
                                   color: PDFTheme.textPrimary,
                                   in: CGRect(x: plotX + plotWidth + 6, y: rowY, width: 40, height: rowHeight),
                                   draws: draws)
        }
    }

    // MARK: - Línea

    private static func drawLine(title: String,
                                 subtitle: String,
                                 points: [(x: Double, y: Double)],
                                 yRange: ClosedRange<Double>,
                                 xAxisLabel: String,
                                 zeroBaseline: Bool,
                                 rect: CGRect,
                                 context: CGContext?,
                                 draws: Bool) {
        let top = drawHeader(title: title, subtitle: subtitle, rect: rect, draws: draws)
        guard points.count > 1 else { return }

        let axisWidth: CGFloat = 34
        let bottomInset: CGFloat = 24
        let plot = CGRect(x: rect.minX + axisWidth,
                          y: top + 4,
                          width: rect.width - axisWidth - 8,
                          height: max(40, rect.maxY - top - bottomInset - 8))

        let xMin = points.map(\.x).min() ?? 0
        let xMax = max(points.map(\.x).max() ?? 1, xMin + 0.001)
        let ySpan = max(yRange.upperBound - yRange.lowerBound, 0.001)

        func locate(_ point: (x: Double, y: Double)) -> CGPoint {
            let px = plot.minX + CGFloat((point.x - xMin) / (xMax - xMin)) * plot.width
            let normalized = (point.y - yRange.lowerBound) / ySpan
            let py = plot.maxY - CGFloat(normalized) * plot.height
            return CGPoint(x: px, y: py)
        }

        if draws, let context {
            // Rejilla discreta: tres divisiones, sin marco.
            context.setStrokeColor(PDFTheme.grid.cgColor)
            context.setLineWidth(0.6)
            for step in 0...3 {
                let y = plot.minY + plot.height * CGFloat(step) / 3
                context.move(to: CGPoint(x: plot.minX, y: y))
                context.addLine(to: CGPoint(x: plot.maxX, y: y))
            }
            context.strokePath()

            if zeroBaseline && yRange.contains(0) {
                let zero = locate((x: xMin, y: 0)).y
                context.setStrokeColor(PDFTheme.axis.cgColor)
                context.setLineWidth(1)
                context.move(to: CGPoint(x: plot.minX, y: zero))
                context.addLine(to: CGPoint(x: plot.maxX, y: zero))
                context.strokePath()
            }

            context.setStrokeColor(PDFTheme.series[0].cgColor)
            context.setLineWidth(2)
            context.setLineJoin(.round)
            context.setLineCap(.round)
            for (index, point) in points.enumerated() {
                let location = locate(point)
                if index == 0 { context.move(to: location) } else { context.addLine(to: location) }
            }
            context.strokePath()

            // Marcadores solo en los extremos: etiquetar cada punto satura.
            if let maxPoint = points.max(by: { $0.y < $1.y }),
               let minPoint = points.min(by: { $0.y < $1.y }) {
                for (point, label) in [(maxPoint, "máx"), (minPoint, "mín")] {
                    let position = locate(point)
                    context.setFillColor(UIColor.white.cgColor)
                    context.fillEllipse(in: CGRect(x: position.x - 5, y: position.y - 5, width: 10, height: 10))
                    context.setFillColor(PDFTheme.series[0].cgColor)
                    context.fillEllipse(in: CGRect(x: position.x - 3.5, y: position.y - 3.5, width: 7, height: 7))
                    PDFTextEngine.drawLine("\(label) \(String(format: "%.2f", point.y))",
                                           font: PDFTheme.Font.caption,
                                           color: PDFTheme.textSecondary,
                                           in: CGRect(x: min(position.x + 7, plot.maxX - 54),
                                                      y: position.y - 12,
                                                      width: 54, height: 10),
                                           draws: draws)
                }
            }
        }

        // Escala vertical y eje temporal.
        for step in 0...3 {
            let value = yRange.upperBound - (yRange.upperBound - yRange.lowerBound) * Double(step) / 3
            let y = plot.minY + plot.height * CGFloat(step) / 3
            PDFTextEngine.drawLine(String(format: "%.1f", value),
                                   font: PDFTheme.Font.caption,
                                   color: PDFTheme.textMuted,
                                   alignment: .right,
                                   in: CGRect(x: rect.minX, y: y - 5, width: axisWidth - 6, height: 10),
                                   draws: draws)
        }
        PDFTextEngine.drawLine(xAxisLabel,
                               font: PDFTheme.Font.caption,
                               color: PDFTheme.textMuted,
                               alignment: .center,
                               in: CGRect(x: plot.minX, y: plot.maxY + 6, width: plot.width, height: 12),
                               draws: draws)
    }

    // MARK: - Matriz de riesgo

    private static func drawRiskMatrix(title: String,
                                       subtitle: String,
                                       risks: [Risk],
                                       rect: CGRect,
                                       context: CGContext?,
                                       draws: Bool) {
        let top = drawHeader(title: title, subtitle: subtitle, rect: rect, draws: draws)
        let levels = Severity.allCases
        let axisWidth: CGFloat = 58
        let bottomInset: CGFloat = 28
        let side = min(rect.width - axisWidth - 8, rect.maxY - top - bottomInset)
        guard side > 40 else { return }
        let cell = side / CGFloat(levels.count)
        let originX = rect.minX + axisWidth
        let originY = top + 2

        for row in 0..<levels.count {
            for column in 0..<levels.count {
                // Fila 0 arriba es la probabilidad más alta.
                let likelihood = levels[levels.count - 1 - row]
                let impact = levels[column]
                let score = likelihood.weight * impact.weight
                let frame = CGRect(x: originX + CGFloat(column) * cell + markGap / 2,
                                   y: originY + CGFloat(row) * cell + markGap / 2,
                                   width: cell - markGap,
                                   height: cell - markGap)
                if draws, let context {
                    context.setFillColor(PDFTheme.sequentialStep(for: score).withAlphaComponent(0.28).cgColor)
                    context.addPath(CGPath(roundedRect: frame, cornerWidth: 3, cornerHeight: 3, transform: nil))
                    context.fillPath()
                }
            }
        }

        for (index, risk) in risks.prefix(12).enumerated() {
            guard let row = levels.firstIndex(of: risk.likelihood),
                  let column = levels.firstIndex(of: risk.impact) else { continue }
            let centerX = originX + (CGFloat(column) + 0.5) * cell
            let centerY = originY + (CGFloat(levels.count - 1 - row) + 0.5) * cell
            // Se separan los que coinciden de casilla para que no se solapen.
            let offset = CGFloat(index % 3 - 1) * 9
            let point = CGPoint(x: centerX + offset, y: centerY + CGFloat((index / 3) % 3 - 1) * 9)
            if draws, let context {
                context.setFillColor(UIColor.white.cgColor)
                context.fillEllipse(in: CGRect(x: point.x - 8, y: point.y - 8, width: 16, height: 16))
                context.setFillColor(PDFTheme.color(for: risk.impact).cgColor)
                context.fillEllipse(in: CGRect(x: point.x - 7, y: point.y - 7, width: 14, height: 14))
                PDFTextEngine.drawLine("\(index + 1)",
                                       font: PDFTheme.Font.chartValue,
                                       color: .white,
                                       alignment: .center,
                                       in: CGRect(x: point.x - 7, y: point.y - 6, width: 14, height: 12),
                                       draws: draws)
            }
        }

        for (index, level) in levels.enumerated() {
            PDFTextEngine.drawLine(level.displayName,
                                   font: PDFTheme.Font.caption,
                                   color: PDFTheme.textMuted,
                                   alignment: .right,
                                   in: CGRect(x: rect.minX,
                                              y: originY + (CGFloat(levels.count - 1 - index) + 0.5) * cell - 5,
                                              width: axisWidth - 8, height: 10),
                                   draws: draws)
            PDFTextEngine.drawLine(level.displayName,
                                   font: PDFTheme.Font.caption,
                                   color: PDFTheme.textMuted,
                                   alignment: .center,
                                   in: CGRect(x: originX + CGFloat(index) * cell,
                                              y: originY + side + 4,
                                              width: cell, height: 10),
                                   draws: draws)
        }
        PDFTextEngine.drawLine("Impacto →",
                               font: PDFTheme.Font.caption,
                               color: PDFTheme.textSecondary,
                               alignment: .center,
                               in: CGRect(x: originX, y: originY + side + 15, width: side, height: 10),
                               draws: draws)
        PDFTextEngine.drawLine("↑ Probabilidad",
                               font: PDFTheme.Font.caption,
                               color: PDFTheme.textSecondary,
                               in: CGRect(x: rect.minX, y: originY - 12, width: axisWidth + 60, height: 10),
                               draws: draws)
    }

    // MARK: - Cronología

    private static func drawTimeline(title: String,
                                     subtitle: String,
                                     events: [TimelineEvent],
                                     duration: TimeInterval,
                                     rect: CGRect,
                                     context: CGContext?,
                                     draws: Bool) {
        let top = drawHeader(title: title, subtitle: subtitle, rect: rect, draws: draws)
        guard duration > 0 else { return }

        // Un carril por tipo: la identidad la lleva la etiqueta de la fila, no
        // el color, que aquí es uno solo para todos los marcadores.
        let kinds: [TimelineEvent.Kind] = [.topicShift, .proposal, .decision, .commitment, .critique, .risk]
        let laneLabelWidth: CGFloat = 92
        let laneHeight: CGFloat = 16
        let plotX = rect.minX + laneLabelWidth + 6
        let plotWidth = max(30, rect.width - laneLabelWidth - 14)

        for (index, kind) in kinds.enumerated() {
            let laneY = top + CGFloat(index) * laneHeight
            PDFTextEngine.drawLine(kind.displayName,
                                   font: PDFTheme.Font.caption,
                                   color: PDFTheme.textSecondary,
                                   alignment: .right,
                                   in: CGRect(x: rect.minX, y: laneY, width: laneLabelWidth, height: laneHeight),
                                   draws: draws)
            if draws, let context {
                context.setStrokeColor(PDFTheme.grid.cgColor)
                context.setLineWidth(1)
                context.move(to: CGPoint(x: plotX, y: laneY + laneHeight / 2))
                context.addLine(to: CGPoint(x: plotX + plotWidth, y: laneY + laneHeight / 2))
                context.strokePath()

                context.setFillColor(PDFTheme.series[0].cgColor)
                for event in events where event.kind == kind {
                    let fraction = min(1, max(0, event.timestamp / duration))
                    let x = plotX + CGFloat(fraction) * plotWidth
                    context.fillEllipse(in: CGRect(x: x - 3, y: laneY + laneHeight / 2 - 3, width: 6, height: 6))
                }
            }
        }

        let axisY = top + CGFloat(kinds.count) * laneHeight + 2
        if draws, let context {
            context.setStrokeColor(PDFTheme.axis.cgColor)
            context.setLineWidth(1)
            context.move(to: CGPoint(x: plotX, y: axisY))
            context.addLine(to: CGPoint(x: plotX + plotWidth, y: axisY))
            context.strokePath()
        }
        for step in 0...4 {
            let fraction = CGFloat(step) / 4
            let label = Transcript.timestamp(duration * Double(fraction))
            PDFTextEngine.drawLine(label,
                                   font: PDFTheme.Font.caption,
                                   color: PDFTheme.textMuted,
                                   alignment: step == 0 ? .left : (step == 4 ? .right : .center),
                                   in: CGRect(x: plotX + fraction * plotWidth - 24, y: axisY + 3, width: 48, height: 10),
                                   draws: draws)
        }
    }

    // MARK: - Utilidades

    /// Marca con el extremo del dato redondeado y la base pegada al eje, que es
    /// como se lee sin ambigüedad de dónde arranca la escala.
    static func roundedDataEnd(rect: CGRect, radius: CGFloat) -> CGPath {
        let radius = min(radius, rect.height / 2, rect.width / 2)
        let path = CGMutablePath()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - radius, y: rect.minY))
        path.addArc(tangent1End: CGPoint(x: rect.maxX, y: rect.minY),
                    tangent2End: CGPoint(x: rect.maxX, y: rect.midY),
                    radius: radius)
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - radius))
        path.addArc(tangent1End: CGPoint(x: rect.maxX, y: rect.maxY),
                    tangent2End: CGPoint(x: rect.midX, y: rect.maxY),
                    radius: radius)
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}
