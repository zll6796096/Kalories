import SwiftUI

struct NutritionMetricView: View {
    let metric: NutritionMetricPresentation
    let confidenceTitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 16) {
                Text(metric.label)
                    .font(.body.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 8)

                Text(metric.valueText)
                    .font(.title3.weight(.semibold))
                    .monospacedDigit()
                    .multilineTextAlignment(.trailing)
                    .fixedSize(horizontal: false, vertical: true)
            }

            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    confidenceText
                    Spacer(minLength: 8)
                    statusLabel
                }

                VStack(alignment: .leading, spacing: 8) {
                    confidenceText
                    statusLabel
                }
            }
        }
        .padding(16)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilitySummary)
    }

    private var confidenceText: some View {
        Text("\(confidenceTitle): \(metric.confidenceLabel)")
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private var statusLabel: some View {
        if let status = metric.status {
            Label(status.text, systemImage: status.symbolName)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(color(for: status.style))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var accessibilitySummary: String {
        var parts = [
            metric.label,
            metric.valueText,
            "\(confidenceTitle): \(metric.confidenceLabel)",
        ]
        if let status = metric.status {
            parts.append(status.text)
        }
        return parts.joined(separator: ", ")
    }

    private func color(for style: NutritionStatusStyle) -> Color {
        switch style {
        case .low:
            .orange
        case .appropriate:
            .green
        case .high:
            .orange
        case .indeterminate:
            .secondary
        }
    }
}
