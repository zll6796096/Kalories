import SwiftUI

@main
struct KaloriesApp: App {
    private enum BootstrapState {
        case ready(AppEnvironment)
        case invalidConfiguration(AppLocalizer)
    }

    private let bootstrapState: BootstrapState

    init() {
        do {
            bootstrapState = .ready(try AppEnvironment.live())
        } catch {
            let savedLocale = AppLocalePreference(defaults: .standard).load()
            let locale = AppLocale.resolve(
                saved: savedLocale?.rawValue,
                preferred: Locale.preferredLanguages
            )
            bootstrapState = .invalidConfiguration(AppLocalizer(locale: locale))
        }
    }

    var body: some Scene {
        WindowGroup {
            switch bootstrapState {
            case let .ready(environment):
                RootView(environment: environment)
            case let .invalidConfiguration(localizer):
                ConfigurationFailureView(localizer: localizer)
            }
        }
    }
}

private struct ConfigurationFailureView: View {
    let localizer: AppLocalizer

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(localizer.text("appName"))
                .font(.title.bold())
                .accessibilityIdentifier("app.title")
            Text(localizer.text("errorServiceNotConfigured"))
                .font(.body)
                .foregroundStyle(.secondary)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .background(Color(uiColor: .systemGroupedBackground))
    }
}
