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
	
	public var darker: Color {
		Color(r: max(0, r * 0.8), g: max(0, g * 0.8), b: max(0, b * 0.8), a: a)
	}
	
	public var lighter: Color {
		Color(r: min(1, r * 1.2), g: min(1, g * 1.2), b: min(1, b * 1.2), a: a)
	}
	
	public var highlight: Color {
		// Neonize: boost brightness and add a bright tint
		Color(
			r: min(1.0, r * 1.5 + 0.2),
			g: min(1.0, g * 1.5 + 0.2),
			b: min(1.0, b * 1.5 + 0.2),
			a: a
		)
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
    public static let yellow        = Color(r: 1.0,  g: 0.80, b: 0.0)
    public static let purple        = Color(r: 0.68, g: 0.32, b: 0.87)
    public static let cyan          = Color(r: 0.35, g: 0.78, b: 0.98)
    public static let magenta       = Color(r: 1.0,  g: 0.17, b: 0.33)
    public static let teal          = Color(r: 0.18, g: 0.67, b: 0.75)
    public static let indigo        = Color(r: 0.34, g: 0.33, b: 0.83)
    public static let white         = Color(r: 1.0,  g: 1.0,  b: 1.0)
    public static let black         = Color(r: 0.0,  g: 0.0,  b: 0.0)
    public static let gray          = Color(r: 0.55, g: 0.55, b: 0.57)
}
