import SwiftUI
import SwiftData
import Charts

struct MeasurementsView: View {
    @Environment(AuthViewModel.self) private var auth
    let viewModel: BodyMetricsViewModel

    @State private var editor: MeasurementEditorTarget?

    var body: some View {
        Group {
            if let user = auth.currentUser {
                MeasurementsContent(ownerID: user.id, viewModel: viewModel, onEdit: { editor = $0 })
            } else {
                ProgressView()
            }
        }
        .background(Color.ftBackground.ignoresSafeArea())
        .navigationTitle("Vücut Ölçüleri")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    Haptics.impact(.light)
                    editor = MeasurementEditorTarget(entry: nil)
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Ölçü ekle")
            }
        }
        .sheet(item: $editor) { target in
            MeasurementEditorSheet(viewModel: viewModel, entry: target.entry)
        }
    }
}

struct MeasurementEditorTarget: Identifiable {
    let entry: MeasurementEntry?
    let id = UUID()
}

private struct MeasurementsContent: View {
    @Query private var entries: [MeasurementEntry]
    let viewModel: BodyMetricsViewModel
    let onEdit: (MeasurementEditorTarget) -> Void

    @State private var selectedMeasure: BodyMeasure = .waist

    init(ownerID: String, viewModel: BodyMetricsViewModel, onEdit: @escaping (MeasurementEditorTarget) -> Void) {
        _entries = Query(filter: #Predicate<MeasurementEntry> { $0.ownerID == ownerID }, sort: \.date, order: .reverse)
        self.viewModel = viewModel
        self.onEdit = onEdit
    }

    var body: some View {
        let changes = BodyMetricsViewModel.latestChanges(entries)
        let series = entries
            .compactMap { entry in entry.value(for: selectedMeasure).map { WeightPoint(date: entry.date, weightKg: $0) } }
            .sorted { $0.date < $1.date }

        List {
            if entries.isEmpty {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Ölçülerini takip et").font(.headline)
                        Text("Bel, göğüs, kalça gibi ölçüler, tartının göstermediği değişimi yakalar. Ayda bir ölçüm yeterli.")
                            .font(.subheadline)
                            .foregroundStyle(Color.ftTextSecondary)
                        Button("İlk ölçünü ekle") { onEdit(MeasurementEditorTarget(entry: nil)) }
                            .buttonStyle(PrimaryButtonStyle())
                            .padding(.top, 4)
                    }
                    .padding(.vertical, 6)
                    .listRowBackground(Color.ftCard)
                }
            } else {
                Section("Son Ölçüler") {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                        ForEach(BodyMeasure.allCases) { measure in
                            tile(measure, change: changes[measure])
                        }
                    }
                    .padding(.vertical, 6)
                    .listRowBackground(Color.ftCard)
                }

                if series.count >= 2 {
                    Section {
                        VStack(alignment: .leading, spacing: 12) {
                            Picker("Ölçü", selection: $selectedMeasure) {
                                ForEach(BodyMeasure.allCases) { Text($0.title).tag($0) }
                            }
                            .pickerStyle(.menu)
                            Chart(series) { point in
                                LineMark(x: .value("Tarih", point.date), y: .value("cm", point.weightKg))
                                    .interpolationMethod(.catmullRom)
                                    .foregroundStyle(Color.ftWeight)
                                PointMark(x: .value("Tarih", point.date), y: .value("cm", point.weightKg))
                                    .foregroundStyle(Color.ftWeight)
                            }
                            .chartYScale(domain: .automatic(includesZero: false))
                            .frame(height: 170)
                            .accessibilityLabel("\(selectedMeasure.title) ölçüsü grafiği")
                        }
                        .padding(.vertical, 4)
                        .listRowBackground(Color.ftCard)
                    }
                }

                Section("Geçmiş") {
                    ForEach(entries) { entry in
                        Button {
                            onEdit(MeasurementEditorTarget(entry: entry))
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(entry.date.formatted(.dateTime.day().month(.wide).year().locale(Locale(identifier: "tr_TR"))))
                                    .font(.subheadline.weight(.medium))
                                    .foregroundStyle(.white)
                                Text(summary(entry))
                                    .font(.caption)
                                    .foregroundStyle(Color.ftTextSecondary)
                                    .lineLimit(2)
                            }
                        }
                        .listRowBackground(Color.ftCard)
                        .swipeActions {
                            Button(role: .destructive) {
                                viewModel.deleteMeasurement(entry)
                            } label: {
                                Label("Sil", systemImage: "trash")
                            }
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
    }

    private func tile(_ measure: BodyMeasure, change: MeasureChange?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(measure.title, systemImage: measure.systemImage)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.ftTextSecondary)
            Text(change.map { "\($0.value.formatted(.number.precision(.fractionLength(0...1)))) cm" } ?? "—")
                .font(.title3.bold().monospacedDigit())
            if let diff = change?.change, abs(diff) >= 0.05 {
                Text("\(diff > 0 ? "+" : "−")\(abs(diff).formatted(.number.precision(.fractionLength(0...1)))) cm")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(Color.ftTextSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.ftCardElevated, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private func summary(_ entry: MeasurementEntry) -> String {
        BodyMeasure.allCases.compactMap { measure in
            entry.value(for: measure).map { "\(measure.title) \($0.formatted(.number.precision(.fractionLength(0...1))))" }
        }
        .joined(separator: " • ")
    }
}

// MARK: - Ölçü ekle / düzenle
private struct MeasurementEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    let viewModel: BodyMetricsViewModel
    let entry: MeasurementEntry?

    @State private var date: Date
    @State private var values: [BodyMeasure: Double]
    @State private var saveError: String?

    init(viewModel: BodyMetricsViewModel, entry: MeasurementEntry?) {
        self.viewModel = viewModel
        self.entry = entry
        _date = State(initialValue: entry?.date ?? .now)
        _values = State(initialValue: entry?.values ?? [:])
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker("Tarih", selection: $date, in: ...Date.now, displayedComponents: .date)
                }

                Section {
                    ForEach(BodyMeasure.allCases) { measure in
                        HStack {
                            Label(measure.title, systemImage: measure.systemImage)
                            Spacer()
                            TextField("—", value: binding(for: measure), format: .number.precision(.fractionLength(0...1)))
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                                .frame(width: 80)
                                .accessibilityLabel("\(measure.title), santimetre")
                            Text("cm").foregroundStyle(Color.ftTextSecondary)
                        }
                    }
                } footer: {
                    Text("Boş bıraktığın ölçüler kaydedilmez. Mezurayı sıkmadan, aynı noktadan ölçmek tutarlılık sağlar.")
                }

                if let entry {
                    Section {
                        Button("Ölçümü sil", role: .destructive) {
                            viewModel.deleteMeasurement(entry)
                            dismiss()
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.ftBackground)
            .navigationTitle(entry == nil ? "Ölçü Ekle" : "Ölçüyü Düzenle")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Vazgeç") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Kaydet") {
                        do {
                            try viewModel.saveMeasurement(values, date: date, editing: entry)
                            dismiss()
                        } catch {
                            saveError = AppError.map(error).errorDescription
                            Haptics.error()
                        }
                    }
                    .disabled(values.isEmpty)
                }
            }
        }
        .alert("Kaydedilemedi", isPresented: Binding(get: { saveError != nil }, set: { if !$0 { saveError = nil } })) {
            Button("Tamam", role: .cancel) {}
        } message: {
            Text(saveError ?? "")
        }
    }

    private func binding(for measure: BodyMeasure) -> Binding<Double?> {
        Binding(
            get: { values[measure] },
            set: { newValue in
                if let newValue, newValue > 0 {
                    values[measure] = newValue
                } else {
                    values[measure] = nil
                }
            }
        )
    }
}
