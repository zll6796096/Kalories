import SwiftUI
import UIKit

struct ResultView: View {
    let result: AnalysisResult
    let image: UIImage?
    let localizer: AppLocalizer
    let onRetake: () -> Void

    var body: some View {
        let presentation = ResultPresenter(localizer: localizer).present(result)

        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                mealHeader(presentation)

                ScoreCard(
                    score: presentation.score,
                    title: localizer.text("estimatedScore")
                )

                findings(presentation)

                metricGroup(
                    metrics(in: presentation, kinds: [.calories])
                )

                metricGroup(
                    metrics(in: presentation, kinds: [.protein, .carbs, .fat])
                )

                metricGroup(
                    metrics(in: presentation, kinds: [.fiber, .sugar, .sodium, .portion])
                )

                if !presentation.advice.isEmpty {
                    textListCard(
                        title: localizer.text("adviceTitle"),
                        items: presentation.advice,
                        symbolName: "leaf"
                    )
                }

                if !presentation.assumptions.isEmpty {
                    textListCard(
                        title: localizer.text("assumptionsTitle"),
                        items: presentation.assumptions,
                        symbolName: "info.circle"
                    )
                }

                referenceCard(presentation)

                Button(action: onRetake) {
                    Label(localizer.text("retake"), systemImage: "camera")
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .accessibilityIdentifier("result.retake")
            }
            .padding(20)
            .frame(maxWidth: 640)
            .frame(maxWidth: .infinity)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .overlay {
            GeometryReader { proxy in
                Color(uiColor: .systemGroupedBackground)
                    .frame(height: proxy.safeAreaInsets.top)
                    .frame(maxHeight: .infinity, alignment: .top)
                    .offset(y: -proxy.safeAreaInsets.top)
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
        .accessibilityIdentifier("result.page")
    }

    @ViewBuilder
    private func mealHeader(_ presentation: ResultPresentation) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                    .accessibilityLabel(presentation.foodName)
            }

            Text(localizer.text("detectedFood"))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Text(presentation.foodName)
                .font(.largeTitle.bold())
                .fixedSize(horizontal: false, vertical: true)

            Label(
                "\(localizer.text("confidence")): \(presentation.overallConfidenceLabel)",
                systemImage: "sparkles"
            )
            .font(.subheadline.weight(.medium))
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func findings(_ presentation: ResultPresentation) -> some View {
        ResultCard {
            VStack(alignment: .leading, spacing: 18) {
                finding(
                    title: localizer.text("strongestPositive"),
                    text: presentation.strongestPositive,
                    symbolName: "checkmark.circle"
                )

                Divider()

                finding(
                    title: localizer.text("mainConcern"),
                    text: presentation.mainConcern,
                    symbolName: "scope"
                )
            }
        }
    }

    private func finding(title: String, text: String, symbolName: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: symbolName)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Text(text)
                .font(.body.weight(.medium))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func metricGroup(_ metrics: [NutritionMetricPresentation]) -> some View {
        VStack(spacing: 12) {
            ForEach(metrics, id: \.kind) { metric in
                NutritionMetricView(
                    metric: metric,
                    confidenceTitle: localizer.text("confidence")
                )
            }
        }
    }

    private func metrics(
        in presentation: ResultPresentation,
        kinds: [NutritionMetricKind]
    ) -> [NutritionMetricPresentation] {
        kinds.compactMap { kind in
            presentation.metrics.first { $0.kind == kind }
        }
    }

    private func textListCard(
        title: String,
        items: [String],
        symbolName: String
    ) -> some View {
        ResultCard {
            VStack(alignment: .leading, spacing: 14) {
                Label(title, systemImage: symbolName)
                    .font(.headline)
                    .fixedSize(horizontal: false, vertical: true)

                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Image(systemName: "circle.fill")
                            .font(.system(size: 6))
                            .foregroundStyle(.secondary)
                            .accessibilityHidden(true)

                        Text(item)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    private func referenceCard(_ presentation: ResultPresentation) -> some View {
        ResultCard {
            VStack(alignment: .leading, spacing: 12) {
                Text(presentation.disclaimer)
                    .font(.footnote.weight(.medium))
                    .fixedSize(horizontal: false, vertical: true)

                Text(presentation.referenceBasis)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct ResultCard<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(uiColor: .secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}
