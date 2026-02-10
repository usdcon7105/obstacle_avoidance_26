
//  FrameView.swift
//  obstacleAvoidance
//
//  Swift file that is used to startup the phone camera for viewing the frames.
//  Triggers audible notification for largest bounding box in view.
//

import SwiftUI

struct FrameView: View {

    // Minimum seconds between any two announcements (more silence, less overload)
    private let announceInterval: TimeInterval = 2.8
    // Consider distance "similar" if within this fraction of last announced (0.15 = 15%)
    private let distanceSimilarityTolerance: Float16 = 0.15
    // Delay after posting an announcement before allowing the next pop (VoiceOver is speaking)
    private let speakDelay: Double = 2.0

    @State private var lastAnnounceTime: Date = .distantPast
    @State private var lastAnnouncedObjectName: String?
    @State private var lastAnnouncedDistance: Float16?
    @State private var timer = Timer.publish(every: 0.01, on: .main, in: .common).autoconnect()
    @State private var clearTimer = Timer.publish(every: 3.0, on: .main, in: .common).autoconnect()
    @State private var isSpeaking: Bool = false

    var image: CGImage?
    var boundingBoxes: [BoundingBox]

    /// True if we should skip announcing (same object at similar distance, or too soon since last announcement).
    private func shouldSkipAnnouncement(objectName: String, distance: Float16) -> Bool {
        let now = Date()
        if now.timeIntervalSince(lastAnnounceTime) < announceInterval {
            return true
        }
        guard let lastName = lastAnnouncedObjectName, let lastDist = lastAnnouncedDistance else {
            return false
        }
        guard objectName == lastName else {
            return false
        }
        let epsilon: Float16 = 1e-6
        let ref = max(lastDist, epsilon)
        let relativeChange = abs(distance - lastDist) / ref
        return relativeChange <= distanceSimilarityTolerance
    }

    var body: some View {
        ZStack {
            if let image = image {
                Image(uiImage: UIImage(cgImage: image))
                    .resizable()
                    .scaledToFit()
            } else {
                Color.black
            }

            // Overlay bounding boxes on the image
            // Notify user of object with the biggest bounding box
            if let biggestBox = boundingBoxes.max(by: { $0.rect.width < $1.rect.width }) {
                ZStack {
                    Rectangle()
                        .stroke(Color.red, lineWidth: 2)
                        .frame(width: biggestBox.rect.width, height: biggestBox.rect.height)
                        .position(x: biggestBox.rect.midX, y: biggestBox.rect.midY)
                }
                .onReceive(timer) { _ in
                    guard !isSpeaking else { return }
                    guard let audioOutput = AudioQueue.popHighestPriorityObject(threshold: 1) else {
                        return
                    }

                    if shouldSkipAnnouncement(objectName: audioOutput.objName, distance: audioOutput.distance) {
                        AudioQueue.clearQueue()
                        return
                    }

                    isSpeaking = true
                    lastAnnounceTime = Date()
                    lastAnnouncedObjectName = audioOutput.objName
                    lastAnnouncedDistance = audioOutput.distance

                    let message = "\(audioOutput.objName) \(audioOutput.corridorPosition) \(audioOutput.formattedDist)"
                    AudioQueue.clearQueue()
                    DispatchQueue.main.async {
                        if UIAccessibility.isVoiceOverRunning {
                            UIAccessibility.post(notification: .announcement, argument: message)
                        }
                    }

                    DispatchQueue.main.asyncAfter(deadline: .now() + speakDelay) {
                        isSpeaking = false
                    }
                }
                .onReceive(clearTimer) { _ in
                    AudioQueue.clearQueue()
                }







                }
//                .onAppear {
//                    let now = Date()
//                    if now.timeIntervalSince(lastAnnounceTime) > announceInterval {
//
//                        UIAccessibility.post(notification:
//                                .announcement, argument: "\(biggestBox.name) at \(biggestBox.direction)")
//                        lastAnnounceTime = now
//                    }
//                }
            }
        }
    }



struct FrameViewPreviews: PreviewProvider {
    static var previews: some View {
        FrameView(image: nil, boundingBoxes: [])
    }
}
