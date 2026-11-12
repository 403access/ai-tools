import AppKit
import SwiftUI

extension NSAttributedString.Key {
    /// Marks a command-bar range as an inserted `@reference`. The value is the
    /// `CommandItem` that produced it, so the editor can style and replace it.
    static let commandMention = NSAttributedString.Key("OpenCodeBarCommandMention")
}

/// Lets the palette place a chosen reference into the live editor.
@MainActor
final class CommandMentionEditor {
    weak var textView: CommandMentionTextView?

    func insert(_ item: CommandItem) {
        textView?.insertMention(item)
    }

    func focus() {
        guard let textView else { return }
        textView.window?.makeFirstResponder(textView)
    }
}

/// AppKit-backed command-bar input. SwiftUI's `TextField` cannot draw a capsule
/// around part of its text, so this small editor keeps the query as attributed
/// text and paints mention ranges itself.
struct CommandMentionField: NSViewRepresentable {
    @Binding var text: String
    let focusRequest: Int
    let onMentionChange: (CommandMentionContext?) -> Void
    let onEditorReady: (CommandMentionEditor) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let textView = CommandMentionTextView.make()
        textView.delegate = context.coordinator

        let scrollView = NSScrollView()
        scrollView.documentView = textView
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.horizontalScrollElasticity = .none
        scrollView.verticalScrollElasticity = .none
        scrollView.scrollerStyle = .overlay

        context.coordinator.textView = textView
        context.coordinator.editor.textView = textView
        context.coordinator.parent = self

        let editor = context.coordinator.editor
        DispatchQueue.main.async {
            self.onEditorReady(editor)
            editor.focus()
        }

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let textView = scrollView.documentView as? CommandMentionTextView else { return }

        if textView.frame.width < scrollView.contentSize.width {
            textView.setFrameSize(
                NSSize(
                    width: scrollView.contentSize.width,
                    height: CommandMentionTextView.lineHeight
                )
            )
        }

        if textView.string != text {
            textView.setPlainText(text)
        }

        if context.coordinator.lastFocusRequest != focusRequest {
            context.coordinator.lastFocusRequest = focusRequest
            DispatchQueue.main.async {
                context.coordinator.editor.focus()
            }
        }
    }

    static func dismantleNSView(_ scrollView: NSScrollView, coordinator: Coordinator) {
        coordinator.textView?.delegate = nil
        coordinator.textView = nil
        coordinator.editor.textView = nil
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: CommandMentionField
        let editor = CommandMentionEditor()
        weak var textView: CommandMentionTextView?
        var lastFocusRequest = 0

        init(_ parent: CommandMentionField) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard let textView else { return }
            if parent.text != textView.string {
                parent.text = textView.string
            }
            textView.scrollRangeToVisible(textView.selectedRange())
            reportMention()
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            reportMention()
        }

        /// Deletions that touch a reference remove the whole reference. Typing
        /// inside one dissolves the capsule instead of growing it.
        func textView(
            _ textView: NSTextView,
            shouldChangeTextIn affectedCharRange: NSRange,
            replacementString: String?
        ) -> Bool {
            guard let mentionView = textView as? CommandMentionTextView else { return true }

            if affectedCharRange.length == 0 {
                mentionView.dissolveMention(containing: affectedCharRange.location)
                return true
            }

            let expanded = mentionView.rangeExpandedToMentions(affectedCharRange)
            guard expanded != affectedCharRange else {
                mentionView.dissolveMentions(in: affectedCharRange)
                return true
            }
            guard (replacementString ?? "").isEmpty else {
                mentionView.dissolveMentions(in: affectedCharRange)
                return true
            }

            mentionView.textStorage?.replaceCharacters(in: expanded, with: "")
            mentionView.setSelectedRange(NSRange(location: expanded.location, length: 0))
            mentionView.didChangeText()
            return false
        }

        private func reportMention() {
            guard let textView else { return }
            let selection = textView.selectedRange()
            guard selection.length == 0 else {
                parent.onMentionChange(nil)
                return
            }
            parent.onMentionChange(
                CommandMentionTrigger.context(in: textView.string, caret: selection.location)
            )
        }
    }
}

// MARK: - Editor

@MainActor
final class CommandMentionTextView: NSTextView {
    static let lineHeight: CGFloat = 24

    private static let textFont = NSFont.systemFont(ofSize: 16, weight: .medium)

    static func make() -> CommandMentionTextView {
        let storage = NSTextStorage()
        let layoutManager = NSLayoutManager()
        storage.addLayoutManager(layoutManager)

        let container = NSTextContainer(
            size: NSSize(width: 1_000_000, height: lineHeight)
        )
        container.widthTracksTextView = false
        container.lineFragmentPadding = 0
        layoutManager.addTextContainer(container)

        let view = CommandMentionTextView(
            frame: NSRect(x: 0, y: 0, width: 320, height: lineHeight),
            textContainer: container
        )
        view.configure()
        return view
    }

    private func configure() {
        drawsBackground = false
        backgroundColor = .clear
        textColor = .labelColor
        insertionPointColor = NSColor(Theme.accent)
        font = Self.textFont
        isEditable = true
        isSelectable = true
        isRichText = false
        importsGraphics = false
        usesFontPanel = false
        allowsUndo = true
        smartInsertDeleteEnabled = false
        isAutomaticQuoteSubstitutionEnabled = false
        isAutomaticDashSubstitutionEnabled = false
        isAutomaticTextReplacementEnabled = false
        isAutomaticSpellingCorrectionEnabled = false
        isContinuousSpellCheckingEnabled = false
        isGrammarCheckingEnabled = false
        usesFindPanel = false
        focusRingType = .none
        textContainerInset = NSSize(width: 1, height: 2)
        selectedTextAttributes = [
            .backgroundColor: NSColor(Theme.accent).withAlphaComponent(0.22),
        ]

        minSize = NSSize(width: 0, height: Self.lineHeight)
        maxSize = NSSize(width: .greatestFiniteMagnitude, height: Self.lineHeight)
        isVerticallyResizable = false
        isHorizontallyResizable = true
        // Leave the document view free to grow past the clip view. Tracking the
        // scroll view's width would clip long commands instead of scrolling.
        autoresizingMask = []
        textContainer?.containerSize = NSSize(
            width: .greatestFiniteMagnitude,
            height: Self.lineHeight
        )
        textContainer?.widthTracksTextView = false

        typingAttributes = normalAttributes
    }

    override func drawBackground(in rect: NSRect) {
        super.drawBackground(in: rect)
        guard let layoutManager, let textContainer, let storage = textStorage else { return }

        storage.enumerateAttribute(
            .commandMention,
            in: NSRange(location: 0, length: storage.length)
        ) { value, characterRange, _ in
            guard value != nil else { return }
            let glyphRange = layoutManager.glyphRange(
                forCharacterRange: characterRange,
                actualCharacterRange: nil
            )
            layoutManager.enumerateEnclosingRects(
                forGlyphRange: glyphRange,
                withinSelectedGlyphRange: NSRange(location: NSNotFound, length: 0),
                in: textContainer
            ) { rect, _ in
                let drawRect = rect
                    .offsetBy(dx: self.textContainerOrigin.x, dy: self.textContainerOrigin.y)
                    .insetBy(dx: -6, dy: 0)
                let path = NSBezierPath(
                    roundedRect: drawRect,
                    xRadius: drawRect.height / 2,
                    yRadius: drawRect.height / 2
                )
                NSColor(Theme.accent).withAlphaComponent(0.15).setFill()
                path.fill()
                NSColor(Theme.accent).withAlphaComponent(0.32).setStroke()
                path.lineWidth = 1
                path.stroke()
            }
        }
    }

    func setPlainText(_ value: String) {
        let attributes = normalAttributes
        textStorage?.setAttributedString(
            NSAttributedString(string: value, attributes: attributes)
        )
        setSelectedRange(NSRange(location: (value as NSString).length, length: 0))
        typingAttributes = attributes
        scrollRangeToVisible(selectedRange())
    }

    func insertMention(_ item: CommandItem) {
        let title = item.title
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }

        let selection = selectedRange()
        let context = selection.length == 0
            ? CommandMentionTrigger.context(in: string, caret: selection.location)
            : nil
        let range = context?.range ?? selection

        let token = NSMutableAttributedString(
            string: "@\(title)",
            attributes: mentionAttributes(for: item)
        )
        // Keep a visible gap between the capsule and whatever is typed next.
        // The extra advance lives on the space so the capsule itself stays
        // tight around its own text.
        let spacer = NSMutableAttributedString(string: " ", attributes: normalAttributes)
        spacer.addAttribute(
            .kern,
            value: 8.0,
            range: NSRange(location: 0, length: spacer.length)
        )
        token.append(spacer)

        guard shouldChangeText(in: range, replacementString: token.string) else { return }
        textStorage?.replaceCharacters(in: range, with: token)
        setSelectedRange(
            NSRange(location: range.location + token.length, length: 0)
        )
        typingAttributes = normalAttributes
        didChangeText()
        scrollRangeToVisible(selectedRange())
    }

    /// Expands a deletion so a partly selected mention disappears as one token.
    func rangeExpandedToMentions(_ range: NSRange) -> NSRange {
        guard let storage = textStorage, range.length > 0 else { return range }
        var result = range
        storage.enumerateAttribute(
            .commandMention,
            in: NSRange(location: 0, length: storage.length)
        ) { value, mentionRange, _ in
            guard value != nil, NSIntersectionRange(range, mentionRange).length > 0 else {
                return
            }
            result = NSUnionRange(result, mentionRange)
        }
        return result
    }

    /// Removes capsule styling from a mention when the caret types inside it.
    func dissolveMention(containing location: Int) {
        guard let storage = textStorage, storage.length > 0 else { return }
        var target: NSRange?
        storage.enumerateAttribute(
            .commandMention,
            in: NSRange(location: 0, length: storage.length)
        ) { value, mentionRange, stop in
            guard value != nil else { return }
            if location > mentionRange.location, location < NSMaxRange(mentionRange) {
                target = mentionRange
                stop.pointee = true
            }
        }
        if let target {
            dissolveMentions(in: target)
        }
    }

    func dissolveMentions(in range: NSRange) {
        guard let storage = textStorage, storage.length > 0 else { return }
        let clipped = NSIntersectionRange(range, NSRange(location: 0, length: storage.length))
        guard clipped.length > 0 else { return }
        storage.removeAttribute(.commandMention, range: clipped)
    }

    private var normalAttributes: [NSAttributedString.Key: Any] {
        [
            .font: Self.textFont,
            .foregroundColor: NSColor.labelColor,
        ]
    }

    private func mentionAttributes(for item: CommandItem) -> [NSAttributedString.Key: Any] {
        [
            .commandMention: item,
            .font: Self.textFont,
            .foregroundColor: NSColor(Theme.accent),
        ]
    }
}
