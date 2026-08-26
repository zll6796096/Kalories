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

                footer
            }
            .padding(24)
            .frame(maxWidth: 640, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(Color(uiColor: .systemGroupedBackground))
    }

    private var footer: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 20) {
                footerLink(
                    localizer.text("privacyPolicy"),
                    destination: privacyURL,
                    identifier: "adult-access.privacy"
                )
                .fixedSize(horizontal: true, vertical: false)
                footerLink(
                    localizer.text("support"),
                    destination: supportURL,
                    identifier: "adult-access.support"
                )
                .fixedSize(horizontal: true, vertical: false)
            }

            VStack(spacing: 0) {
                footerLink(
                    localizer.text("privacyPolicy"),
                    destination: privacyURL,
                    identifier: "adult-access.privacy"
                )
                footerLink(
                    localizer.text("support"),
                    destination: supportURL,
                    identifier: "adult-access.support"
                )
            }
        }
        .font(.footnote)
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private func footerLink(
        _ title: String,
        destination: URL,
        identifier: String
    ) -> some View {
        Link(destination: destination) {
            Text(title)
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
        }
        .accessibilityIdentifier(identifier)
    }
}
