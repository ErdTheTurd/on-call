import SwiftUI
import Combine
import UniformTypeIdentifiers

@MainActor
final class DocumentUploadService: ObservableObject {
    static let shared = DocumentUploadService()

    @Published var uploadedDocuments: [UploadedDocument] = []
    private let storageKey = "uploaded_documents_v1"

    struct UploadedDocument: Identifiable, Codable {
        let id: UUID
        let fileName: String
        let uploadedAt: Date
        var reviewStatus: ReviewStatus

        enum ReviewStatus: String, Codable { case pending, approved, rejected }
    }

    init() { load() }

    func registerUpload(fileName: String) {
        uploadedDocuments.append(UploadedDocument(
            id: UUID(), fileName: fileName, uploadedAt: Date(), reviewStatus: .pending
        ))
        save()
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let docs = try? JSONDecoder().decode([UploadedDocument].self, from: data) else { return }
        uploadedDocuments = docs
    }

    private func save() {
        if let data = try? JSONEncoder().encode(uploadedDocuments) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }
}

struct DocumentPickerButton: View {
    let label: String
    let onPick: (String) -> Void

    var body: some View {
        Button {
            onPick("\(label.replacingOccurrences(of: " ", with: "")).pdf")
        } label: {
            Label("Upload \(label)", systemImage: "doc.badge.plus")
                .font(.subheadline.weight(.semibold))
        }
        .buttonStyle(.bordered)
    }
}
