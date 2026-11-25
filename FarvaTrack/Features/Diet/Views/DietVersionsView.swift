import SwiftUI

/// Sürüm geçmişi ve programı inceleyen kişinin önerileri.
struct DietVersionsView: View {
    @Environment(DietStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let programID: String
    @State private var diffVersion: DietVersion?
    @State private var effective: [String: Date] = [:]

    private var program: DietProgram? { store.program(id: programID) }
    private var pending: [DietSuggestion] { store.suggestions(for: programID).filter { $0.status == .pending } }
    private var decided: [DietSuggestion] { store.suggestions(for: programID).filter { $0.status != .pending } }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(pending) { suggestion in suggestionCard(suggestion) }
                    DietSectionTitle(text: "Sürüm geçmişi")
                    if let program {
                        VStack(spacing: 0) {
                            ForEach(program.versions.sorted { $0.number > $1.number }) { version in
                                versionRow(version, current: version.number == program.version(on: .now).number)
                            }
                        }
                        .padding(.horizontal, 14)
                        .background(Color.ftCard, in: RoundedRectangle(cornerRadius: 14))
                    }
                    Text("Eski günlerin kayıtları ve analizleri hangi sürümle yapıldıysa onunla kalır.")
                        .font(.caption).foregroundStyle(Color.ftTextSecondary)
                    if !decided.isEmpty {
                        DietSectionTitle(text: "Önceki öneriler")
                        ForEach(decided) { suggestion in
                            HStack {
                                Text("\(suggestion.authorName) · \(DietFormat.shortDate(suggestion.createdAt))").font(.subheadline)
                                Spacer()
                                Text(suggestion.status == .accepted ? "Kabul edildi" : "Reddedildi")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(suggestion.status == .accepted ? Color.ftSuccess : Color.ftTextSecondary)
                            }
                            .padding(12)
                            .background(Color.ftCard, in: RoundedRectangle(cornerRadius: 12))
                        }
                    }
                }
                .padding(16)
            }
            .ftScreenBackground()
            .navigationTitle("\(program?.name ?? "Program") · Sürümler")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Kapat") { dismiss() } } }
            .sheet(item: $diffVersion) { version in DietVersionDiffView(programID: programID, version: version) }
            .task { await store.refreshSocial() }
        }
    }

    private func suggestionCard(_ suggestion: DietSuggestion) -> some View {
        let base = program?.latestPlan ?? DietPlan()
        let changes = DietPlanDiff.changes(from: base, to: suggestion.plan)
        let defaultDate = Calendar.current.date(byAdding: .day, value: 1, to: .now) ?? .now
        let date = Binding(get: { effective[suggestion.id] ?? defaultDate }, set: { effective[suggestion.id] = $0 })
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: "person.crop.circle.fill").font(.title).foregroundStyle(Color.ftAccentLight)
                VStack(alignment: .leading, spacing: 1) {
                    Text("\(suggestion.authorName) değişiklik önerdi").font(.headline).foregroundStyle(Color.ftText)
                    Text("Sürüm \(suggestion.basedOnVersion + 1) · \(suggestion.createdAt.formatted(.dateTime.day().month().hour().minute().locale(DietFormat.locale)))")
                        .font(.caption).foregroundStyle(Color.ftTextSecondary)
                }
            }
            if !suggestion.note.isEmpty {
                Text("“\(suggestion.note)”").font(.subheadline)
                    .padding(10).frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.ftAccent.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
            }
            ForEach(changes.prefix(8)) { change in
                HStack(alignment: .top, spacing: 6) {
                    Text(change.symbol).bold().foregroundStyle(change.kind == .removed ? Color.ftDanger : (change.kind == .added ? Color.ftSuccess : Color.ftWarning))
                    Text("\(change.mealName): \(change.text)").font(.subheadline)
                    Spacer()
                    Text(change.daysText).font(.caption).foregroundStyle(Color.ftTextSecondary)
                }
                Divider()
            }
            let before = base.averageNutrition
            let after = suggestion.plan.averageNutrition
            let proteinDelta = Int((after.protein - before.protein).rounded())
            HStack {
                Text("Günlük ort.").font(.caption)
                Spacer()
                Text("\(before.kcal) → \(after.kcal) kcal").font(.caption.bold())
                Text("P \(proteinDelta >= 0 ? "+" : "")\(proteinDelta) g")
                    .font(.caption).foregroundStyle(MacroKind.protein.color)
            }
            .padding(8)
            .background(Color.ftCardElevated, in: RoundedRectangle(cornerRadius: 10))
            DatePicker("Ne zamandan", selection: date, in: Calendar.current.startOfDay(for: .now)..., displayedComponents: .date)
                .environment(\.locale, DietFormat.locale)
            HStack {
                Button("Reddet") { Task { await store.decide(suggestion, accept: false, effectiveFrom: date.wrappedValue) } }
                    .buttonStyle(.bordered).tint(Color.ftTextSecondary)
                Button("Kabul et ve uygula") { Task { await store.decide(suggestion, accept: true, effectiveFrom: date.wrappedValue) } }
                    .buttonStyle(.borderedProminent).tint(Color.ftAccent)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(14)
        .background(Color.ftCard, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.ftAccent.opacity(0.55), lineWidth: 1.5))
    }

    private func versionRow(_ version: DietVersion, current: Bool) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Circle().fill(current ? Color.ftAccent : Color.clear)
                .overlay(Circle().strokeBorder(Color.ftAccent.opacity(0.6), lineWidth: current ? 0 : 2))
                .frame(width: 10, height: 10).padding(.top, 5)
            VStack(alignment: .leading, spacing: 2) {
                Text("Sürüm \(version.number)\(current ? " · kullanımda" : "")").font(.subheadline.bold()).foregroundStyle(Color.ftText)
                Text("\(DietFormat.shortDate(version.effectiveFrom)) itibarıyla\(version.authorName.map { " · \($0)" } ?? "")")
                    .font(.caption).foregroundStyle(Color.ftTextSecondary)
                if !version.note.isEmpty { Text(version.note).font(.caption).foregroundStyle(Color.ftText) }
            }
            Spacer()
            if version.number > 1 {
                Button("Fark") { diffVersion = version }.font(.caption.weight(.semibold)).tint(Color.ftAccentLight)
            }
        }
        .padding(.vertical, 10)
    }
}

struct DietVersionDiffView: View {
    @Environment(DietStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let programID: String
    let version: DietVersion

    var body: some View {
        NavigationStack {
            List {
                let previous = store.program(id: programID)?.versions.first { $0.number == version.number - 1 }?.plan ?? DietPlan()
                let changes = DietPlanDiff.changes(from: previous, to: version.plan)
                if changes.isEmpty { Text("Plan aynı (yalnızca tarih ya da not değişti).") }
                ForEach(changes) { change in
                    HStack(alignment: .top) {
                        Text(change.symbol).bold()
                        VStack(alignment: .leading) {
                            Text("\(change.mealName): \(change.text)")
                            Text(change.days.count <= 8 ? "Gün " + change.days.map(String.init).joined(separator: ", ") : "\(change.days.count) gün")
                                .font(.caption).foregroundStyle(Color.ftTextSecondary)
                        }
                    }
                }
            }
            .navigationTitle("Sürüm \(version.number - 1) → \(version.number)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Kapat") { dismiss() } } }
        }
    }
}
