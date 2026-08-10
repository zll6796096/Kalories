import SwiftUI

struct AnalyzingView: View {
    let flow: AppFlowModel
    let localizer: AppLocalizer

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            ProgressView()
                .controlSize(.large)
                .accessibilityLabel(localizer.text("analyzingTitle"))

            VStack(spacing: 8) {
                Text(localizer.text("analyzingTitle"))
                    .font(.title.bold())
                    .multilineTextAlignment(.center)
                Text(localizer.text("analyzingBody"))
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            Spacer()

            Button {
                flow.cancelAnalysis()
            } label: {
                Text(localizer.text("cancel"))
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.bordered)
            .accessibilityIdentifier("analysis.cancel")
        }
        .padding(24)
        .frame(maxWidth: 640)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(uiColor: .systemGroupedBackground))
    }
}
