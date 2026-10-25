import AVKit
import SwiftData
import SwiftUI

enum CompareMode: String, CaseIterable, Identifiable {
    case sideBySide = "Side by side"
    case slider = "Slider"
    case fade = "Fade"

    var id: Self { self }
}

struct ExportedVideo: Identifiable {
    let id = UUID()
    let url: URL
}

struct CompareView: View {
    @Query(sort: \ProgressPhoto.takenAt) private var photos: [ProgressPhoto]
    @AppStorage("comparePose") private var pose: Pose = .front
    @AppStorage("compareMode") private var mode: CompareMode = .slider
    // Before/after picks per pose, keyed "front.before", "front.after", ...
    @AppStorage("comparePicks") private var picksData = Data()
    @State private var split = 0.5
    @State private var fade = 0.5
    @State private var aligning = false
    @State private var exporting = false
    @State private var video: ExportedVideo?

    private var posePhotos: [ProgressPhoto] {
        photos.filter { $0.pose == pose }
    }

    private var picks: [String: UUID] {
        (try? JSONDecoder().decode([String: UUID].self, from: picksData)) ?? [:]
    }

    // Defaults to first vs latest until the user picks, or if the picked photo was deleted.
    private var before: ProgressPhoto? {
        posePhotos.first { $0.id == picks["\(pose.rawValue).before"] } ?? posePhotos.first
    }

    private var after: ProgressPhoto? {
        posePhotos.first { $0.id == picks["\(pose.rawValue).after"] } ?? posePhotos.last
    }

    private func pick(_ slot: String) -> Binding<UUID?> {
        let key = "\(pose.rawValue).\(slot)"
        return Binding(
            get: { picks[key] },
            set: { id in
                var updated = picks
                updated[key] = id
                picksData = (try? JSONEncoder().encode(updated)) ?? Data()
            }
        )
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Pose", selection: $pose) {
                    ForEach(Pose.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .padding()

                if posePhotos.count >= 2, let before, let after {
                    ScrollView {
                        VStack(spacing: 16) {
                            LabeledContent("Time between before vs after", value: timeBetween(before, after))
                                .font(.subheadline)
                            HStack {
                                photoMenu("Before", selection: pick("before"), current: before)
                                Image(systemName: "arrow.right").foregroundStyle(.secondary)
                                photoMenu("After", selection: pick("after"), current: after)
                            }
                            Picker("Mode", selection: $mode) {
                                ForEach(CompareMode.allCases) { Text($0.rawValue).tag($0) }
                            }
                            .pickerStyle(.segmented)
                            canvas(before: before, after: after)
                            if let start = before.weight, let end = after.weight {
                                LabeledContent("Weight change", value: (end - start).formatted(.number.precision(.fractionLength(1)).sign(strategy: .always())) + " kg")
                                    .padding()
                                    .background(.quaternary.opacity(0.6), in: .rect(cornerRadius: 12))
                            }
                        }
                        .padding(.horizontal)
                        .padding(.bottom)
                    }
                    .sheet(isPresented: $aligning) { AlignView(reference: before, moving: after) }
                } else {
                    ContentUnavailableView(
                        "Need two \(pose.rawValue) photos",
                        systemImage: "square.split.2x1",
                        description: Text("Add at least two photos of this pose to compare them.")
                    )
                }
            }
            .navigationTitle("Compare")
            .toolbar {
                if posePhotos.count >= 2 {
                    ToolbarItemGroup(placement: .primaryAction) {
                        Button { aligning = true } label: { Label("Align", systemImage: "arrow.up.and.down.and.arrow.left.and.right") }
                        if exporting {
                            ProgressView()
                        } else {
                            Button(action: exportTimelapse) { Label("Time-lapse", systemImage: "film") }
                        }
                    }
                }
            }
            .sheet(item: $video) { video in
                NavigationStack {
                    VideoPlayer(player: AVPlayer(url: video.url))
                        .aspectRatio(3 / 4, contentMode: .fit)
                        .padding()
                        .navigationTitle("\(pose.title) time-lapse")
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .primaryAction) { ShareLink(item: video.url) }
                        }
                }
            }
        }
    }

    private func photoMenu(_ title: String, selection: Binding<UUID?>, current: ProgressPhoto) -> some View {
        Menu {
            Picker(title, selection: selection) {
                ForEach(posePhotos) { photo in
                    Text(photo.takenAt.formatted(date: .abbreviated, time: .omitted)).tag(Optional(photo.id))
                }
            }
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.caption).foregroundStyle(.secondary)
                Text(current.takenAt.formatted(date: .abbreviated, time: .omitted)).font(.headline)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .background(.quaternary, in: .rect(cornerRadius: 10))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func canvas(before: ProgressPhoto, after: ProgressPhoto) -> some View {
        let beforeLabel = before.takenAt.formatted(.dateTime.month(.abbreviated).year())
        let afterLabel = after.takenAt.formatted(.dateTime.month(.abbreviated).year())
        switch mode {
        case .sideBySide:
            HStack(spacing: 4) {
                AlignedPhoto(photo: before)
                    .aspectRatio(3 / 4, contentMode: .fit)
                    .overlay(alignment: .bottomLeading) { Badge(beforeLabel) }
                AlignedPhoto(photo: after)
                    .aspectRatio(3 / 4, contentMode: .fit)
                    .overlay(alignment: .bottomLeading) { Badge(afterLabel) }
            }
            .clipShape(.rect(cornerRadius: 12))
        case .slider:
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    AlignedPhoto(photo: before)
                    AlignedPhoto(photo: after)
                        .mask(alignment: .trailing) {
                            Rectangle().frame(width: geo.size.width * (1 - split))
                        }
                    ZStack {
                        Rectangle().fill(.white).frame(width: 3)
                        Circle()
                            .fill(.white)
                            .frame(width: 34, height: 34)
                            .overlay(Image(systemName: "arrow.left.and.right").font(.caption.bold()).foregroundStyle(.black))
                    }
                    .shadow(radius: 3)
                    .offset(x: geo.size.width * split - 17)
                }
                .overlay(alignment: .bottomLeading) { Badge(beforeLabel) }
                .overlay(alignment: .bottomTrailing) { Badge(afterLabel) }
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                    split = min(max(value.location.x / geo.size.width, 0), 1)
                })
            }
            .aspectRatio(3 / 4, contentMode: .fit)
            .clipShape(.rect(cornerRadius: 12))
        case .fade:
            VStack(spacing: 12) {
                ZStack {
                    AlignedPhoto(photo: before)
                    AlignedPhoto(photo: after).opacity(fade)
                }
                .aspectRatio(3 / 4, contentMode: .fit)
                .clipShape(.rect(cornerRadius: 12))
                HStack {
                    Text(beforeLabel)
                    Slider(value: $fade)
                    Text(afterLabel)
                }
                .font(.caption)
            }
        }
    }

    private func timeBetween(_ before: ProgressPhoto, _ after: ProgressPhoto) -> String {
        let components = Calendar.current.dateComponents([.year, .month, .day], from: before.takenAt, to: after.takenAt)
        let years = abs(components.year ?? 0)
        let months = abs(components.month ?? 0)
        let days = abs(components.day ?? 0)
        let yearText = "\(years) year\(years == 1 ? "" : "s")"
        let monthText = "\(months) month\(months == 1 ? "" : "s")"
        if years > 0 { return months > 0 ? "\(yearText) \(monthText)" : yearText }
        if months > 0 { return monthText }
        return days == 0 ? "Same day" : "\(days) day\(days == 1 ? "" : "s")"
    }

    private func exportTimelapse() {
        exporting = true
        let frames = posePhotos.map {
            TimelapseExporter.Frame(fileName: $0.fileName, date: $0.takenAt, scale: $0.alignScale, offsetX: $0.alignOffsetX, offsetY: $0.alignOffsetY)
        }
        Task {
            defer { exporting = false }
            if let url = try? await TimelapseExporter.export(frames) {
                video = ExportedVideo(url: url)
            }
        }
    }
}

struct AlignView: View {
    let reference: ProgressPhoto
    @Bindable var moving: ProgressPhoto
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var overlayOpacity = 0.5
    @State private var startScale = 1.0
    @State private var startOffset = CGSize.zero

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Text("Pinch and drag the \(moving.takenAt.formatted(date: .abbreviated, time: .omitted)) photo until it lines up with \(reference.takenAt.formatted(date: .abbreviated, time: .omitted)).")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                GeometryReader { geo in
                    ZStack {
                        AlignedPhoto(photo: reference)
                        AlignedPhoto(photo: moving).opacity(overlayOpacity)
                    }
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture()
                            .onChanged { value in
                                moving.alignOffsetX = startOffset.width + value.translation.width / geo.size.width
                                moving.alignOffsetY = startOffset.height + value.translation.height / geo.size.height
                            }
                            .onEnded { _ in
                                startOffset = CGSize(width: moving.alignOffsetX, height: moving.alignOffsetY)
                            }
                            .simultaneously(with: MagnifyGesture()
                                .onChanged { value in
                                    moving.alignScale = min(max(startScale * value.magnification, 0.5), 3)
                                }
                                .onEnded { _ in startScale = moving.alignScale })
                    )
                }
                .aspectRatio(3 / 4, contentMode: .fit)
                .clipShape(.rect(cornerRadius: 12))
                HStack {
                    Text("Overlay").font(.caption)
                    Slider(value: $overlayOpacity, in: 0.1...0.9)
                }
            }
            .padding()
            .navigationTitle("Align photos")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Reset") {
                        moving.alignScale = 1
                        moving.alignOffsetX = 0
                        moving.alignOffsetY = 0
                        startScale = 1
                        startOffset = .zero
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        try? context.save()
                        dismiss()
                    }
                }
            }
            .onAppear {
                startScale = moving.alignScale
                startOffset = CGSize(width: moving.alignOffsetX, height: moving.alignOffsetY)
            }
        }
    }
}
