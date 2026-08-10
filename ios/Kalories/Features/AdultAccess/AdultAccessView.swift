import SwiftUI

struct AdultAccessView: View {
    let model: AdultAccessModel
    let localizer: AppLocalizer
    let privacyURL: URL
    let supportURL: URL

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text(localizer.text("appName"))
                    .font(.headline)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("app.title")

                Image(systemName: "checkmark.shield")
                    .font(.system(size: 44))
                    .foregroundStyle(.tint)
                    .accessibilityHidden(true)

                Text(localizer.text("adultAccessTitle"))
                    .font(.largeTitle.bold())
                    .accessibilityIdentifier("adult-access.title")

                Text(localizer.text("adultAccessBody"))

                Text(localizer.text("adultAccessUnderage"))
                    .font(.callout.weight(.semibold))

                Button(localizer.text("adultAccessConfirm")) {
                    model.confirm()
                }
                .buttonStyle(.borderedProminent)
                .frame(maxWidth: .infinity)
                .controlSize(.large)
                .accessibilityIdentifier("adult-access.confirm")

                HStack(spacing: 20) {
                    Link(localizer.text("privacyPolicy"), destination: privacyURL)
                        .accessibilityIdentifier("adult-access.privacy")
                    Link(localizer.text("support"), destination: supportURL)
                        .accessibilityIdentifier("adult-access.support")
                }
                .font(.footnote)
            }
            .padding(24)
            .frame(maxWidth: 640, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(Color(uiColor: .systemGroupedBackground))
    }
}
