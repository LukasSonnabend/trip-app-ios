import SwiftUI
import UIKit
import UniformTypeIdentifiers

class ShareViewController: UIViewController {
    private var extractedItems: [ItineraryItem] = []
    private var sharedContent: String?
    private var sharedURL: String?
    private var sharedFileData: (Data, String)?
    private var sharedMapLocation: ParsedMapLocation?

    override func viewDidLoad() {
        super.viewDidLoad()

        guard KeychainManager.shared.accessToken != nil else {
            let host = UIHostingController(rootView: NotAuthenticatedExtensionView {
                self.extensionContext?.completeRequest(returningItems: [])
            })
            embed(host)
            return
        }

        let rootView = ShareExtensionMainView(
            onDismiss: { [weak self] in
                self?.extensionContext?.completeRequest(returningItems: [])
            },
            extractedItems: extractedItems
        )
        let host = UIHostingController(rootView: rootView)
        embed(host)

        Task { await loadInput() }
    }

    private func embed(_ child: UIViewController) {
        addChild(child)
        view.addSubview(child.view)
        child.view.frame = view.bounds
        child.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        child.didMove(toParent: self)
    }

    private func loadInput() async {
        guard let items = extensionContext?.inputItems as? [NSExtensionItem],
              let item = items.first,
              let providers = item.attachments else { return }

        for provider in providers {
            // 1. PDF data first — a shared PDF also conforms to public.url/file-url,
            //    and we want the bytes, not the temp file path.
            if provider.hasItemConformingToTypeIdentifier(UTType.pdf.identifier) {
                if let pdfURL = try? await provider.loadItem(forTypeIdentifier: UTType.pdf.identifier) as? URL {
                    if let data = try? Data(contentsOf: pdfURL) {
                        sharedFileData = (data, pdfURL.lastPathComponent.isEmpty ? "document.pdf" : pdfURL.lastPathComponent)
                    }
                } else if let data = try? await provider.loadItem(forTypeIdentifier: UTType.pdf.identifier) as? Data {
                    sharedFileData = (data, "document.pdf")
                } else if let data = try? await provider.loadItem(forTypeIdentifier: UTType.data.identifier) as? Data {
                    sharedFileData = (data, "document.pdf")
                }
                continue
            }

            // 2. File URL — read its data immediately; use it only if it's a PDF.
            if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                if let fileURL = try? await provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier) as? URL {
                    if fileURL.pathExtension.lowercased() == "pdf",
                       let data = try? Data(contentsOf: fileURL) {
                        sharedFileData = (data, fileURL.lastPathComponent)
                        continue
                    }
                }
            }

            // 3. Web URL (skip local file paths, which don't mean anything to the backend).
            if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
                if let url = try? await provider.loadItem(forTypeIdentifier: UTType.url.identifier) as? URL {
                    if !url.isFileURL {
                        sharedURL = url.absoluteString
                        if let parsed = await MapURLLocationParser.parseResolving(url) {
                            sharedMapLocation = parsed
                        }
                    }
                }
                continue
            }

            // 4. Plain text.
            if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
                if let text = try? await provider.loadItem(forTypeIdentifier: UTType.plainText.identifier) as? String {
                    sharedContent = text
                }
                continue
            }
        }

        NotificationCenter.default.post(
            name: .shareInputReady,
            object: nil,
            userInfo: [
                "content": sharedContent as Any,
                "url": sharedURL as Any,
                "fileData": sharedFileData as Any,
                "mapLocation": sharedMapLocation as Any,
            ]
        )
    }
}

extension Notification.Name {
    static let shareInputReady = Notification.Name("shareInputReady")
}
