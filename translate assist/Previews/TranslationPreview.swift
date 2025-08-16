//
//  TranslationPreview.swift
//  translate assist
//
//  Phase 2: Provider‑driven preview using TranslationVM + fake providers.
//

import SwiftUI

struct TranslationDrivenPreview: View {
    @StateObject private var vm = TranslationVM(
        translationProvider: FakeTranslationProvider(),
        llmEnhancer: FakeLLMEnhancer(),
        glossary: FakeGlossaryProvider(),
        examplesProvider: FakeExamplesProvider(),
        metrics: FakeMetricsProvider()
    )

    @State private var term: String = "Hello, world!"
    @State private var persona: String = "Engineer·Read"

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                TextField("Enter text", text: $term)
                    .textFieldStyle(.roundedBorder)
                Button("Run") {
                    Task { await vm.load(term: term, src: "en", persona: persona) }
                }
            }

            if let banner = vm.banner { Text(banner).font(.footnote).foregroundStyle(.orange) }

            Text(vm.topText.isEmpty ? "—" : vm.topText)
                .font(.title3)
                .bold()

            if !vm.alternatives.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Alternatives")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    ForEach(vm.alternatives, id: \.self) { alt in
                        Text(alt).font(.body).foregroundStyle(.secondary)
                    }
                }
            }

            if !vm.explanation.isEmpty { Text(vm.explanation).font(.footnote).foregroundStyle(.secondary) }
            Spacer()
        }
        .padding(16)
        .frame(width: Constants.popoverWidth, height: Constants.popoverHeight)
        .task { await vm.load(term: term, src: "en", persona: persona) }
    }
}

#Preview("VM‑driven · Light") {
    TranslationDrivenPreview()
}

#Preview("VM‑driven · RTL Dark") {
    TranslationDrivenPreview()
        .environment(\.layoutDirection, .rightToLeft)
        .preferredColorScheme(.dark)
}


