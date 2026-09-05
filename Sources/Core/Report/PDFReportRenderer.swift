import UIKit

/// Generador del PDF.
///
/// Trabaja en dos pasadas sobre la misma maquetación: la primera no dibuja
/// nada y solo cuenta en qué página cae cada sección y cuántas páginas salen en
/// total; la segunda pinta ya con el índice y los «página N de M» correctos.
/// La pasada en seco no cuesta memoria porque medir texto no crea contexto
/// gráfico alguno.
///
/// El PDF se escribe directamente a disco con `writePDF(to:)`, de modo que un
/// informe de sesenta páginas no se acumula nunca en memoria: cada página se
/// serializa y se suelta.
final class PDFReportRenderer {

    struct Input {
        var session: RecordingSession
        var report: AnalysisReport
        var transcript: Transcript?
        var includeTranscript: Bool
        var organization: String
        var limits: ResourceLimits
    }

    enum RenderError: LocalizedError {
        case writeFailed(String)

        var errorDescription: String? {
            switch self {
            case .writeFailed(let detail): return "No se pudo escribir el PDF. \(detail)"
            }
        }
    }

    @discardableResult
    func render(_ input: Input, to url: URL) throws -> URL {
        let sections = ReportComposer.sections(report: input.report,
                                               session: input.session,
                                               transcript: input.transcript,
                                               includeTranscript: input.includeTranscript,
                                               limits: input.limits)

        // Pasada 1: solo medidas.
        let dryRun = Run(input: input, sections: sections, pdfContext: nil, sectionPages: [:], totalPages: nil)
        dryRun.execute()

        // Pasada 2: dibujo real.
        let format = UIGraphicsPDFRendererFormat()
        format.documentInfo = [
            kCGPDFContextTitle as String: input.report.title,
            kCGPDFContextAuthor as String: input.organization.isEmpty ? "Graba y Análisis" : input.organization,
            kCGPDFContextCreator as String: "Graba y Análisis para iOS",
            kCGPDFContextSubject as String: input.report.subtitle
        ]
        let bounds = CGRect(origin: .zero, size: PDFTheme.pageSize)
        let renderer = UIGraphicsPDFRenderer(bounds: bounds, format: format)

        do {
            try renderer.writePDF(to: url) { context in
                let run = Run(input: input,
                              sections: sections,
                              pdfContext: context,
                              sectionPages: dryRun.sectionPages,
                              totalPages: dryRun.page)
                run.execute()
            }
        } catch {
            throw RenderError.writeFailed(error.localizedDescription)
        }
        return url
    }
}

// MARK: - Paginador

private final class Run {

    private let input: Input
    private let sections: [ReportComposer.Section]
    private let pdfContext: UIGraphicsPDFRendererContext?
    private let totalPages: Int?
    private var currentSectionTitle = ""

    typealias Input = PDFReportRenderer.Input

    var sectionPages: [String: Int]
    private(set) var page = 0
    private var cursor: CGFloat = 0

    private var draws: Bool { pdfContext != nil }
    private var cg: CGContext? { pdfContext?.cgContext }
    private var content: CGRect { PDFTheme.contentRect }
    private var remaining: CGFloat { content.maxY - cursor }

    init(input: Input,
         sections: [ReportComposer.Section],
         pdfContext: UIGraphicsPDFRendererContext?,
         sectionPages: [String: Int],
         totalPages: Int?) {
        self.input = input
        self.sections = sections
        self.pdfContext = pdfContext
        self.sectionPages = sectionPages
        self.totalPages = totalPages
    }

    func execute() {
        drawCoverPage()
        drawTableOfContents()
        for section in sections {
            startSection(section.title)
            for block in section.blocks {
                place(block)
            }
        }
    }

    // MARK: - Páginas

    private func newPage() {
        if draws { pdfContext?.beginPage() }
        page += 1
        cursor = content.minY
        drawRunningHead()
        drawFooter()
    }

    private func ensure(_ height: CGFloat) {
        if remaining < height { newPage() }
    }

    private func drawRunningHead() {
        guard page > 1, !currentSectionTitle.isEmpty else { return }
        PDFTextEngine.drawLine(currentSectionTitle,
                               font: PDFTheme.Font.caption,
                               color: PDFTheme.textMuted,
                               in: CGRect(x: content.minX, y: content.minY - 26, width: content.width * 0.7, height: 12),
                               draws: draws)
        PDFTextEngine.drawLine(input.report.title,
                               font: PDFTheme.Font.caption,
                               color: PDFTheme.textMuted,
                               alignment: .right,
                               in: CGRect(x: content.minX + content.width * 0.7,
                                          y: content.minY - 26,
                                          width: content.width * 0.3, height: 12),
                               draws: draws)
        if draws, let cg {
            cg.setStrokeColor(PDFTheme.panelBorder.cgColor)
            cg.setLineWidth(0.5)
            cg.move(to: CGPoint(x: content.minX, y: content.minY - 12))
            cg.addLine(to: CGPoint(x: content.maxX, y: content.minY - 12))
            cg.strokePath()
        }
    }

    private func drawFooter() {
        guard page > 1 else { return }
        let y = content.maxY + 22
        let label = totalPages.map { "Página \(page) de \($0)" } ?? "Página \(page)"
        PDFTextEngine.drawLine(label,
                               font: PDFTheme.Font.caption,
                               color: PDFTheme.textMuted,
                               alignment: .right,
                               in: CGRect(x: content.minX, y: y, width: content.width, height: 12),
                               draws: draws)
        PDFTextEngine.drawLine("Generado en el dispositivo · Graba y Análisis",
                               font: PDFTheme.Font.caption,
                               color: PDFTheme.textMuted,
                               in: CGRect(x: content.minX, y: y, width: content.width * 0.7, height: 12),
                               draws: draws)
    }

    private func startSection(_ title: String) {
        currentSectionTitle = title
        newPage()
        sectionPages[title] = page

        PDFTextEngine.drawLine(title,
                               font: PDFTheme.Font.sectionTitle,
                               color: PDFTheme.textPrimary,
                               in: CGRect(x: content.minX, y: cursor, width: content.width, height: 26),
                               draws: draws)
        cursor += 26
        if draws, let cg {
            cg.setFillColor(PDFTheme.series[0].cgColor)
            cg.fill(CGRect(x: content.minX, y: cursor, width: 46, height: 2.5))
        }
        cursor += 16
    }

    // MARK: - Portada

    private func drawCoverPage() {
        newPage()
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "es_ES")
        formatter.dateStyle = .full
        formatter.timeStyle = .short

        if draws, let cg {
            cg.setFillColor(PDFTheme.series[0].cgColor)
            cg.fill(CGRect(x: 0, y: 0, width: PDFTheme.pageSize.width, height: 8))
        }

        var y = content.minY + 40
        if !input.organization.isEmpty {
            PDFTextEngine.drawLine(input.organization.uppercased(),
                                   font: PDFTheme.Font.smallEmphasis,
                                   color: PDFTheme.series[0],
                                   in: CGRect(x: content.minX, y: y, width: content.width, height: 14),
                                   draws: draws)
            y += 20
        }
        PDFTextEngine.drawLine("INFORME DE SESIÓN",
                               font: PDFTheme.Font.smallEmphasis,
                               color: PDFTheme.textMuted,
                               in: CGRect(x: content.minX, y: y, width: content.width, height: 14),
                               draws: draws)
        y += 26

        let title = PDFTextEngine.attributed(input.report.title,
                                             font: PDFTheme.Font.coverTitle,
                                             color: PDFTheme.textPrimary,
                                             lineSpacing: 3)
        let titleHeight = PDFTextEngine.height(of: title, width: content.width)
        _ = PDFTextEngine.draw(title,
                               in: CGRect(x: content.minX, y: y, width: content.width, height: titleHeight),
                               draws: draws)
        y += titleHeight + 10

        if !input.report.subtitle.isEmpty {
            let subtitle = PDFTextEngine.attributed(input.report.subtitle,
                                                    font: PDFTheme.Font.coverSubtitle,
                                                    color: PDFTheme.textSecondary)
            let height = PDFTextEngine.height(of: subtitle, width: content.width)
            _ = PDFTextEngine.draw(subtitle,
                                   in: CGRect(x: content.minX, y: y, width: content.width, height: height),
                                   draws: draws)
            y += height + 20
        }

        if draws, let cg {
            cg.setStrokeColor(PDFTheme.panelBorder.cgColor)
            cg.setLineWidth(1)
            cg.move(to: CGPoint(x: content.minX, y: y))
            cg.addLine(to: CGPoint(x: content.maxX, y: y))
            cg.strokePath()
        }
        y += 22

        let facts: [(String, String)] = [
            ("Fecha", formatter.string(from: input.session.createdAt)),
            ("Duración", ReportComposer.formatDuration(input.session.duration)),
            ("Origen del audio", "Salida de audio del dispositivo"),
            ("Motor de análisis", input.report.provenance.engine)
        ]
        for (label, value) in facts where !value.isEmpty {
            PDFTextEngine.drawLine(label,
                                   font: PDFTheme.Font.small,
                                   color: PDFTheme.textMuted,
                                   in: CGRect(x: content.minX, y: y, width: 130, height: 14),
                                   draws: draws)
            PDFTextEngine.drawLine(value,
                                   font: PDFTheme.Font.bodyEmphasis,
                                   color: PDFTheme.textPrimary,
                                   in: CGRect(x: content.minX + 136, y: y, width: content.width - 136, height: 14),
                                   draws: draws)
            y += 20
        }

        // Resumen de una línea en la portada: lo primero que se lee.
        let firstParagraph = input.report.executiveSummary
            .components(separatedBy: "\n\n")
            .last(where: { !$0.isEmpty }) ?? ""
        if !firstParagraph.isEmpty {
            y += 16
            drawPanel(rect: CGRect(x: content.minX, y: y, width: content.width, height: 0), body: firstParagraph, at: &y)
        }

        PDFTextEngine.drawLine("Documento generado automáticamente a partir de la grabación. Contrastar con el audio original antes de usarlo como acta.",
                               font: PDFTheme.Font.caption,
                               color: PDFTheme.textMuted,
                               in: CGRect(x: content.minX, y: content.maxY - 12, width: content.width, height: 12),
                               draws: draws)
    }

    private func drawPanel(rect: CGRect, body: String, at y: inout CGFloat) {
        let inset: CGFloat = 14
        let attributed = PDFTextEngine.attributed(body,
                                                  font: PDFTheme.Font.body,
                                                  color: PDFTheme.textSecondary)
        let height = PDFTextEngine.height(of: attributed, width: rect.width - inset * 2) + inset * 2
        if draws, let cg {
            let frame = CGRect(x: rect.minX, y: y, width: rect.width, height: height)
            cg.setFillColor(PDFTheme.panel.cgColor)
            cg.setStrokeColor(PDFTheme.panelBorder.cgColor)
            cg.setLineWidth(0.75)
            let path = CGPath(roundedRect: frame, cornerWidth: 6, cornerHeight: 6, transform: nil)
            cg.addPath(path)
            cg.drawPath(using: .fillStroke)
        }
        _ = PDFTextEngine.draw(attributed,
                               in: CGRect(x: rect.minX + inset,
                                          y: y + inset,
                                          width: rect.width - inset * 2,
                                          height: height - inset * 2),
                               draws: draws)
        y += height
    }

    // MARK: - Índice

    private func drawTableOfContents() {
        currentSectionTitle = "Índice"
        newPage()
        PDFTextEngine.drawLine("Índice",
                               font: PDFTheme.Font.sectionTitle,
                               color: PDFTheme.textPrimary,
                               in: CGRect(x: content.minX, y: cursor, width: content.width, height: 26),
                               draws: draws)
        cursor += 34

        for section in sections {
            ensure(22)
            let pageLabel = sectionPages[section.title].map(String.init) ?? "—"
            PDFTextEngine.drawLine(section.title,
                                   font: PDFTheme.Font.body,
                                   color: PDFTheme.textPrimary,
                                   in: CGRect(x: content.minX, y: cursor, width: content.width - 40, height: 16),
                                   draws: draws)
            PDFTextEngine.drawLine(pageLabel,
                                   font: PDFTheme.Font.mono,
                                   color: PDFTheme.textSecondary,
                                   alignment: .right,
                                   in: CGRect(x: content.maxX - 36, y: cursor, width: 36, height: 16),
                                   draws: draws)
            if draws, let cg {
                let titleWidth = PDFTextEngine.lineWidth(section.title, font: PDFTheme.Font.body)
                let dotsStart = content.minX + titleWidth + 6
                let dotsEnd = content.maxX - 42
                if dotsEnd > dotsStart {
                    cg.setStrokeColor(PDFTheme.panelBorder.cgColor)
                    cg.setLineWidth(0.5)
                    cg.setLineDash(phase: 0, lengths: [1, 3])
                    cg.move(to: CGPoint(x: dotsStart, y: cursor + 11))
                    cg.addLine(to: CGPoint(x: dotsEnd, y: cursor + 11))
                    cg.strokePath()
                    cg.setLineDash(phase: 0, lengths: [])
                }
            }
            cursor += 21
        }
    }

    // MARK: - Colocación de bloques

    private func place(_ block: ReportBlock) {
        switch block {
        case .pageBreak:
            newPage()

        case .spacer(let height):
            cursor += height

        case .divider:
            ensure(14)
            if draws, let cg {
                cg.setStrokeColor(PDFTheme.panelBorder.cgColor)
                cg.setLineWidth(0.75)
                cg.move(to: CGPoint(x: content.minX, y: cursor + 6))
                cg.addLine(to: CGPoint(x: content.maxX, y: cursor + 6))
                cg.strokePath()
            }
            cursor += 14

        case .sectionTitle(let title):
            startSection(title)

        case .subheading(let text):
            ensure(30)
            PDFTextEngine.drawLine(text,
                                   font: PDFTheme.Font.subsectionTitle,
                                   color: PDFTheme.textPrimary,
                                   in: CGRect(x: content.minX, y: cursor, width: content.width, height: 18),
                                   draws: draws)
            cursor += 22

        case .paragraph(let text):
            placeFlowingText(text, font: PDFTheme.Font.body, color: PDFTheme.textPrimary, trailing: 9)

        case .lead(let text):
            placeFlowingText(text, font: PDFTheme.Font.body, color: PDFTheme.textSecondary, trailing: 12)

        case .caption(let text):
            placeFlowingText(text, font: PDFTheme.Font.caption, color: PDFTheme.textMuted, trailing: 8)

        case .bullets(let items):
            for item in items { placeListItem(marker: "•", text: item) }
            cursor += 4

        case .numbered(let items):
            for (index, item) in items.enumerated() {
                placeListItem(marker: "\(index + 1).", text: item)
            }
            cursor += 4

        case .keyValues(let pairs):
            for (label, value) in pairs {
                ensure(30)
                PDFTextEngine.drawLine(label,
                                       font: PDFTheme.Font.smallEmphasis,
                                       color: PDFTheme.series[0],
                                       in: CGRect(x: content.minX, y: cursor, width: content.width, height: 13),
                                       draws: draws)
                cursor += 14
                placeFlowingText(value,
                                 font: PDFTheme.Font.body,
                                 color: PDFTheme.textPrimary,
                                 trailing: 9,
                                 indent: 10)
            }

        case .quote(let text, let attribution):
            placeQuote(text: text, attribution: attribution)

        case .callout(let title, let body, let color):
            placeCallout(title: title, body: body, color: color)

        case .metricTiles(let tiles):
            placeMetricTiles(tiles)

        case .table(let spec):
            placeTable(spec)

        case .chart(let spec):
            placeChart(spec)

        case .tableOfContents:
            drawTableOfContents()
        }
    }

    private func placeFlowingText(_ text: String,
                                  font: UIFont,
                                  color: UIColor,
                                  trailing: CGFloat,
                                  indent: CGFloat = 0) {
        guard !text.isEmpty else { return }
        var pending: NSAttributedString? = PDFTextEngine.attributed(text, font: font, color: color, alignment: .justified)
        let width = content.width - indent

        while let attributed = pending {
            if remaining < font.lineHeight * 2 { newPage() }
            let rect = CGRect(x: content.minX + indent, y: cursor, width: width, height: remaining)
            let (used, rest) = PDFTextEngine.draw(attributed, in: rect, draws: draws)
            if used == 0 && rest != nil {
                newPage()
                continue
            }
            cursor += used
            pending = rest
            if pending != nil { newPage() }
        }
        cursor += trailing
    }

    private func placeListItem(marker: String, text: String) {
        let markerWidth: CGFloat = 20
        let width = content.width - markerWidth
        var pending: NSAttributedString? = PDFTextEngine.attributed(text,
                                                                    font: PDFTheme.Font.body,
                                                                    color: PDFTheme.textPrimary)
        var isFirstFragment = true

        while let attributed = pending {
            if remaining < PDFTheme.Font.body.lineHeight * 2 { newPage() }
            if isFirstFragment {
                PDFTextEngine.drawLine(marker,
                                       font: PDFTheme.Font.body,
                                       color: PDFTheme.series[0],
                                       in: CGRect(x: content.minX, y: cursor, width: markerWidth - 4, height: 14),
                                       draws: draws)
                isFirstFragment = false
            }
            let rect = CGRect(x: content.minX + markerWidth, y: cursor, width: width, height: remaining)
            let (used, rest) = PDFTextEngine.draw(attributed, in: rect, draws: draws)
            if used == 0 && rest != nil {
                newPage()
                continue
            }
            cursor += used
            pending = rest
            if pending != nil { newPage() }
        }
        cursor += 6
    }

    private func placeQuote(text: String, attribution: String) {
        let inset: CGFloat = 18
        let attributed = PDFTextEngine.attributed("«\(text)»",
                                                  font: PDFTheme.Font.quote,
                                                  color: PDFTheme.textPrimary)
        let width = content.width - inset
        let height = PDFTextEngine.height(of: attributed, width: width)
        ensure(height + 28)

        if draws, let cg {
            cg.setFillColor(PDFTheme.series[0].cgColor)
            cg.fill(CGRect(x: content.minX, y: cursor + 2, width: 2.5, height: height + 12))
        }
        _ = PDFTextEngine.draw(attributed,
                               in: CGRect(x: content.minX + inset, y: cursor, width: width, height: height),
                               draws: draws)
        cursor += height + 3
        PDFTextEngine.drawLine(attribution,
                               font: PDFTheme.Font.caption,
                               color: PDFTheme.textMuted,
                               in: CGRect(x: content.minX + inset, y: cursor, width: width, height: 12),
                               draws: draws)
        cursor += 22
    }

    private func placeCallout(title: String, body: String, color: UIColor) {
        let inset: CGFloat = 14
        let width = content.width - inset * 2
        let titleAttributed = PDFTextEngine.attributed(title,
                                                       font: PDFTheme.Font.bodyEmphasis,
                                                       color: PDFTheme.textPrimary)
        let bodyAttributed = PDFTextEngine.attributed(body,
                                                      font: PDFTheme.Font.small,
                                                      color: PDFTheme.textSecondary)
        let titleHeight = PDFTextEngine.height(of: titleAttributed, width: width)
        let bodyHeight = PDFTextEngine.height(of: bodyAttributed, width: width)
        let total = titleHeight + bodyHeight + inset * 2 + 4
        ensure(total + 8)

        if draws, let cg {
            let frame = CGRect(x: content.minX, y: cursor, width: content.width, height: total)
            cg.setFillColor(PDFTheme.panel.cgColor)
            cg.addPath(CGPath(roundedRect: frame, cornerWidth: 6, cornerHeight: 6, transform: nil))
            cg.fillPath()
            cg.setFillColor(color.cgColor)
            cg.addPath(CGPath(roundedRect: CGRect(x: frame.minX, y: frame.minY, width: 3, height: frame.height),
                              cornerWidth: 1.5, cornerHeight: 1.5, transform: nil))
            cg.fillPath()
        }
        _ = PDFTextEngine.draw(titleAttributed,
                               in: CGRect(x: content.minX + inset, y: cursor + inset, width: width, height: titleHeight),
                               draws: draws)
        _ = PDFTextEngine.draw(bodyAttributed,
                               in: CGRect(x: content.minX + inset,
                                          y: cursor + inset + titleHeight + 4,
                                          width: width, height: bodyHeight),
                               draws: draws)
        cursor += total + 10
    }

    private func placeMetricTiles(_ tiles: [MetricTile]) {
        guard !tiles.isEmpty else { return }
        let gap: CGFloat = 10
        let tileWidth = (content.width - gap * CGFloat(tiles.count - 1)) / CGFloat(tiles.count)
        let height: CGFloat = 62
        ensure(height + 8)

        for (index, tile) in tiles.enumerated() {
            let x = content.minX + CGFloat(index) * (tileWidth + gap)
            let frame = CGRect(x: x, y: cursor, width: tileWidth, height: height)
            if draws, let cg {
                cg.setFillColor(PDFTheme.panel.cgColor)
                cg.setStrokeColor(PDFTheme.panelBorder.cgColor)
                cg.setLineWidth(0.75)
                cg.addPath(CGPath(roundedRect: frame, cornerWidth: 6, cornerHeight: 6, transform: nil))
                cg.drawPath(using: .fillStroke)
            }
            PDFTextEngine.drawLine(tile.value,
                                   font: UIFont.monospacedDigitSystemFont(ofSize: 19, weight: .semibold),
                                   color: PDFTheme.textPrimary,
                                   in: CGRect(x: frame.minX + 10, y: frame.minY + 9, width: frame.width - 20, height: 24),
                                   draws: draws)
            PDFTextEngine.drawLine(tile.label,
                                   font: PDFTheme.Font.caption,
                                   color: PDFTheme.textSecondary,
                                   in: CGRect(x: frame.minX + 10, y: frame.minY + 33, width: frame.width - 20, height: 12),
                                   draws: draws)
            PDFTextEngine.drawLine(tile.footnote,
                                   font: PDFTheme.Font.caption,
                                   color: PDFTheme.textMuted,
                                   in: CGRect(x: frame.minX + 10, y: frame.minY + 45, width: frame.width - 20, height: 12),
                                   draws: draws)
        }
        cursor += height + 8
    }

    private func placeChart(_ spec: ChartSpec) {
        let height = spec.preferredHeight
        // Una gráfica partida entre dos páginas es ilegible: si no cabe entera,
        // pasa a la siguiente.
        if remaining < height { newPage() }
        let available = min(height, remaining)
        ChartRenderer.draw(spec,
                           in: CGRect(x: content.minX, y: cursor, width: content.width, height: available),
                           context: cg,
                           draws: draws)
        cursor += available + 10
    }

    // MARK: - Tablas

    private func placeTable(_ spec: TableSpec) {
        let widths = spec.columns.map { $0.widthFraction * content.width }
        let padding: CGFloat = 6
        let headerHeight: CGFloat = 22

        if !spec.title.isEmpty {
            ensure(34)
            PDFTextEngine.drawLine(spec.title,
                                   font: PDFTheme.Font.subsectionTitle,
                                   color: PDFTheme.textPrimary,
                                   in: CGRect(x: content.minX, y: cursor, width: content.width, height: 18),
                                   draws: draws)
            cursor += 22
        }

        func drawHeader() {
            if draws, let cg {
                cg.setFillColor(PDFTheme.panel.cgColor)
                cg.fill(CGRect(x: content.minX, y: cursor, width: content.width, height: headerHeight))
                cg.setStrokeColor(PDFTheme.panelBorder.cgColor)
                cg.setLineWidth(0.75)
                cg.move(to: CGPoint(x: content.minX, y: cursor + headerHeight))
                cg.addLine(to: CGPoint(x: content.maxX, y: cursor + headerHeight))
                cg.strokePath()
            }
            var x = content.minX
            for (index, column) in spec.columns.enumerated() {
                PDFTextEngine.drawLine(column.title,
                                       font: PDFTheme.Font.smallEmphasis,
                                       color: PDFTheme.textSecondary,
                                       alignment: column.alignment,
                                       in: CGRect(x: x + padding, y: cursor,
                                                  width: widths[index] - padding * 2, height: headerHeight),
                                       draws: draws)
                x += widths[index]
            }
            cursor += headerHeight
        }

        ensure(headerHeight + 40)
        drawHeader()

        for (rowIndex, row) in spec.rows.enumerated() {
            // Altura de la fila: la de la celda más alta con el texto ajustado
            // al ancho de su columna.
            var rowHeight: CGFloat = 0
            for (index, cell) in row.enumerated() where index < widths.count {
                let dotInset: CGFloat = cell.dotColor == nil ? 0 : 11
                let attributed = PDFTextEngine.attributed(cell.text,
                                                          font: PDFTheme.Font.small,
                                                          color: PDFTheme.textPrimary)
                let height = PDFTextEngine.height(of: attributed,
                                                  width: widths[index] - padding * 2 - dotInset)
                rowHeight = max(rowHeight, height)
            }
            rowHeight += padding * 2

            if remaining < rowHeight + 6 {
                newPage()
                drawHeader()
            }

            if draws, let cg {
                if rowIndex % 2 == 1 {
                    cg.setFillColor(PDFTheme.panel.withAlphaComponent(0.6).cgColor)
                    cg.fill(CGRect(x: content.minX, y: cursor, width: content.width, height: rowHeight))
                }
                cg.setStrokeColor(PDFTheme.grid.cgColor)
                cg.setLineWidth(0.5)
                cg.move(to: CGPoint(x: content.minX, y: cursor + rowHeight))
                cg.addLine(to: CGPoint(x: content.maxX, y: cursor + rowHeight))
                cg.strokePath()
            }

            var x = content.minX
            for (index, cell) in row.enumerated() where index < widths.count {
                var textX = x + padding
                var textWidth = widths[index] - padding * 2
                if let dotColor = cell.dotColor {
                    if draws, let cg {
                        cg.setFillColor(dotColor.cgColor)
                        cg.fillEllipse(in: CGRect(x: textX, y: cursor + padding + 2, width: 7, height: 7))
                    }
                    textX += 11
                    textWidth -= 11
                }
                let attributed = PDFTextEngine.attributed(cell.text,
                                                          font: PDFTheme.Font.small,
                                                          color: PDFTheme.textPrimary,
                                                          alignment: spec.columns[index].alignment)
                _ = PDFTextEngine.draw(attributed,
                                       in: CGRect(x: textX, y: cursor + padding,
                                                  width: max(10, textWidth), height: rowHeight - padding),
                                       draws: draws)
                x += widths[index]
            }
            cursor += rowHeight
        }

        if let note = spec.note {
            cursor += 5
            placeFlowingText(note, font: PDFTheme.Font.caption, color: PDFTheme.textMuted, trailing: 8)
        } else {
            cursor += 12
        }
    }
}
