import Foundation
import Testing

@testable import CapApp

@Suite("HUDPresentation")
struct HUDPresentationTests {
    @Test("A capture shows immediately and starts the success timer")
    func captureStartsTimer() {
        var presentation = HUDPresentation()

        let action = presentation.show(captured)

        #expect(action == .restart(.seconds(3)))
        #expect(presentation.display == HUDPresentation.Display(content: captured, streak: 1))
    }

    @Test("Consecutive captures coalesce into a streak")
    func consecutiveCapturesCoalesce() {
        var presentation = HUDPresentation()

        _ = presentation.show(captured)
        let action = presentation.show(secondCapture)

        #expect(action == .restart(.seconds(3)))
        #expect(presentation.display?.content == secondCapture)
        #expect(presentation.display?.streak == 2)
    }

    @Test("A failure replaces the streak and holds longer")
    func failureBreaksStreak() {
        var presentation = HUDPresentation()

        _ = presentation.show(captured)
        _ = presentation.show(secondCapture)
        let action = presentation.show(failed)

        #expect(action == .restart(.seconds(6)))
        #expect(presentation.display?.streak == 1)
    }

    @Test("A duplicate gets the middle duration and no streak")
    func duplicateDuration() {
        var presentation = HUDPresentation()

        _ = presentation.show(captured)
        let action = presentation.show(duplicate)

        #expect(action == .restart(.seconds(4)))
        #expect(presentation.display?.streak == 1)
    }

    @Test("Hover pauses the timer; leaving restarts it for the visible style")
    func hoverPausesAndResumes() {
        var presentation = HUDPresentation()

        _ = presentation.show(duplicate)

        #expect(presentation.hoverChanged(true) == .stop)
        #expect(presentation.hoverChanged(false) == .restart(.seconds(4)))
    }

    @Test("A capture landing under the cursor shows but leaves the timer paused")
    func showWhileHoveringStaysPaused() {
        var presentation = HUDPresentation()

        _ = presentation.show(captured)
        _ = presentation.hoverChanged(true)
        let action = presentation.show(secondCapture)

        #expect(action == .stop)
        #expect(presentation.display?.streak == 2)
    }

    @Test("Hover on an empty toast decides nothing")
    func hoverWithoutDisplay() {
        var presentation = HUDPresentation()

        #expect(presentation.hoverChanged(true) == .none)
    }

    @Test("Annotation only starts on annotatable content")
    func annotationRequiresCaptureID() {
        var presentation = HUDPresentation()

        _ = presentation.show(blocked)

        #expect(presentation.beginAnnotation() == false)
        #expect(presentation.isAnnotating == false)
    }

    @Test("A capture during annotation is buffered, not shown")
    func annotationBuffersIncoming() {
        var presentation = HUDPresentation()

        _ = presentation.show(captured)
        let began = presentation.beginAnnotation()
        let action = presentation.show(failed)

        #expect(began)

        #expect(action == HUDPresentation.TimerAction.none)
        #expect(presentation.display?.content == captured)
        #expect(presentation.buffered == failed)
    }

    @Test("Abandoning annotation restarts the timer for the visible content")
    func abandonRestartsTimer() {
        var presentation = HUDPresentation()

        _ = presentation.show(duplicate)
        _ = presentation.beginAnnotation()
        let action = presentation.abandonAnnotation()

        #expect(action == .restart(.seconds(4)))
        #expect(presentation.isAnnotating == false)
        #expect(presentation.display?.content == duplicate)
    }

    @Test("Abandoning annotation promotes a buffered capture")
    func abandonPromotesBuffered() {
        var presentation = HUDPresentation()

        _ = presentation.show(captured)
        _ = presentation.beginAnnotation()
        _ = presentation.show(secondCapture)
        let action = presentation.abandonAnnotation()

        #expect(action == .restart(.seconds(3)))
        #expect(presentation.display?.content == secondCapture)
        #expect(presentation.display?.streak == 2)
        #expect(presentation.buffered == nil)
    }

    @Test("Dismissing clears the toast and stops the clock")
    func dismissClears() {
        var presentation = HUDPresentation()

        _ = presentation.show(captured)
        let action = presentation.dismiss()

        #expect(action == .stop)
        #expect(presentation.display == nil)
    }

    @Test("Dismissing mid-annotation shows the buffered capture instead of hiding")
    func dismissShowsBuffered() {
        var presentation = HUDPresentation()

        _ = presentation.show(captured)
        _ = presentation.beginAnnotation()
        _ = presentation.show(failed)
        let action = presentation.dismiss()

        #expect(action == .restart(.seconds(6)))
        #expect(presentation.display?.content == failed)
        #expect(presentation.isAnnotating == false)
    }

    @Test("Dismissing while hovering does not leave the next toast timerless")
    func dismissResetsHover() {
        var presentation = HUDPresentation()

        _ = presentation.show(captured)
        _ = presentation.hoverChanged(true)
        _ = presentation.dismiss()
        let action = presentation.show(secondCapture)

        #expect(action == .restart(.seconds(3)))
    }

    @Test("A streak does not survive a dismissal")
    func streakResetsAfterDismiss() {
        var presentation = HUDPresentation()

        _ = presentation.show(captured)
        _ = presentation.dismiss()
        _ = presentation.show(secondCapture)

        #expect(presentation.display?.streak == 1)
    }
}

private let captured = HUDContent(
    style: .captured, captureID: 1, headline: "Captured", detail: "example.com")
private let secondCapture = HUDContent(
    style: .captured, captureID: 2, headline: "Captured", detail: "example.org")
private let duplicate = HUDContent(
    style: .duplicate, captureID: 3, headline: "Already captured 2 min. ago", detail: nil)
private let blocked = HUDContent(
    style: .blocked, headline: "Capture blocked", detail: "Secure input is active.")
private let failed = HUDContent(
    style: .failed, headline: "Capture failed", detail: nil)
