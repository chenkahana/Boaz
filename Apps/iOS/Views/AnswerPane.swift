import SwiftUI

struct AnswerPane: View {
    @Environment(BrowserModel.self) private var model

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                SearchBar()
                if model.isLoading {
                    LoadingGlow()
                } else if let answer = model.answer {
                    AnswerContent(answer: answer)
                } else {
                    EmptyHero()
                }
            }
            .padding(20)
        }
        .scrollDismissesKeyboard(.interactively)
    }
}

private struct AnswerContent: View {
    @Environment(BrowserModel.self) private var model
    let answer: Answer

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(answer.title)
                .font(.system(.largeTitle, design: .rounded, weight: .bold))
                .foregroundStyle(Theme.textPrimary)

            SourceStrip(sources: answer.sources)

            ForEach(answer.sections) { section in
                VStack(alignment: .leading, spacing: 12) {
                    Text(section.title)
                        .font(.system(.title3, design: .rounded, weight: .semibold))
                    ForEach(section.bullets) { bullet in
                        BulletRow(bullet: bullet, source: answer.source(for: bullet))
                    }
                    ForEach(section.followUps, id: \.self) { question in
                        Button {
                            model.query = question
                            Task { await model.search() }
                        } label: {
                            Label(question, systemImage: "arrow.turn.down.right")
                                .font(.subheadline)
                        }
                        .buttonStyle(.bordered)
                        .buttonBorderShape(.capsule)
                    }
                }
                .card()
            }
        }
    }
}

private struct BulletRow: View {
    @Environment(BrowserModel.self) private var model
    let bullet: Answer.Bullet
    let source: Answer.Source?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(bullet.emoji)
            VStack(alignment: .leading, spacing: 6) {
                Text(bullet.text).foregroundStyle(Theme.textPrimary)
                if let source {
                    Button {
                        model.open(source, quote: bullet.quote)
                    } label: {
                        Text(source.site)
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(Theme.indigo(4), in: .capsule)
                            .foregroundStyle(Theme.indigo(11))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

private struct SourceStrip: View {
    @Environment(BrowserModel.self) private var model
    let sources: [Answer.Source]

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(sources) { source in
                    Button { model.open(source, quote: nil) } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(source.site).font(.caption2).foregroundStyle(Theme.textSecondary)
                            Text(source.title).font(.footnote.weight(.medium)).lineLimit(2)
                        }
                        .frame(width: 150, alignment: .leading)
                        .card()
                        .overlay(RoundedRectangle(cornerRadius: Theme.cornerRadius)
                            .stroke(model.selectedSource == source ? Theme.brand : .clear, lineWidth: 2))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .scrollIndicators(.hidden)
    }
}

private struct EmptyHero: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: "sparkle").font(.largeTitle).foregroundStyle(Theme.yellow)
            Text("Go anywhere.").font(.system(.largeTitle, design: .rounded, weight: .bold))
            Text("Search or type an address.")
                .foregroundStyle(.white.opacity(0.85))
        }
        .foregroundStyle(.white)
        .padding(24)
        .frame(maxWidth: .infinity, minHeight: 260, alignment: .bottomLeading)
        .background(Theme.hero, in: .rect(cornerRadius: 28))
    }
}

private struct LoadingGlow: View {
    @State private var phase = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(0..<4, id: \.self) { i in
                Capsule()
                    .fill(Theme.glow)
                    .frame(height: 14)
                    .frame(maxWidth: i == 3 ? 180 : .infinity)
                    .opacity(phase ? 0.9 : 0.3)
            }
        }
        .animation(.easeInOut(duration: 0.9).repeatForever(), value: phase)
        .onAppear { phase = true }
    }
}
