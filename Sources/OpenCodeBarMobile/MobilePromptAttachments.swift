import Foundation
import PhotosUI
import SwiftUI
import UIKit

/// An image the user picked for a prompt but has not sent yet.
struct PromptDraftAttachment: Identifiable, Equatable {
    let id = UUID()
    var name: String
    var mime: String
    var data: Data
    var thumbnail: UIImage

    static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id }

    /// Builds the OpenCode prompt-input attachment (inline data URI).
    func toInput() -> PromptFileAttachmentInput {
        PromptFileAttachmentInput(
            uri: "data:\(mime);base64,\(data.base64EncodedString())",
            source: .inline,
            name: name
        )
    }

    /// Loads and compresses a picked photo so prompt bodies stay reasonable.
    static func load(from item: PhotosPickerItem) async -> PromptDraftAttachment? {
        guard let data = try? await item.loadTransferable(type: Data.self),
              let image = UIImage(data: data)
        else { return nil }

        let prepared = prepare(image: image)
        let name = item.itemIdentifier.map { "photo-\($0.suffix(8)).jpg" } ?? "photo.jpg"
        return PromptDraftAttachment(
            name: name,
            mime: "image/jpeg",
            data: prepared.data,
            thumbnail: prepared.thumbnail
        )
    }

    private static func prepare(image: UIImage) -> (data: Data, thumbnail: UIImage) {
        let maxDimension: CGFloat = 1600
        let size = image.size
        let scale = min(1, maxDimension / max(size.width, size.height))
        let target = CGSize(width: floor(size.width * scale), height: floor(size.height * scale))
        let renderer = UIGraphicsImageRenderer(size: target)
        let resized = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
        let data = resized.jpegData(compressionQuality: 0.82) ?? Data()
        let thumbSize = CGSize(width: 72, height: 72)
        let thumb = UIGraphicsImageRenderer(size: thumbSize).image { _ in
            let fill = max(thumbSize.width / max(size.width, 1), thumbSize.height / max(size.height, 1))
            let draw = CGSize(width: size.width * fill, height: size.height * fill)
            let origin = CGPoint(x: (thumbSize.width - draw.width) / 2, y: (thumbSize.height - draw.height) / 2)
            resized.draw(in: CGRect(origin: origin, size: draw))
        }
        return (data, thumb)
    }
}

/// Horizontal strip of prompt image attachments with remove buttons.
/// Tap an image to preview it full-screen before sending.
struct PromptAttachmentStrip: View {
    @Binding var attachments: [PromptDraftAttachment]
    var disabled: Bool = false
    @State private var preview: PromptDraftAttachment?

    var body: some View {
        if !attachments.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(attachments) { item in
                        ZStack(alignment: .topTrailing) {
                            Button {
                                preview = item
                            } label: {
                                Image(uiImage: item.thumbnail)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 56, height: 56)
                                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                                            .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
                                    )
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Preview image")
                            .accessibilityHint("Shows the full image. Use the remove button to detach it.")

                            if !disabled {
                                Button {
                                    attachments.removeAll { $0.id == item.id }
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.system(size: 16, weight: .semibold))
                                        .symbolRenderingMode(.palette)
                                        .foregroundStyle(.white, .black.opacity(0.55))
                                }
                                .buttonStyle(.plain)
                                .offset(x: 5, y: -5)
                                .accessibilityLabel("Remove image")
                            }
                        }
                    }
                }
                .padding(.vertical, 2)
            }
            .sheet(item: $preview) { item in
                PromptAttachmentPreview(attachment: item) {
                    attachments.removeAll { $0.id == item.id }
                    preview = nil
                }
            }
        }
    }
}

private struct PromptAttachmentPreview: View {
    let attachment: PromptDraftAttachment
    var onRemove: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                if let image = UIImage(data: attachment.data) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .accessibilityLabel(attachment.name)
                }
            }
            .navigationTitle(attachment.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .destructiveAction) {
                    Button("Remove", role: .destructive) {
                        onRemove()
                        dismiss()
                    }
                }
            }
        }
    }
}
