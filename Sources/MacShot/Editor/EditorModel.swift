import Foundation
import MacShotCore

/// Editörün araç / stil durumu ve belge. Toolbar (SwiftUI) ile canvas aynı nesneyi paylaşır.
@MainActor
final class EditorModel: ObservableObject {
    enum Tool: String, CaseIterable, Identifiable {
        case arrow, rectangle, text, pixelate, number

        var id: String { rawValue }

        var title: String {
            switch self {
            case .arrow: "Ok"
            case .rectangle: "Kutu"
            case .text: "Metin"
            case .pixelate: "Bulanık"
            case .number: "Numara"
            }
        }

        var symbol: String {
            switch self {
            case .arrow: "arrow.up.right"
            case .rectangle: "rectangle"
            case .text: "textformat"
            case .pixelate: "mosaic"
            case .number: "1.circle"
            }
        }

        /// Klavye kısayolu (tek harf).
        var key: Character {
            switch self {
            case .arrow: "a"
            case .rectangle: "r"
            case .text: "t"
            case .pixelate: "b"
            case .number: "n"
            }
        }
    }

    enum Width: CaseIterable, Identifiable {
        case thin, medium, thick

        var id: Self { self }

        var title: String {
            switch self {
            case .thin: "İnce"
            case .medium: "Orta"
            case .thick: "Kalın"
            }
        }

        /// Görüntü pikseli.
        var pixels: CGFloat {
            switch self {
            case .thin: 3
            case .medium: 6
            case .thick: 12
            }
        }
    }

    static let palette: [Annotation.Color] = [.red, .yellow, .green, .blue, .black, .white]

    @Published var tool: Tool = .arrow
    @Published var color: Annotation.Color = .red
    @Published var width: Width = .medium
    @Published private(set) var document = AnnotationDocument()

    func add(_ shape: Annotation.Shape) {
        document.add(Annotation(shape, color: color, lineWidth: width.pixels))
    }

    func undo() { document.undo() }
    func redo() { document.redo() }
    func clear() { document.removeAll() }
}
