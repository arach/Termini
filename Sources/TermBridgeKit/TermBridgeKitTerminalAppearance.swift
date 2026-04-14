import Foundation

public enum TermBridgeKitTerminalColorScheme: String, CaseIterable, Codable, Identifiable, Sendable {
    case dark
    case light

    public var id: Self { self }
}

public struct TermBridgeKitTerminalColor: Hashable, Codable, Sendable {
    public var red: UInt8
    public var green: UInt8
    public var blue: UInt8

    public init(red: UInt8, green: UInt8, blue: UInt8) {
        self.red = red
        self.green = green
        self.blue = blue
    }

    public init(hex: UInt32) {
        self.red = UInt8((hex >> 16) & 0xFF)
        self.green = UInt8((hex >> 8) & 0xFF)
        self.blue = UInt8(hex & 0xFF)
    }

    var ghosttyRGBSequenceFragment: String {
        "rgb:\(ghosttyComponent(red))/\(ghosttyComponent(green))/\(ghosttyComponent(blue))"
    }

    private func ghosttyComponent(_ value: UInt8) -> String {
        String(format: "%04X", Int(value) * 257)
    }
}

public struct TermBridgeKitTerminalTheme: Hashable, Codable, Sendable, Identifiable {
    public var id: String
    public var name: String
    public var colorScheme: TermBridgeKitTerminalColorScheme
    public var background: TermBridgeKitTerminalColor
    public var foreground: TermBridgeKitTerminalColor
    public var cursor: TermBridgeKitTerminalColor
    public var selectionBackground: TermBridgeKitTerminalColor?
    public var selectionForeground: TermBridgeKitTerminalColor?
    public var ansiPalette: [TermBridgeKitTerminalColor]

    public init(
        id: String,
        name: String,
        colorScheme: TermBridgeKitTerminalColorScheme,
        background: TermBridgeKitTerminalColor,
        foreground: TermBridgeKitTerminalColor,
        cursor: TermBridgeKitTerminalColor,
        selectionBackground: TermBridgeKitTerminalColor? = nil,
        selectionForeground: TermBridgeKitTerminalColor? = nil,
        ansiPalette: [TermBridgeKitTerminalColor]
    ) {
        precondition(ansiPalette.count == 16, "Ghostty themes require a 16-color ANSI palette.")
        self.id = id
        self.name = name
        self.colorScheme = colorScheme
        self.background = background
        self.foreground = foreground
        self.cursor = cursor
        self.selectionBackground = selectionBackground
        self.selectionForeground = selectionForeground
        self.ansiPalette = ansiPalette
    }

    public static let midnightBloom = TermBridgeKitTerminalTheme(
        id: "midnight-bloom",
        name: "Midnight Bloom",
        colorScheme: .dark,
        background: .init(hex: 0x0D1321),
        foreground: .init(hex: 0xE6EDF7),
        cursor: .init(hex: 0xFF8A5B),
        selectionBackground: .init(hex: 0x243B53),
        selectionForeground: .init(hex: 0xF8FBFF),
        ansiPalette: [
            .init(hex: 0x172033), .init(hex: 0xFF6B6B), .init(hex: 0x8ED081), .init(hex: 0xFFD166),
            .init(hex: 0x65AFFF), .init(hex: 0xC792EA), .init(hex: 0x63D2FF), .init(hex: 0xD8E1F0),
            .init(hex: 0x41516E), .init(hex: 0xFF9C8F), .init(hex: 0xB5E48C), .init(hex: 0xFFE29A),
            .init(hex: 0x90C2FF), .init(hex: 0xE0AAFF), .init(hex: 0x9BE7FF), .init(hex: 0xFFFFFF)
        ]
    )

    public static let emberGlow = TermBridgeKitTerminalTheme(
        id: "ember-glow",
        name: "Ember Glow",
        colorScheme: .dark,
        background: .init(hex: 0x1A120F),
        foreground: .init(hex: 0xF7E7D7),
        cursor: .init(hex: 0xFFB36A),
        selectionBackground: .init(hex: 0x5D2E1E),
        selectionForeground: .init(hex: 0xFFF7ED),
        ansiPalette: [
            .init(hex: 0x241714), .init(hex: 0xE76F51), .init(hex: 0x7FB069), .init(hex: 0xF4A261),
            .init(hex: 0x4EA8DE), .init(hex: 0xB07BAC), .init(hex: 0x4FD1C5), .init(hex: 0xE9D8C7),
            .init(hex: 0x6C4A3D), .init(hex: 0xFF9770), .init(hex: 0x9AD576), .init(hex: 0xFFCC80),
            .init(hex: 0x74C0FC), .init(hex: 0xD0A5DB), .init(hex: 0x7BE0D6), .init(hex: 0xFFF5EB)
        ]
    )

    public static let jadeNight = TermBridgeKitTerminalTheme(
        id: "jade-night",
        name: "Jade Night",
        colorScheme: .dark,
        background: .init(hex: 0x071A1F),
        foreground: .init(hex: 0xDCF7F3),
        cursor: .init(hex: 0x6CE5B1),
        selectionBackground: .init(hex: 0x124D5F),
        selectionForeground: .init(hex: 0xF2FFFD),
        ansiPalette: [
            .init(hex: 0x10282E), .init(hex: 0xF07178), .init(hex: 0x6CE5B1), .init(hex: 0xF6C177),
            .init(hex: 0x5BC0EB), .init(hex: 0xC792EA), .init(hex: 0x4FD1C5), .init(hex: 0xC7ECE5),
            .init(hex: 0x35535A), .init(hex: 0xFF9EAA), .init(hex: 0x9CF3CB), .init(hex: 0xFFD7A5),
            .init(hex: 0x8ED8F8), .init(hex: 0xE0B8FF), .init(hex: 0x8AE8DD), .init(hex: 0xF7FFFE)
        ]
    )

    public static let paperLantern = TermBridgeKitTerminalTheme(
        id: "paper-lantern",
        name: "Paper Lantern",
        colorScheme: .light,
        background: .init(hex: 0xFFF8EC),
        foreground: .init(hex: 0x332A1F),
        cursor: .init(hex: 0xD94841),
        selectionBackground: .init(hex: 0xF7D7A8),
        selectionForeground: .init(hex: 0x23180F),
        ansiPalette: [
            .init(hex: 0x3F352A), .init(hex: 0xC8553D), .init(hex: 0x5D8A4A), .init(hex: 0xC9941E),
            .init(hex: 0x2F6DA3), .init(hex: 0x8C5E99), .init(hex: 0x287D8E), .init(hex: 0xE3D6C4),
            .init(hex: 0x7D6A58), .init(hex: 0xE07A5F), .init(hex: 0x7FB069), .init(hex: 0xE9C46A),
            .init(hex: 0x5A8FC2), .init(hex: 0xB084CC), .init(hex: 0x4FB0C6), .init(hex: 0xFFFDF8)
        ]
    )

    public static let blueprint = TermBridgeKitTerminalTheme(
        id: "blueprint",
        name: "Blueprint",
        colorScheme: .light,
        background: .init(hex: 0xF3F8FF),
        foreground: .init(hex: 0x16324F),
        cursor: .init(hex: 0x2563EB),
        selectionBackground: .init(hex: 0xCFE1FF),
        selectionForeground: .init(hex: 0x0F2236),
        ansiPalette: [
            .init(hex: 0x23384D), .init(hex: 0xD94F4F), .init(hex: 0x2F855A), .init(hex: 0xC48A12),
            .init(hex: 0x2563EB), .init(hex: 0x8B5CF6), .init(hex: 0x0F9FB6), .init(hex: 0xDCE7F5),
            .init(hex: 0x5C7690), .init(hex: 0xF97373), .init(hex: 0x4EB37D), .init(hex: 0xE8B948),
            .init(hex: 0x5B8CFF), .init(hex: 0xB692FF), .init(hex: 0x59C6D9), .init(hex: 0xFFFFFF)
        ]
    )

    public static let presets: [TermBridgeKitTerminalTheme] = [
        .midnightBloom,
        .emberGlow,
        .jadeNight,
        .paperLantern,
        .blueprint
    ]

    var applyEscapeSequence: String {
        var commands = [
            osc(command: 10, color: foreground),
            osc(command: 11, color: background),
            osc(command: 12, color: cursor)
        ]

        if let selectionBackground {
            commands.append(osc(command: 17, color: selectionBackground))
        }

        if let selectionForeground {
            commands.append(osc(command: 19, color: selectionForeground))
        }

        commands.append(contentsOf: ansiPalette.enumerated().map { index, color in
            "\u{1B}]4;\(index);\(color.ghosttyRGBSequenceFragment)\u{07}"
        })

        return commands.joined()
    }

    static var resetEscapeSequence: String {
        [
            "\u{1B}]104\u{07}",
            "\u{1B}]110\u{07}",
            "\u{1B}]111\u{07}",
            "\u{1B}]112\u{07}",
            "\u{1B}]117\u{07}",
            "\u{1B}]119\u{07}"
        ].joined()
    }

    private func osc(command: Int, color: TermBridgeKitTerminalColor) -> String {
        "\u{1B}]\(command);\(color.ghosttyRGBSequenceFragment)\u{07}"
    }
}

public struct TermBridgeKitTerminalAppearance: Hashable, Codable, Sendable {
    public var theme: TermBridgeKitTerminalTheme?
    public var fontSize: Double?

    public init(
        theme: TermBridgeKitTerminalTheme? = nil,
        fontSize: Double? = nil
    ) {
        self.theme = theme
        self.fontSize = fontSize
    }

    public static let `default` = TermBridgeKitTerminalAppearance()
}
