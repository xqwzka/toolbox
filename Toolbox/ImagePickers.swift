import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
import UIKit

/// Pick images from Photos without needing full library access:
/// PHPicker only hands over what the user chose. Same host
/// pattern as the download page's video picker, but the
/// filter is images and the selection limit is 0 (unlimited),
/// and results are collected as raw data so the caller can
/// save them without a second trip through the provider.
/// All results arrive in one onPick call, so the caller can
/// show a single "导入 N 张" toast.
struct ImagePhotoPicker: UIViewControllerRepresentable {
    var isPresented: Binding<Bool>
    var onPick: ([(data: Data, ext: String)]) -> Void

    func makeUIViewController(context: Context) -> ImagePhotoPickerHostViewController {
        ImagePhotoPickerHostViewController(isPresented: isPresented, onPick: onPick)
    }

    func updateUIViewController(_ uiViewController: ImagePhotoPickerHostViewController, context: Context) {
        uiViewController.isPresented = isPresented
        uiViewController.onPick = onPick
        uiViewController.updatePresentation()
    }
}

final class ImagePhotoPickerHostViewController: UIViewController, PHPickerViewControllerDelegate {
    var isPresented: Binding<Bool>
    var onPick: ([(data: Data, ext: String)]) -> Void

    init(isPresented: Binding<Bool>, onPick: @escaping ([(data: Data, ext: String)]) -> Void) {
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
            var configuration = PHPickerConfiguration()
            configuration.filter = .images
            configuration.selectionLimit = 0
            let picker = PHPickerViewController(configuration: configuration)
            picker.delegate = self
            present(picker, animated: true)
        } else if presentedViewController != nil {
            dismiss(animated: true)
        }
    }

    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        isPresented.wrappedValue = false
        guard !results.isEmpty else { return }
        let group = DispatchGroup()
        var picked: [(data: Data, ext: String)] = []
        let lock = NSLock()
        for result in results {
            let provider = result.itemProvider
            guard let typeID = provider.registeredTypeIdentifiers.first(where: { UTType($0)?.conforms(to: .image) == true }) else { continue }
            group.enter()
            provider.loadDataRepresentation(forTypeIdentifier: typeID) { data, _ in
                defer { group.leave() }
                guard let data else { return }
                let ext = UTType(typeID)?.preferredFilenameExtension ?? "jpg"
                lock.lock()
                picked.append((data: data, ext: ext))
                lock.unlock()
            }
        }
        group.notify(queue: .main) { [weak self] in
            self?.onPick(picked)
        }
    }
}

/// Pick image files from Files. Same reason as the other
/// UIKit document pickers in this app: SwiftUI's
/// .fileImporter never completed on the user's device.
/// asCopy: true makes the system copy the picked files
/// into the app's container first, so the URLs handed to
/// the delegate can be read directly.
struct ImageFilePicker: UIViewControllerRepresentable {
    var isPresented: Binding<Bool>
    var onPick: ([URL]) -> Void

    func makeUIViewController(context: Context) -> ImageFilePickerHostViewController {
        ImageFilePickerHostViewController(isPresented: isPresented, onPick: onPick)
    }

    func updateUIViewController(_ uiViewController: ImageFilePickerHostViewController, context: Context) {
        uiViewController.isPresented = isPresented
        uiViewController.onPick = onPick
        uiViewController.updatePresentation()
    }
}

final class ImageFilePickerHostViewController: UIViewController, UIDocumentPickerDelegate {
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
                forOpeningContentTypes: [UTType.image],
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
