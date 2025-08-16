//
//  Phase2Preview.swift
//  translate assist
//
//  Phase 2: Simple SwiftUI preview rendering canned MT + LLM results.
//

import SwiftUI

struct Phase2PreviewView: View {
    private let mt = FakeDataFactory.sampleMTResponse()
    private let decision = FakeDataFactory.sampleDecision()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "globe")
                    .imageScale(.large)
                Text("Translate Assist")
                    .font(.headline)
                Spacer()
            }

            let topText = topCandidateText()
            Text(topText)
                .font(.title3)
                .bold()

            if !alternatives().isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Alternatives")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    ForEach(alternatives(), id: \.self) { alt in
                        Text(alt)
                            .font(.body)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Text(decision.explanation)
                .font(.footnote)
                .foregroundStyle(.secondary)

            Spacer()
        }
        .padding(16)
        .frame(width: Constants.popoverWidth, height: Constants.popoverHeight)
    }

    private func topCandidateText() -> String {
        if decision.decision == .rewrite, let rewrite = decision.rewrite {
            return rewrite
        }
        if mt.candidates.indices.contains(decision.topIndex) {
            return mt.candidates[decision.topIndex].text
        }
        return mt.candidates.first?.text ?? "—"
    }

    private func alternatives() -> [String] {
        mt.candidates.enumerated()
            .filter { $0.offset != decision.topIndex }
            .map { $0.element.text }
    }
}

#Preview("Light · LTR") {
    Phase2PreviewView()
}

#Preview("Dark · RTL") {
    Phase2PreviewView()
        .environment(\.layoutDirection, .rightToLeft)
        .preferredColorScheme(.dark)
}


