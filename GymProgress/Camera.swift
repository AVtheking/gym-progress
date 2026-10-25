import AVFoundation
import SwiftData
import SwiftUI

final class CameraController: NSObject, ObservableObject, AVCapturePhotoCaptureDelegate {
    let session = AVCaptureSession()
    @Published var permissionDenied = false
    @Published var unavailable = false
    private let output = AVCapturePhotoOutput()
    private let queue = DispatchQueue(label: "camera.session")
    private var position: AVCaptureDevice.Position = .front
    private var pending: CheckedContinuation<Data?, Never>?

    func start() {
        Task { @MainActor in
            guard await AVCaptureDevice.requestAccess(for: .video) else {
                permissionDenied = true
                return
            }
            let position = position
            queue.async { [self] in
                configure(position)
                session.startRunning()
            }
        }
    }

    func stop() {
        queue.async { [self] in session.stopRunning() }
    }

    func flip() {
        position = position == .front ? .back : .front
        let position = position
        queue.async { [self] in configure(position) }
    }

    func capture() async -> Data? {
        // Front shots are saved mirrored so they match the preview and the ghost overlay.
        let mirrored = position == .front
        return await withCheckedContinuation { continuation in
            pending = continuation
            queue.async { [self] in
                if let connection = output.connection(with: .video) {
                    if connection.isVideoMirroringSupported {
                        connection.automaticallyAdjustsVideoMirroring = false
                        connection.isVideoMirrored = mirrored
                    }
                    if connection.isVideoRotationAngleSupported(90) {
                        connection.videoRotationAngle = 90
                    }
                }
                output.capturePhoto(with: AVCapturePhotoSettings(), delegate: self)
            }
        }
    }

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        let data = error == nil ? photo.fileDataRepresentation() : nil
        DispatchQueue.main.async { [self] in
            pending?.resume(returning: data)
            pending = nil
        }
    }

    private func configure(_ position: AVCaptureDevice.Position) {
        session.beginConfiguration()
        defer { session.commitConfiguration() }
        session.sessionPreset = .photo
        session.inputs.forEach { session.removeInput($0) }
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input)
        else {
            DispatchQueue.main.async { self.unavailable = true }
            return
        }
        session.addInput(input)
        if !session.outputs.contains(output), session.canAddOutput(output) {
            session.addOutput(output)
        }
    }
}

struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ view: PreviewView, context: Context) {}

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }
}

struct CaptureView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query(sort: \ProgressPhoto.takenAt, order: .reverse) private var photos: [ProgressPhoto]
    @StateObject private var camera = CameraController()
    @State private var pose: Pose = .front
    @State private var ghostOpacity = 0.35
    @State private var timer = 0
    @State private var countdown: Int?
    @State private var shooting = false
    @State private var flash = false
    @State private var savedCount = 0

    private var ghost: ProgressPhoto? {
        photos.first { $0.pose == pose }
    }

    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Button("Done") { dismiss() }
                Spacer()
                if savedCount > 0 {
                    Text("\(savedCount) saved").foregroundStyle(.secondary)
                    Spacer()
                }
                Menu {
                    Picker("Timer", selection: $timer) {
                        Text("Off").tag(0)
                        Text("3 seconds").tag(3)
                        Text("10 seconds").tag(10)
                    }
                } label: {
                    Label(timer == 0 ? "Timer" : "\(timer)s", systemImage: "timer")
                }
            }
            .padding(.horizontal)

            Picker("Pose", selection: $pose) {
                ForEach(Pose.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)

            ZStack {
                if camera.unavailable {
                    Color.black
                    Text("Camera not available").foregroundStyle(.white)
                } else {
                    CameraPreview(session: camera.session)
                }
                if let ghost {
                    StoredPhoto(fileName: ghost.fileName, maxPixel: 1200)
                        .opacity(ghostOpacity)
                        .allowsHitTesting(false)
                }
                if let countdown {
                    Text("\(countdown)")
                        .font(.system(size: 120, weight: .bold))
                        .foregroundStyle(.white)
                        .shadow(radius: 8)
                }
                if flash { Color.white }
            }
            .aspectRatio(3 / 4, contentMode: .fit)
            .clipShape(.rect(cornerRadius: 16))
            .padding(.horizontal)

            if ghost != nil {
                VStack(spacing: 4) {
                    HStack {
                        Image(systemName: "circle.lefthalf.filled")
                        Slider(value: $ghostOpacity, in: 0...0.8)
                    }
                    Text("Line up with your last \(pose.rawValue) photo")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal)
            }

            Spacer()

            HStack {
                Color.clear.frame(maxWidth: .infinity, maxHeight: 1)
                Button(action: shoot) {
                    Circle()
                        .strokeBorder(.primary, lineWidth: 4)
                        .overlay(Circle().fill(.primary).padding(8))
                        .frame(width: 76, height: 76)
                }
                .disabled(shooting || camera.unavailable)
                Button { camera.flip() } label: {
                    Image(systemName: "arrow.triangle.2.circlepath.camera").font(.title2)
                }
                .frame(maxWidth: .infinity)
            }
            .padding(.bottom)
        }
        .onAppear { camera.start() }
        .onDisappear { camera.stop() }
        .alert("Camera access needed", isPresented: $camera.permissionDenied) {
            Button("OK") {}
        } message: {
            Text("Allow camera access in Settings to take progress photos.")
        }
    }

    private func shoot() {
        shooting = true
        Task {
            defer { shooting = false }
            for remaining in stride(from: timer, to: 0, by: -1) {
                countdown = remaining
                try? await Task.sleep(for: .seconds(1))
            }
            countdown = nil
            guard let data = await camera.capture() else { return }
            flash = true
            try? await Task.sleep(for: .milliseconds(120))
            withAnimation { flash = false }
            guard let fileName = try? PhotoStore.save(data) else { return }
            context.insert(ProgressPhoto(takenAt: .now, pose: pose, fileName: fileName))
            savedCount += 1
            // Walk through front → side → back in one session.
            if let index = Pose.allCases.firstIndex(of: pose), index + 1 < Pose.allCases.count {
                pose = Pose.allCases[index + 1]
            }
        }
    }
}
