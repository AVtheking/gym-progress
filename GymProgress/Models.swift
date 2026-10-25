import Foundation
import SwiftData

enum Pose: String, CaseIterable, Identifiable, Codable {
    case front, side, back

    var id: String { rawValue }
    var title: String { rawValue.capitalized }
}

@Model
final class ProgressPhoto {
    var id: UUID
    var takenAt: Date
    var poseRaw: String
    var fileName: String
    var weight: Double?
    var note: String
    // Stored per photo (offsets as a fraction of the frame) so every comparison
    // and the time-lapse use the same framing.
    var alignScale: Double
    var alignOffsetX: Double
    var alignOffsetY: Double

    init(takenAt: Date, pose: Pose, fileName: String) {
        id = UUID()
        self.takenAt = takenAt
        poseRaw = pose.rawValue
        self.fileName = fileName
        note = ""
        alignScale = 1
        alignOffsetX = 0
        alignOffsetY = 0
    }

    var pose: Pose {
        get { Pose(rawValue: poseRaw) ?? .front }
        set { poseRaw = newValue.rawValue }
    }
}
