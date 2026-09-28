//
//  PostHogSurveySheetDetentsTest.swift
//  PostHogTests
//
//  Created by Anna Garcia on 28/09/2026.
//

#if os(iOS)
    import Foundation
    @testable import PostHog
    import Testing

    @Suite("Survey sheet detents")
    struct PostHogSurveySheetDetentsTest {
        @available(iOS 15.0, *)
        @Test("a sheet shorter than the window gets a detent of its own height")
        func shortSheetGetsItsOwnHeight() {
            #expect(SurveyPresentationDetentsRepresentable.detents(forSheetHeight: 400, availableHeight: 844) == [.height(400)])
        }

        @available(iOS 15.0, *)
        @Test("a sheet taller than the window can be expanded")
        func tallSheetIsExpandable() {
            #expect(SurveyPresentationDetentsRepresentable.detents(forSheetHeight: 900, availableHeight: 844) == [.medium, .large])
            #expect(SurveyPresentationDetentsRepresentable.detents(forSheetHeight: 844, availableHeight: 844) == [.medium, .large])
        }

        /// iPhone Duo, unfolded in landscape: the window is 669pt tall on the inner display while
        /// `UIScreen.main` still reports the 678pt outer display. A sheet between the two doesn't fit.
        /// Unfolded in portrait the window is 951pt tall, so sheets between 678 and 951pt used to be
        /// shown at half height even though they fit.
        @available(iOS 15.0, *)
        @Test("a sheet taller than the window but shorter than the main screen can be expanded")
        func sheetBetweenWindowAndMainScreenIsExpandable() {
            #expect(SurveyPresentationDetentsRepresentable.detents(forSheetHeight: 672, availableHeight: 669) == [.medium, .large])
        }
    }
#endif
