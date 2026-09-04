import UIKit

/// Paleta y tipografía del informe.
///
/// Los colores de las gráficas salen de una paleta validada para daltonismo: se
/// asignan por orden fijo, nunca en ciclo, y las series que llevan color llevan
/// además su etiqueta escrita al lado, de modo que el color nunca es el único
/// portador de la información. El informe se imprime en blanco y negro sin
/// perder sentido.
enum PDFTheme {

    // MARK: Superficies y texto

    static let page = UIColor.white
    static let panel = UIColor(hex: 0xFCFCFB)
    static let panelBorder = UIColor(hex: 0xE6E5E1)
    static let grid = UIColor(hex: 0xEDECE8)
    static let axis = UIColor(hex: 0xC9C8C2)
    static let textPrimary = UIColor(hex: 0x0B0B0B)
    static let textSecondary = UIColor(hex: 0x52514E)
    static let textMuted = UIColor(hex: 0x7A7975)

    // MARK: Series categóricas (orden fijo)

    /// Máximo tres series con color en una misma gráfica: a partir de ahí los
    /// pares dejan de ser distinguibles con daltonismo y hay que agrupar.
    static let series: [UIColor] = [
        UIColor(hex: 0x2A78D6),   // azul
        UIColor(hex: 0xEB6834),   // naranja
        UIColor(hex: 0x1BAF7A)    // aguamarina
    ]

    static let maxColorSeries = 3

    /// Rampa secuencial de un solo tono para codificar magnitud. El paso más
    /// claro respeta el mínimo de contraste sobre papel blanco.
    static let sequential: [UIColor] = [
        UIColor(hex: 0x86B6EF),
        UIColor(hex: 0x6DA7EC),
        UIColor(hex: 0x5598E7),
        UIColor(hex: 0x3987E5),
        UIColor(hex: 0x2A78D6),
        UIColor(hex: 0x256ABF),
        UIColor(hex: 0x1C5CAB),
        UIColor(hex: 0x184F95),
        UIColor(hex: 0x104281),
        UIColor(hex: 0x0D366B)
    ]

    /// Colores de estado, reservados: nunca se usan como «serie 4».
    enum Status {
        static let good = UIColor(hex: 0x0CA30C)
        static let warning = UIColor(hex: 0xFAB219)
        static let serious = UIColor(hex: 0xEC835A)
        static let critical = UIColor(hex: 0xD03B3B)
    }

    static func color(for severity: Severity) -> UIColor {
        switch severity {
        case .low: return Status.good
        case .medium: return Status.warning
        case .high: return Status.serious
        case .critical: return Status.critical
        }
    }

    static func color(for status: CommitmentStatus) -> UIColor {
        switch status {
        case .agreed: return Status.good
        case .conditional: return Status.warning
        case .pending: return Status.serious
        case .atRisk: return Status.critical
        }
    }

    static func sequentialStep(for fraction: Double) -> UIColor {
        let clamped = max(0, min(1, fraction))
        let index = Int((clamped * Double(sequential.count - 1)).rounded())
        return sequential[index]
    }

    // MARK: Tipografía

    enum Font {
        static let coverTitle = UIFont.systemFont(ofSize: 30, weight: .bold)
        static let coverSubtitle = UIFont.systemFont(ofSize: 15, weight: .regular)
        static let sectionTitle = UIFont.systemFont(ofSize: 19, weight: .semibold)
        static let subsectionTitle = UIFont.systemFont(ofSize: 13, weight: .semibold)
        static let body = UIFont.systemFont(ofSize: 10.5, weight: .regular)
        static let bodyEmphasis = UIFont.systemFont(ofSize: 10.5, weight: .semibold)
        static let small = UIFont.systemFont(ofSize: 9, weight: .regular)
        static let smallEmphasis = UIFont.systemFont(ofSize: 9, weight: .semibold)
        static let caption = UIFont.systemFont(ofSize: 8, weight: .regular)
        static let quote = UIFont.italicSystemFont(ofSize: 12)
        static let mono = UIFont.monospacedDigitSystemFont(ofSize: 9, weight: .regular)
        static let chartTitle = UIFont.systemFont(ofSize: 11.5, weight: .semibold)
        static let chartLabel = UIFont.systemFont(ofSize: 8.5, weight: .regular)
        static let chartValue = UIFont.monospacedDigitSystemFont(ofSize: 8.5, weight: .semibold)
    }

    // MARK: Geometría

    /// A4 en puntos.
    static let pageSize = CGSize(width: 595.28, height: 841.89)
    static let marginLeft: CGFloat = 56
    static let marginRight: CGFloat = 56
    static let marginTop: CGFloat = 62
    static let marginBottom: CGFloat = 58

    static var contentWidth: CGFloat {
        pageSize.width - marginLeft - marginRight
    }

    static var contentRect: CGRect {
        CGRect(x: marginLeft,
               y: marginTop,
               width: contentWidth,
               height: pageSize.height - marginTop - marginBottom)
    }
}

extension UIColor {
    convenience init(hex: UInt32) {
        self.init(red: CGFloat((hex >> 16) & 0xFF) / 255.0,
                  green: CGFloat((hex >> 8) & 0xFF) / 255.0,
                  blue: CGFloat(hex & 0xFF) / 255.0,
                  alpha: 1.0)
    }
}
