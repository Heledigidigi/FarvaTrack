import SwiftUI

/// Egzersiz form rehberi: adımlar, sık hatalar, çalışan kaslar.
struct ExerciseGuideView: View {
    let name: String
    let category: ExerciseCategory
    let guide: ExerciseGuide

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(spacing: 12) {
                        Image(systemName: guide.symbol)
                            .font(.system(size: 64))
                            .foregroundStyle(category.tint)
                            .frame(width: 120, height: 120)
                            .background(category.tint.opacity(0.15), in: Circle())
                            .accessibilityHidden(true)
                        FlowTags(tags: guide.muscles, tint: category.tint)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .listRowBackground(Color.clear)
                }

                Section("Nasıl yapılır") {
                    ForEach(Array(guide.steps.enumerated()), id: \.offset) { index, step in
                        HStack(alignment: .top, spacing: 12) {
                            Text("\(index + 1)")
                                .font(.subheadline.bold().monospacedDigit())
                                .frame(width: 24, height: 24)
                                .background(category.tint.opacity(0.2), in: Circle())
                                .foregroundStyle(category.tint)
                            Text(step).font(.subheadline)
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
                .listRowBackground(Color.ftCard)

                Section("Sık yapılan hatalar") {
                    ForEach(guide.mistakes, id: \.self) { mistake in
                        Label(mistake, systemImage: "xmark.octagon.fill")
                            .font(.subheadline)
                            .foregroundStyle(Color.white, Color.ftWarning)
                    }
                }
                .listRowBackground(Color.ftCard)

                if let tip = guide.tip {
                    Section("İpucu") {
                        Label(tip, systemImage: "lightbulb.fill")
                            .font(.subheadline)
                            .foregroundStyle(Color.white, Color.ftStats)
                    }
                    .listRowBackground(Color.ftCard)
                }

                Section {
                    if let url = ExerciseGuide.videoSearchURL(for: name) {
                        Link(destination: url) {
                            Label("YouTube'da örnek videolara bak", systemImage: "play.rectangle.fill")
                        }
                    }
                } footer: {
                    Text("Bu bilgiler genel rehber niteliğindedir. Ağrı hissedersen hareketi bırak; yeni başlıyorsan bir antrenörden destek almak iyi olur.")
                }
                .listRowBackground(Color.ftCard)
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .ftScreenBackground()
            .navigationTitle(name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Kapat") { dismiss() }
                }
            }
        }
    }
}

/// Kas etiketleri (satır sonuna gelince alta geçer).
private struct FlowTags: View {
    let tags: [String]
    let tint: Color

    var body: some View {
        ViewThatFits {
            HStack(spacing: 6) { chips }
            VStack(spacing: 6) {
                HStack(spacing: 6) { ForEach(tags.prefix(3), id: \.self, content: chip) }
                HStack(spacing: 6) { ForEach(tags.dropFirst(3), id: \.self, content: chip) }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Çalışan kaslar: \(tags.joined(separator: ", "))")
    }

    private var chips: some View {
        ForEach(tags, id: \.self, content: chip)
    }

    private func chip(_ text: String) -> some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(tint.opacity(0.18), in: Capsule())
            .foregroundStyle(tint)
    }
}

/// Bir egzersiz için rehber varsa "i" butonu gösterir.
struct ExerciseGuideButton: View {
    let key: String
    let name: String
    let category: ExerciseCategory
    @State private var show = false

    var body: some View {
        if let guide = ExerciseGuides.guide(for: key) {
            Button {
                show = true
            } label: {
                Image(systemName: "info.circle")
                    .foregroundStyle(Color.ftAccentLight)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("\(name) nasıl yapılır")
            .sheet(isPresented: $show) {
                ExerciseGuideView(name: name, category: category, guide: guide)
            }
        }
    }
}
