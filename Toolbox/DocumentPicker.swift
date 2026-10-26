import SwiftUI
import UniformTypeIdentifiers
import UIKit

/// UIKit document picker presenter.
///
/// SwiftUI's .fileImporter never completed in this app: after
/// selecting a file and tapping 打开, the picker stayed open and
/// its completion handler never ran (confirmed on the v2 build
/// with local and iCloud files alike). This presenter bypasses
/// SwiftUI's picker wrapper entirely: it presents a real
/// UIDocumentPickerViewController from UIKit and reports the
/// picked URLs through its delegate, which is a UIKit-level
/// guarantee independent of SwiftUI's presentation machinery.
///
/// asCopy: true makes the system copy the picked files into the
/// app's container first, so the URLs handed to the delegate need
/// no security-scoped access dance; the caller still copies them
/// into Documents (the system copies may live in a temp location).
struct DocumentPickerPresenter: UIViewControllerRepresentable {
    var isPresented: Binding<Bool>
    var onPick: ([URL]) -> Void

    func makeUIViewController(context: Context) -> PickerHostViewController {
        PickerHostViewController(isPresented: isPresented, onPick: onPick)
    }

    func updateUIViewController(_ uiViewController: PickerHostViewController, context: Context) {
        uiViewController.isPresented = isPresented
        uiViewController.onPick = onPick
        uiViewController.updatePresentation()
    }
}

final class PickerHostViewController: UIViewController, UIDocumentPickerDelegate {
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
                forOpeningContentTypes: [UTType.html],
                asCopy: true
            )
            picker.delegate = self
            picker.allowsMultipleSelection = true
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
