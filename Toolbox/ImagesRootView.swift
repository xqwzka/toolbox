import SwiftUI
import SwiftData
import UIKit

/// Image library: an independent page, like 卡密 but for
/// pictures. Import from Photos (multi-select, no full
/// library access needed — PHPicker only hands over what
/// the user picked) or from Files, then tap any thumbnail
/// to copy that image to the system pasteboard, ready to
/// paste into WeChat, Notes, or any app that accepts images.
/// Files live under Documents/images; the SwiftData record
/// only stores the file name, so the database stays small.
struct ImagesRootView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \StoredImage.createdAt, order: .reverse) private var images: [StoredImage]

    @State private var showingPhotoPicker = false
    @State private var showingFilePicker = false
    @State private var viewingImage: StoredImage?
    @State private var toastVisible = false
    @State private var toastText = "已复制图片"
    @State private var toastID = 0

    private let columns = [
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8),
    ]

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                VStack(spacing: 0) {
                    HStack(spacing: 0) {
                        VStack(spacing: 4) {
                            Text("\(images.count) 张")
                                .font(.title3)
                                .fontWeight(.bold)
                            Text("共")
                                .font(.caption)
                                .foregroundColor(.gray)
                        }
                        .frame(maxWidth: .infinity)
                        VStack(spacing: 4) {
                            Text("点图片即复制")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                            Text("长按可查看大图 / 删除")
                                .font(.caption)
                                .foregroundColor(.gray)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .padding(.vertical, 16)
                    .padding(.horizontal, 16)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 8)

                    if images.isEmpty {
                        VStack(spacing: 12) {
                            Image(systemName: "photo.fill")
                                .font(.largeTitle)
                                .foregroundColor(.gray)
                            Text("暂无图片，点右上角 + 导入")
                                .foregroundColor(.gray)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        ScrollView {
                            LazyVGrid(columns: columns, spacing: 8) {
                                ForEach(images) { item in
                                    Button {
                                        copy(item)
                                    } label: {
                                        ImageThumbView(item: item)
                                    }
                                    .buttonStyle(.plain)
                                    .contextMenu {
                                        Button {
                                            viewingImage = item
                                        } label: {
                                            Label("查看大图", systemImage: "eye")
                                        }
                                        Button {
                                            copy(item)
                                        } label: {
                                            Label("复制图片", systemImage: "doc.on.doc")
                                        }
                                        Button(role: .destructive) {
                                            delete(item)
                                        } label: {
                                            Label("删除", systemImage: "trash")
                                        }
                                    }
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.bottom, 24)
                        }
                    }
                }
                if toastVisible {
                    ImageToastView(text: toastText)
                        .padding(.bottom, 24)
                }
            }
            .background(CardTheme.background.ignoresSafeArea())
            .navigationTitle("图片")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            showingPhotoPicker = true
                        } label: {
                            Label("从相册导入", systemImage: "photo")
                        }
                        Button {
                            showingFilePicker = true
                        } label: {
                            Label("从文件导入", systemImage: "folder")
                        }
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .background(
                ImagePhotoPicker(isPresented: $showingPhotoPicker) { picked in
                    importPicked(picked)
                }
            )
            .background(
                ImageFilePicker(isPresented: $showingFilePicker) { urls in
                    importFiles(urls)
                }
            )
            .sheet(item: $viewingImage) { item in
                ImageDetailView(item: item, onCopy: {
                    copy(item)
                    viewingImage = nil
                }, onDelete: {
                    delete(item)
                    viewingImage = nil
                })
            }
        }
    }

    /// Tap = copy, like 卡密's tap-to-copy. The pasteboard
    /// takes a UIImage, so a HEIC import pastes as a readable
    /// image in the receiving app; the stored file itself is
    /// left untouched.
    private func copy(_ item: StoredImage) {
        guard let image = item.image else {
            showToast("这张图读不出来")
            return
        }
        UIPasteboard.general.image = image
        showToast("已复制图片")
    }

    private func delete(_ item: StoredImage) {
        StoredImage.deleteFile(named: item.fileName)
        context.delete(item)
    }

    private func importPicked(_ picked: [(data: Data, ext: String)]) {
        var count = 0
        for entry in picked {
            if let record = StoredImage.saveImageData(entry.data, ext: entry.ext) {
                context.insert(record)
                count += 1
            }
        }
        showToast(count == 0 ? "没有可导入的图片" : "导入 \(count) 张")
    }

    private func importFiles(_ urls: [URL]) {
        var count = 0
        for url in urls {
            guard let data = try? Data(contentsOf: url) else { continue }
            let ext = url.pathExtension.isEmpty ? "jpg" : url.pathExtension
            if let record = StoredImage.saveImageData(data, ext: ext) {
                context.insert(record)
                count += 1
            }
        }
        showToast(count == 0 ? "没有可导入的图片" : "导入 \(count) 张")
    }

    private func showToast(_ message: String) {
        toastID += 1
        let currentID = toastID
        toastText = message
        toastVisible = true
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            if toastID == currentID {
                toastVisible = false
            }
        }
    }
}

/// One square thumbnail, loaded off the main thread like the
/// download page's video thumbnails. The full file is only
/// decoded for the detail view, not for the grid cell itself
/// beyond what UIKit needs to draw the tile.
private struct ImageThumbView: View {
    let item: StoredImage
    @State private var thumb: UIImage?

    var body: some View {
        ZStack {
            if let thumb {
                Image(uiImage: thumb)
                    .resizable()
                    .scaledToFill()
            } else {
                Color.gray.opacity(0.2)
                Image(systemName: "photo")
                    .foregroundColor(.gray)
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .task {
            // Capture only the file path, not the model object:
            // the detached task runs off the main actor.
            let path = item.fileURL.path
            let image = await Task.detached { () -> UIImage? in
                UIImage(contentsOfFile: path)
            }.value
            if !Task.isCancelled {
                thumb = image
            }
        }
    }
}

/// Full-size preview with explicit copy and delete actions.
/// Copy dismisses back to the grid so the "已复制图片"
/// toast underneath is visible.
private struct ImageDetailView: View {
    let item: StoredImage
    let onCopy: () -> Void
    let onDelete: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                if let image = item.image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity)
                } else {
                    Text("这张图读不出来")
                        .foregroundColor(.gray)
                        .padding(.top, 48)
                }
            }
            .navigationTitle("图片")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("关闭") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(role: .destructive) { onDelete() } label: {
                        Image(systemName: "trash")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("复制图片") { onCopy() }
                        .buttonStyle(.borderedProminent)
                }
            }
        }
    }
}

private struct ImageToastView: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.subheadline)
            .foregroundColor(.white)
            .padding(.vertical, 10)
            .padding(.horizontal, 20)
            .background(Color.black.opacity(0.85))
            .clipShape(Capsule())
            .shadow(color: Color.black.opacity(0.2), radius: 8, y: 2)
    }
}
