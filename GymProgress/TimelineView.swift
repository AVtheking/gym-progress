import PhotosUI
import SwiftData
import SwiftUI

struct TimelineView: View {
    @Query(sort: \ProgressPhoto.takenAt, order: .reverse) private var photos: [ProgressPhoto]
    @State private var poseFilter: Pose?
    @State private var showCamera = false
    @State private var showPicker = false
    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var importBatch: ImportBatch?

    private var months: [(month: Date, photos: [ProgressPhoto])] {
        let filtered = photos.filter { poseFilter == nil || $0.pose == poseFilter }
        let grouped = Dictionary(grouping: filtered) {
            Calendar.current.dateInterval(of: .month, for: $0.takenAt)?.start ?? $0.takenAt
        }
        return grouped.keys.sorted(by: >).map { ($0, grouped[$0] ?? []) }
    }

    var body: some View {
        NavigationStack {
            Group {
                if photos.isEmpty {
                    ContentUnavailableView {
                        Label("No progress photos yet", systemImage: "figure.strengthtraining.traditional")
                    } description: {
                        Text("Take this month's photos or import older ones from your library.")
                    } actions: {
                        Button("Take photos") { showCamera = true }.buttonStyle(.borderedProminent)
                        Button("Import from Photos") { showPicker = true }
                    }
                } else {
                    ScrollView {
                        Picker("Pose", selection: $poseFilter) {
                            Text("All").tag(Pose?.none)
                            ForEach(Pose.allCases) { Text($0.title).tag(Pose?.some($0)) }
                        }
                        .pickerStyle(.segmented)
                        .padding(.horizontal)

                        LazyVStack(alignment: .leading, spacing: 12, pinnedViews: .sectionHeaders) {
                            ForEach(months, id: \.month) { month in
                                Section {
                                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 3), spacing: 4) {
                                        ForEach(month.photos) { photo in
                                            NavigationLink(value: photo) {
                                                StoredPhoto(fileName: photo.fileName)
                                                    .aspectRatio(3 / 4, contentMode: .fit)
                                                    .overlay(alignment: .bottomLeading) { Badge(photo.pose.title) }
                                            }
                                        }
                                    }
                                    .padding(.horizontal, 4)
                                } header: {
                                    Text(month.month.formatted(.dateTime.month(.wide).year()))
                                        .font(.headline)
                                        .padding(.horizontal)
                                        .padding(.vertical, 6)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .background(.bar)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Progress")
            .navigationDestination(for: ProgressPhoto.self) { PhotoDetailView(photo: $0) }
            .toolbar {
                ToolbarItemGroup(placement: .primaryAction) {
                    Button { showPicker = true } label: { Label("Import", systemImage: "photo.badge.plus") }
                    Button { showCamera = true } label: { Label("Camera", systemImage: "camera") }
                }
            }
            .photosPicker(isPresented: $showPicker, selection: $pickerItems, maxSelectionCount: 50, matching: .images)
            .onChange(of: pickerItems) { _, items in
                guard !items.isEmpty else { return }
                importBatch = ImportBatch(items: items)
                pickerItems = []
            }
            .sheet(item: $importBatch) { ImportReviewView(items: $0.items) }
            .fullScreenCover(isPresented: $showCamera) { CaptureView() }
        }
    }
}

struct ImportBatch: Identifiable {
    let id = UUID()
    let items: [PhotosPickerItem]
}

struct ImportDraft: Identifiable {
    let id = UUID()
    let data: Data
    let preview: UIImage?
    var date: Date
    let dateFound: Bool
    var pose: Pose
}

struct ImportReviewView: View {
    let items: [PhotosPickerItem]
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var drafts: [ImportDraft] = []
    @State private var loading = true
    @State private var saving = false

    var body: some View {
        NavigationStack {
            List {
                if loading {
                    HStack(spacing: 12) {
                        ProgressView()
                        Text("Loading \(items.count) photos…")
                    }
                }
                ForEach($drafts) { $draft in
                    HStack(alignment: .top, spacing: 12) {
                        Image(uiImage: draft.preview ?? UIImage())
                            .resizable()
                            .scaledToFill()
                            .frame(width: 72, height: 96)
                            .clipShape(.rect(cornerRadius: 8))
                        VStack(alignment: .leading, spacing: 8) {
                            DatePicker("Taken", selection: $draft.date, displayedComponents: .date)
                            if !draft.dateFound {
                                Text("No date in this photo, please check it")
                                    .font(.caption)
                                    .foregroundStyle(.orange)
                            }
                            Picker("Pose", selection: $draft.pose) {
                                ForEach(Pose.allCases) { Text($0.title).tag($0) }
                            }
                            .pickerStyle(.segmented)
                        }
                    }
                }
                .onDelete { drafts.remove(atOffsets: $0) }
            }
            .navigationTitle("Import photos")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save \(drafts.count)", action: save)
                        .disabled(loading || saving || drafts.isEmpty)
                }
            }
            .overlay {
                if saving { ProgressView("Saving…").padding().background(.regularMaterial, in: .rect(cornerRadius: 12)) }
            }
            .interactiveDismissDisabled(saving)
            .task { await load() }
        }
    }

    private func load() async {
        for item in items {
            guard let data = try? await item.loadTransferable(type: Data.self) else { continue }
            let date = PhotoStore.captureDate(of: data)
            drafts.append(ImportDraft(
                data: data,
                preview: PhotoStore.preview(of: data, maxPixel: 300),
                date: date ?? .now,
                dateFound: date != nil,
                pose: .front
            ))
        }
        loading = false
    }

    private func save() {
        saving = true
        Task {
            for draft in drafts {
                let data = draft.data
                guard let fileName = try? await Task.detached(operation: { try PhotoStore.save(data) }).value else { continue }
                context.insert(ProgressPhoto(takenAt: draft.date, pose: draft.pose, fileName: fileName))
            }
            dismiss()
        }
    }
}

struct PhotoDetailView: View {
    @Bindable var photo: ProgressPhoto
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var weightText = ""
    @State private var confirmDelete = false

    var body: some View {
        Form {
            Section {
                StoredPhoto(fileName: photo.fileName, maxPixel: 1600)
                    .aspectRatio(3 / 4, contentMode: .fit)
                    .listRowInsets(EdgeInsets())
            }
            Section {
                DatePicker("Date", selection: $photo.takenAt, displayedComponents: .date)
                Picker("Pose", selection: $photo.pose) {
                    ForEach(Pose.allCases) { Text($0.title).tag($0) }
                }
                LabeledContent("Weight (kg)") {
                    TextField("Optional", text: $weightText)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                }
                TextField("Notes", text: $photo.note, axis: .vertical)
            }
            Section {
                Button("Delete photo", role: .destructive) { confirmDelete = true }
            }
        }
        .navigationTitle(photo.takenAt.formatted(date: .abbreviated, time: .omitted))
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { weightText = photo.weight.map { $0.formatted(.number.grouping(.never)) } ?? "" }
        .onChange(of: weightText) { _, text in
            photo.weight = Double(text.replacingOccurrences(of: ",", with: "."))
        }
        .confirmationDialog("Delete this photo?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                dismiss()
                PhotoStore.delete(named: photo.fileName)
                context.delete(photo)
            }
        }
    }
}
