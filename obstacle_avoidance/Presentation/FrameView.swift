
//  FrameView.swift
//  obstacleAvoidance
//
//  Swift file that is used to startup the phone camera for viewing the frames.
//  Triggers audible notification for largest bounding box in view.
//

import SwiftUI

struct FrameView: View {

    // Delay after posting an announcement before allowing the next pop (VoiceOver is speaking)
    private let speakDelay: Double = 2.0

    @State private var timer = Timer.publish(every: 0.01, on: .main, in: .common).autoconnect()
    @State private var clearTimer = Timer.publish(every: 3.0, on: .main, in: .common).autoconnect()
    @State private var isSpeaking: Bool = false

    var image: CGImage?
    var boundingBoxes: [BoundingBox]

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
            }
        }
        .onReceive(timer) { _ in
            guard !isSpeaking else { return }
            guard let audioOutput = AudioQueue.popNextAnnouncement(threshold: 1) else {
                return
            }
            isSpeaking = true

            let message = audioOutput.announcementMessage
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
}



struct FrameViewPreviews: PreviewProvider {
    static var previews: some View {
        FrameView(image: nil, boundingBoxes: [])
    }
}
