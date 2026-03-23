import SwiftUI

// MARK: - Palette

enum Palette {
    static let blue       = adaptive(light: (0.56, 0.65, 0.75), dark: (0.62, 0.72, 0.82))
    static let rose       = adaptive(light: (0.76, 0.58, 0.63), dark: (0.82, 0.64, 0.69))
    static let sage       = adaptive(light: (0.60, 0.72, 0.68), dark: (0.66, 0.78, 0.74))
    static let terracotta = adaptive(light: (0.78, 0.62, 0.56), dark: (0.84, 0.68, 0.62))
    static let lavender   = adaptive(light: (0.72, 0.66, 0.76), dark: (0.78, 0.72, 0.82))
    static let sand       = adaptive(light: (0.78, 0.74, 0.60), dark: (0.84, 0.80, 0.66))

    static let quotaGood   = adaptive(light: (0.60, 0.72, 0.64), dark: (0.50, 0.78, 0.56))
    static let quotaWarn   = adaptive(light: (0.80, 0.72, 0.52), dark: (0.88, 0.80, 0.50))
    static let quotaDanger = adaptive(light: (0.78, 0.54, 0.54), dark: (0.90, 0.50, 0.50))

    static func adaptive(light: (CGFloat, CGFloat, CGFloat), dark: (CGFloat, CGFloat, CGFloat)) -> Color {
        Color(nsColor: NSColor(name: nil, dynamicProvider: { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            let c = isDark ? dark : light
            return NSColor(red: c.0, green: c.1, blue: c.2, alpha: 1.0)
        }))
    }
}
