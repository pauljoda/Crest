import SwiftUI

/// Shared motion roles for Crest-authored transitions.
///
/// Crest names motion by semantic role so chrome, flows, controls, and collection
/// interactions never invent their own pacing. Anything longer belongs to native,
/// system-owned motion.
///
/// Never apply these animations directly. Route every Crest-authored animation
/// through `BrowserVisualAccessibilityPolicy.animation(_:reduceMotion:)` so the
/// system's Reduce Motion setting can drop the animation entirely:
///
/// ```swift
/// .animation(
///     BrowserVisualAccessibilityPolicy.animation(CrestMotion.pane, reduceMotion: reduceMotion),
///     value: selection
/// )
/// ```
enum CrestMotion {
    /// The deliberate hold that distinguishes a long press from an ordinary tap.
    static let longPressRecognitionDelay: TimeInterval = 0.55
    /// Swapping one pane of chrome for another inside a stable frame.
    static let paneTransition: TimeInterval = 0.22
    /// Advancing or retreating a step in a multi-step flow.
    static let stepTransition: TimeInterval = 0.30
    /// A control acknowledging a press.
    static let pressFeedback: TimeInterval = 0.14
    /// A compact control acknowledging a press without moving surrounding chrome.
    static let compactPressFeedback: TimeInterval = 0.12
    /// A dense developer control acknowledging a press.
    static let developerPressFeedback: TimeInterval = 0.16
    /// Hover and selection changes on compact interactive surfaces.
    static let surfaceTransition: TimeInterval = 0.12
    /// Inserting, removing, or reordering items in a collection.
    static let collectionTransition: TimeInterval = 0.22
    /// Morphing the content represented by an active drag preview.
    static let dragPreviewTransition: TimeInterval = 0.18
    /// Selecting a destination or changing a window's browsing mode.
    static let navigationTransition: TimeInterval = 0.28
    /// Showing or hiding the app's primary browser chrome.
    static let chromeTransition: TimeInterval = 0.28
    /// Showing or changing a secondary pane layered over browser chrome.
    static let floatingPaneTransition: TimeInterval = 0.24
    /// Showing or hiding compact toolbars within web content.
    static let toolbarTransition: TimeInterval = 0.24
    /// Removing transient feedback or secondary chrome.
    static let dismissalTransition: TimeInterval = 0.18
    /// Crossfading the window's material and branded base layers.
    static let windowBackdropTransition: TimeInterval = 0.16
    /// Hover feedback for sidebar rows.
    static let hoverTransition: TimeInterval = 0.14
    /// Expanding or collapsing a sidebar disclosure group.
    static let disclosureTransition: TimeInterval = 0.20
    /// Updating an address field's determinate loading fill.
    static let loadingProgressTransition: TimeInterval = 0.22
    /// Selecting a choice within an onboarding flow.
    static let selectionTransition: TimeInterval = 0.20
    /// Applying or removing the persistent visual state of a drag source.
    static let dragSourceTransition: TimeInterval = 0.20
    /// Aligning a programmatically selected item within a scrolling picker.
    static let scrollAlignmentTransition: TimeInterval = 0.24
    /// Handing visible content from the start page to a destination page.
    static let contentNavigationTransition: TimeInterval = 0.42
    /// Settling an interactive horizontal Space swipe.
    static let spaceSwipeTransition: TimeInterval = 0.32
    /// Presenting the standard Peek card from its source location.
    static let peekEntranceTransition: TimeInterval = 0.28
    /// Presenting Peek inside a Quick Window.
    static let quickPeekEntranceTransition: TimeInterval = 0.34
    /// Revealing initial Peek web content after its first commit.
    static let contentRevealTransition: TimeInterval = 0.12
    /// Updating a favicon-derived palette or comparable content state.
    static let paletteTransition: TimeInterval = 0.18
    /// Revealing or hiding recovery details after a navigation failure.
    static let recoveryTransition: TimeInterval = 0.18
    /// Updating the loaded state rendered inside a pinned-tab tile.
    static let contentStateTransition: TimeInterval = 0.22
    /// Presenting transient confirmation feedback in browser chrome.
    static let feedbackPresentationTransition: TimeInterval = 0.22
    /// Settling Peek after an interactive vertical drag.
    static let peekDragSettlementTransition: TimeInterval = 0.30
    /// Dismissing a Peek card back into browser chrome.
    static let peekDismissalTransition: TimeInterval = 0.22
    /// Revealing one destination in the utility fan.
    static let utilityFanRevealTransition: TimeInterval = 0.42
    /// Returning one destination into the collapsed utility fan.
    static let utilityFanDismissTransition: TimeInterval = 0.26
    /// Allows the utility fan's dismissal animation to finish before hiding it.
    static let utilityFanDismissCompletionDelay: Duration = .milliseconds(260)
    /// The complete press-and-return cycle for reload feedback.
    static let reloadFeedbackDuration: Duration = .milliseconds(240)
    /// One half of the reload feedback cycle.
    static let reloadFeedbackPhaseDuration: Duration = .milliseconds(120)
    /// SwiftUI animation APIs express the reload phase in seconds.
    static let reloadFeedbackPhaseSeconds: TimeInterval = 0.12

    static var pane: Animation { .snappy(duration: paneTransition) }
    static var step: Animation { .snappy(duration: stepTransition) }
    /// Uses SwiftUI's native default curve for full onboarding-step changes.
    static var onboardingStep: Animation { .default }
    /// Uses SwiftUI's native snappy curve for progress selection feedback.
    static var onboardingProgress: Animation { .snappy }
    /// Uses SwiftUI's native snappy curve for onboarding presentation state.
    static var onboardingPresentation: Animation { .snappy }
    static var press: Animation { .easeOut(duration: pressFeedback) }
    static var compactPress: Animation { .easeOut(duration: compactPressFeedback) }
    static var developerPress: Animation { .snappy(duration: developerPressFeedback) }
    static var surface: Animation { .easeInOut(duration: surfaceTransition) }
    static var collection: Animation { .snappy(duration: collectionTransition) }
    static var dragPreview: Animation { .smooth(duration: dragPreviewTransition) }
    static var navigation: Animation { .snappy(duration: navigationTransition) }
    static var chrome: Animation { .smooth(duration: chromeTransition) }
    static var floatingPane: Animation { .smooth(duration: floatingPaneTransition) }
    static var toolbar: Animation { .snappy(duration: toolbarTransition) }
    static var dismissal: Animation { .easeOut(duration: dismissalTransition) }
    static var windowBackdrop: Animation {
        .easeInOut(duration: windowBackdropTransition)
    }
    static var hover: Animation { .easeInOut(duration: hoverTransition) }
    static var disclosure: Animation { .snappy(duration: disclosureTransition) }
    static var loadingProgress: Animation {
        .smooth(duration: loadingProgressTransition)
    }
    static var selection: Animation { .easeInOut(duration: selectionTransition) }
    static var dragSource: Animation { .snappy(duration: dragSourceTransition) }
    static var scrollAlignment: Animation {
        .snappy(duration: scrollAlignmentTransition, extraBounce: 0)
    }
    static var contentNavigation: Animation {
        .snappy(duration: contentNavigationTransition, extraBounce: 0.04)
    }
    static var spaceSwipe: Animation {
        .snappy(duration: spaceSwipeTransition, extraBounce: 0)
    }
    static var peekEntrance: Animation {
        .spring(duration: peekEntranceTransition, bounce: 0.2)
    }
    static var quickPeekEntrance: Animation {
        .smooth(duration: quickPeekEntranceTransition)
    }
    static var contentReveal: Animation {
        .easeOut(duration: contentRevealTransition)
    }
    static var palette: Animation { .easeInOut(duration: paletteTransition) }
    static var recovery: Animation { .easeInOut(duration: recoveryTransition) }
    static var contentState: Animation { .snappy(duration: contentStateTransition) }
    static var feedbackPresentation: Animation {
        .snappy(duration: feedbackPresentationTransition)
    }
    static var peekDragSettlement: Animation {
        .snappy(duration: peekDragSettlementTransition)
    }
    static var peekDismissal: Animation { .snappy(duration: peekDismissalTransition) }
    static var utilityFanReveal: Animation {
        .smooth(duration: utilityFanRevealTransition, extraBounce: 0.05)
    }
    static var utilityFanDismiss: Animation {
        .smooth(duration: utilityFanDismissTransition, extraBounce: 0)
    }
    static var reloadTurnOut: Animation {
        .easeOut(duration: reloadFeedbackPhaseSeconds)
    }
    static var reloadTurnIn: Animation {
        .easeIn(duration: reloadFeedbackPhaseSeconds)
    }
}
