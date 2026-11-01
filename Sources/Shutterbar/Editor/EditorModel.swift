import Foundation
import ShutterbarCore

/// The editor's tool / style state and document. The toolbar (SwiftUI) and the canvas share the same object.
@MainActor
final class EditorModel: ObservableObject {
    enum Tool: String, CaseIterable, Identifiable {
        case arrow, rectangle, text, pixelate, number

        var id: String { rawValue }

        var title: String {
            switch self {
            case .arrow: "Arrow"
            case .rectangle: "Rectangle"
            case .text: "Text"
            case .pixelate: "Pixelate"
            case .number: "Number"
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

        /// Keyboard shortcut (single letter).
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
            case .thin: "Thin"
            case .medium: "Medium"
            case .thick: "Thick"
            }
        }

        /// Image pixels.
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
