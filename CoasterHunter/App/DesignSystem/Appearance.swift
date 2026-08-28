import SwiftUI

/// Light, dark, or whatever the phone says.
///
/// Three states, not two — and `system` is the default, so it is the case that
/// has to be right. Most people never open this setting.
public enum Appearance: String, CaseIterable, Identifiable, Sendable {
    case system, light, dark

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .system: return "System"
        case .light:  return "Light"
        case .dark:   return "Dark"
        }
    }

    public var symbolName: String {
        switch self {
        case .system: return "circle.lefthalf.filled"
        case .light:  return "sun.max"
        case .dark:   return "moon"
        }
    }

    /// `nil` hands control back to the OS, which is what `system` means.
    public var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light:  return .light
        case .dark:   return .dark
        }
    }
}

/// Reads and writes the rider's choice.
public final class AppearanceStore: ObservableObject {
    private static let key = "appearance"

    @Published public var appearance: Appearance {
        didSet { UserDefaults.standard.set(appearance.rawValue, forKey: Self.key) }
    }

    public init(defaults: UserDefaults = .standard) {
        let stored = defaults.string(forKey: Self.key)
        appearance = stored.flatMap(Appearance.init(rawValue:)) ?? .system
    }
}

public struct AppearancePicker: View {
    @Binding var selection: Appearance

    public init(selection: Binding<Appearance>) {
        self._selection = selection
    }

    public var body: some View {
        Picker("Appearance", selection: $selection) {
            ForEach(Appearance.allCases) { option in
                Label(option.title, systemImage: option.symbolName).tag(option)
            }
        }
        .pickerStyle(.segmented)
    }
}
