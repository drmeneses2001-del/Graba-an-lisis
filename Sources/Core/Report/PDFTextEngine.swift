import UIKit
import CoreText

/// Medición y dibujo de texto para el informe.
///
/// La medida y el corte se hacen con CoreText (sin contexto gráfico), y el
/// dibujo con UIKit. Así el paginador puede calcular cuánto texto cabe en una
/// página antes de empezar a pintar, que es lo que permite generar el índice
/// con números de página correctos en una primera pasada sin salida.
enum PDFTextEngine {

    static func attributed(_ text: String,
                           font: UIFont,
                           color: UIColor = PDFTheme.textPrimary,
                           alignment: NSTextAlignment = .natural,
                           lineSpacing: CGFloat = 2.5,
                           paragraphSpacing: CGFloat = 0,
                           kerning: CGFloat = 0) -> NSAttributedString {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = alignment
        paragraph.lineSpacing = lineSpacing
        paragraph.paragraphSpacing = paragraphSpacing
        paragraph.lineBreakMode = .byWordWrapping
        paragraph.hyphenationFactor = 0.9
        return NSAttributedString(string: text, attributes: [
            .font: font,
            .foregroundColor: color,
            .paragraphStyle: paragraph,
            .kern: kerning
        ])
    }

    static func height(of attributed: NSAttributedString, width: CGFloat) -> CGFloat {
        guard attributed.length > 0, width > 0 else { return 0 }
        let bounds = attributed.boundingRect(
            with: CGSize(width: width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            context: nil)
        return ceil(bounds.height)
    }

    /// Cuántos caracteres del texto caben en un rectángulo. Devuelve 0 si no
    /// cabe ni una línea completa.
    static func fittingLength(of attributed: NSAttributedString,
                              width: CGFloat,
                              height: CGFloat) -> Int {
        guard attributed.length > 0, width > 0, height > 0 else { return 0 }
        let framesetter = CTFramesetterCreateWithAttributedString(attributed)
        let path = CGPath(rect: CGRect(x: 0, y: 0, width: width, height: height), transform: nil)
        let frame = CTFramesetterCreateFrame(framesetter,
                                             CFRangeMake(0, 0),
                                             path,
                                             nil)
        let visible = CTFrameGetVisibleStringRange(frame)
        return visible.length
    }

    /// Dibuja el texto que quepa y devuelve lo que sobra, o `nil` si cabía todo.
    @discardableResult
    static func draw(_ attributed: NSAttributedString,
                     in rect: CGRect,
                     draws: Bool) -> (usedHeight: CGFloat, remainder: NSAttributedString?) {
        guard attributed.length > 0 else { return (0, nil) }
        let total = height(of: attributed, width: rect.width)

        if total <= rect.height {
            if draws { attributed.draw(with: rect, options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil) }
            return (total, nil)
        }

        let fitting = fittingLength(of: attributed, width: rect.width, height: rect.height)
        guard fitting > 0 else { return (0, attributed) }

        // Se corta en el último espacio para no partir palabras entre páginas.
        var cut = fitting
        let string = attributed.string as NSString
        let searchRange = NSRange(location: 0, length: min(fitting, string.length))
        let lastSpace = string.rangeOfCharacter(from: .whitespacesAndNewlines,
                                                options: .backwards,
                                                range: searchRange)
        if lastSpace.location != NSNotFound && lastSpace.location > fitting / 2 {
            cut = lastSpace.location + lastSpace.length
        }

        let head = attributed.attributedSubstring(from: NSRange(location: 0, length: cut))
        let tailLength = attributed.length - cut
        let tail = tailLength > 0
            ? attributed.attributedSubstring(from: NSRange(location: cut, length: tailLength))
            : nil

        if draws {
            head.draw(with: rect, options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil)
        }
        return (height(of: head, width: rect.width), tail)
    }

    /// Texto de una línea, recortado con puntos suspensivos si no cabe.
    static func drawLine(_ text: String,
                         font: UIFont,
                         color: UIColor,
                         alignment: NSTextAlignment = .left,
                         in rect: CGRect,
                         draws: Bool) {
        guard draws, !text.isEmpty else { return }
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = alignment
        paragraph.lineBreakMode = .byTruncatingTail
        let attributed = NSAttributedString(string: text, attributes: [
            .font: font,
            .foregroundColor: color,
            .paragraphStyle: paragraph
        ])
        let size = attributed.size()
        let y = rect.midY - size.height / 2
        attributed.draw(with: CGRect(x: rect.minX, y: y, width: rect.width, height: size.height),
                        options: [.usesLineFragmentOrigin],
                        context: nil)
    }

    static func lineWidth(_ text: String, font: UIFont) -> CGFloat {
        (text as NSString).size(withAttributes: [.font: font]).width
    }
}
