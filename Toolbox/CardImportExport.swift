import SwiftUI
import UniformTypeIdentifiers
import UIKit

/// UIKit .txt picker for card-code import.
///
/// Same reason as the web viewer's DocumentPicker: SwiftUI's
/// .fileImporter never completed on this device (picker stayed
/// open, completion never ran), so import goes through a real
/// UIDocumentPickerViewController. asCopy: true copies the file
/// into the container first, so the URL needs no security-scoped
/// access dance.
struct TextFilePicker: UIViewControllerRepresentable {
    var isPresented: Binding<Bool>
    var onPick: ([URL]) -> Void

    func makeUIViewController(context: Context) -> TextPickerHostViewController {
        TextPickerHostViewController(isPresented: isPresented, onPick: onPick)
    }

    func updateUIViewController(_ uiViewController: TextPickerHostViewController, context: Context) {
        uiViewController.isPresented = isPresented
        uiViewController.onPick = onPick
        uiViewController.updatePresentation()
    }
}

final class TextPickerHostViewController: UIViewController, UIDocumentPickerDelegate {
    var isPresented: Binding<Bool>
    var onPick: ([URL]) -> Void

    init(isPresented: Binding<Bool>, onPick: @escaping ([URL]) -> Void) {
        self.isPresented = isPresented
        self.onPick = onPick
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func updatePresentation() {
        if isPresented.wrappedValue {
            guard presentedViewController == nil else { return }
            let picker = UIDocumentPickerViewController(
                forOpeningContentTypes: [UTType.plainText],
                asCopy: true
            )
            picker.delegate = self
            picker.allowsMultipleSelection = false
            present(picker, animated: true)
        } else if presentedViewController != nil {
            dismiss(animated: true)
        }
    }

    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        isPresented.wrappedValue = false
        onPick(urls)
    }

    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
        isPresented.wrappedValue = false
    }
}

/// UIKit share sheet for card-code export. Presented from a host
/// view controller so the exported .txt can be saved to Files or
/// sent elsewhere.
struct ActivityView: UIViewControllerRepresentable {
    var isPresented: Binding<Bool>
    var url: URL?

    func makeUIViewController(context: Context) -> ActivityHostViewController {
        ActivityHostViewController(isPresented: isPresented, url: url)
    }

    func updateUIViewController(_ uiViewController: ActivityHostViewController, context: Context) {
        uiViewController.isPresented = isPresented
        uiViewController.url = url
        uiViewController.updatePresentation()
    }
}

final class ActivityHostViewController: UIViewController {
    var isPresented: Binding<Bool>
    var url: URL?

    init(isPresented: Binding<Bool>, url: URL?) {
        self.isPresented = isPresented
        self.url = url
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func updatePresentation() {
        if isPresented.wrappedValue {
            guard presentedViewController == nil, let url = url else { return }
            let activity = UIActivityViewController(activityItems: [url], applicationActivities: nil)
            activity.completionWithItemsHandler = { [weak self] _, _, _, _ in
                self?.isPresented.wrappedValue = false
            }
            present(activity, animated: true)
        } else if presentedViewController != nil {
            dismiss(animated: true)
        }
    }
}
