import SwiftUI

/// Serif, space-tinted reading view built from the blocks `Reader` extracted — no external parser.
struct ReaderView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme
    let article: ReaderArticle
    let tint: Color

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(article.title)
                            .font(.system(.largeTitle, design: .serif, weight: .bold))
                        HStack(spacing: 6) {
                            Text(article.site.uppercased()).font(.caption.weight(.semibold))
                            Text("·").font(.caption)
                            Text("\(article.readingMinutes) min read").font(.caption)
                        }
                        .foregroundStyle(tint)
                    }
                    ForEach(article.blocks) { block in BlockView(block: block) }
                }
                .padding(20)
                .padding(.bottom, 60)
            }
            .background(backgroundTint)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } } }
        }
    }

    private var backgroundTint: Color {
        scheme == .dark ? Color.black : tint.opacity(0.04)
    }
}

private struct BlockView: View {
    let block: ReaderBlock

    var body: some View {
        switch block.tag {
        case .h2:
            Text(block.text ?? "").font(.system(.title2, design: .serif, weight: .bold)).padding(.top, 6)
        case .h3:
            Text(block.text ?? "").font(.system(.title3, design: .serif, weight: .semibold)).padding(.top, 4)
        case .p:
            Text(block.text ?? "").font(.system(.body, design: .serif)).lineSpacing(6)
        case .blockquote:
            HStack(spacing: 12) {
                Capsule().fill(.secondary).frame(width: 3)
                Text(block.text ?? "").font(.system(.body, design: .serif).italic()).foregroundStyle(.secondary)
            }
        case .li:
            HStack(alignment: .top, spacing: 8) {
                Text("•").font(.system(.body, design: .serif))
                Text(block.text ?? "").font(.system(.body, design: .serif)).lineSpacing(6)
            }
        case .img:
            if let src = block.src, let url = URL(string: src) {
                AsyncImage(url: url) { image in
                    image.resizable().aspectRatio(contentMode: .fit)
                } placeholder: { Color.clear }
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        case .figcaption:
            Text(block.text ?? "").font(.caption).foregroundStyle(.secondary)
        }
    }
}
