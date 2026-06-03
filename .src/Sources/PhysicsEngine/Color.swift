//
//  Color.swift
//  PhysicsEngine
//

// MARK: - Color

public struct Color: Equatable, Sendable {
    public var r: Float
    public var g: Float
    public var b: Float
    public var a: Float

    public init(r: Float, g: Float, b: Float, a: Float = 1) {
        self.r = r
        self.g = g
        self.b = b
        self.a = a
    }

    public func withOpacity(_ opacity: Float) -> Color {
        Color(r: r, g: g, b: b, a: a * opacity)
    }

    // MARK: Named Presets

    public static let background    = Color(r: 0.08, g: 0.09, b: 0.11)
    public static let pivot         = Color(r: 0.92, g: 0.94, b: 0.96)
    public static let string        = Color(r: 0.95, g: 0.22, b: 0.18)
    public static let bob           = Color(r: 0.12, g: 0.42, b: 0.92)
    public static let bobHighlight  = Color(r: 0.32, g: 0.66, b: 1.0)
    public static let gravity       = Color(r: 0.16, g: 0.72, b: 0.30)
    public static let tension       = Color(r: 0.96, g: 0.58, b: 0.12)

    public static let red           = Color(r: 1.0,  g: 0.23, b: 0.19)
    public static let green         = Color(r: 0.30, g: 0.85, b: 0.39)
    public static let blue          = Color(r: 0.0,  g: 0.48, b: 1.0)
    public static let orange        = Color(r: 1.0,  g: 0.58, b: 0.0)
    public static let white         = Color(r: 1.0,  g: 1.0,  b: 1.0)
}
