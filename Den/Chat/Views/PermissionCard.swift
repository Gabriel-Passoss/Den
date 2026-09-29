import SwiftUI
import HarnessCore

struct PermissionCard: View {
    let request: PermissionRequest
    let harnessName: String
    var resolve: (PermissionOption) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(.orange)
                Text("Permissão necessária")
                    .font(.system(size: 12, weight: .semibold))
            }

            Text("\(harnessName) quer usar \(request.displayName ?? request.toolName).")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

            if let detail = detail(of: request) {
                Text(detail)
                    .font(.system(size: 11, design: .monospaced))
                    .textSelection(.enabled)
                    .lineLimit(4)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 7)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 6))
            }

            HStack(spacing: 8) {
                Spacer()
                ForEach(request.options, id: \.id) { option in
                    let button = Button(option.label) {
                        resolve(option)
                    }

                    if option.kind == .allowOnce {
                        button.keyboardShortcut(.defaultAction)
                    } else {
                        button
                    }
                }
            }
        }
        .padding(12)
        .background(Color.orange.opacity(0.09), in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10).stroke(Color.orange.opacity(0.35), lineWidth: 1)
        )
    }

    private func detail(of request: PermissionRequest) -> String? {
        request.input["command"]?.stringValue
        ?? request.input["file_path"]?.stringValue
        ?? request.description
    }
}
