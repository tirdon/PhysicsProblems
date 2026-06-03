import Foundation

struct Vec2: Equatable {
    var x: Double
    var y: Double

    static let zero = Vec2(x: 0, y: 0)

    var lengthSquared: Double {
        x * x + y * y
    }

    var length: Double {
        sqrt(lengthSquared)
    }

    var normalized: Vec2 {
        let value = length
        guard value > 0.000001 else { return .zero }
        return self / value
    }

    func distance(to other: Vec2) -> Double {
        (self - other).length
    }

    func dot(_ other: Vec2) -> Double {
        x * other.x + y * other.y
    }

    func rotated(by angle: Double) -> Vec2 {
        let c = cos(angle)
        let s = sin(angle)
        return Vec2(x: x * c - y * s, y: x * s + y * c)
    }
}

extension Vec2 {
    static func + (lhs: Vec2, rhs: Vec2) -> Vec2 {
        Vec2(x: lhs.x + rhs.x, y: lhs.y + rhs.y)
    }

    static func - (lhs: Vec2, rhs: Vec2) -> Vec2 {
        Vec2(x: lhs.x - rhs.x, y: lhs.y - rhs.y)
    }

    static prefix func - (value: Vec2) -> Vec2 {
        Vec2(x: -value.x, y: -value.y)
    }

    static func * (lhs: Vec2, rhs: Double) -> Vec2 {
        Vec2(x: lhs.x * rhs, y: lhs.y * rhs)
    }

    static func * (lhs: Double, rhs: Vec2) -> Vec2 {
        rhs * lhs
    }

    static func / (lhs: Vec2, rhs: Double) -> Vec2 {
        Vec2(x: lhs.x / rhs, y: lhs.y / rhs)
    }
}

struct Color: Equatable {
    var r: Double
    var g: Double
    var b: Double
    var a: Double

    static let background = Color(r: 0.08, g: 0.09, b: 0.11, a: 1)
    static let pivot = Color(r: 0.92, g: 0.94, b: 0.96, a: 1)
    static let string = Color(r: 0.95, g: 0.22, b: 0.18, a: 1)
    static let bob = Color(r: 0.12, g: 0.42, b: 0.92, a: 1)
    static let bobHighlight = Color(r: 0.32, g: 0.66, b: 1.0, a: 1)
    static let gravity = Color(r: 0.16, g: 0.72, b: 0.30, a: 1)
    static let tension = Color(r: 0.96, g: 0.58, b: 0.12, a: 1)

    func withOpacity(_ opacity: Double) -> Color {
        Color(r: r, g: g, b: b, a: a * opacity)
    }
}

func clamp(_ value: Double, min minimum: Double, max maximum: Double) -> Double {
    Swift.max(minimum, Swift.min(maximum, value))
}

func distanceFromPointToSegment(_ point: Vec2, _ start: Vec2, _ end: Vec2) -> Double {
    let segment = end - start
    let lengthSquared = segment.lengthSquared
    guard lengthSquared > 0.000001 else {
        return point.distance(to: start)
    }
    let t = clamp((point - start).dot(segment) / lengthSquared, min: 0, max: 1)
    let projection = start + segment * t
    return point.distance(to: projection)
}
