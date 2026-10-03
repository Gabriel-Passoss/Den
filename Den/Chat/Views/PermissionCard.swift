import SwiftUI
import HarnessCore

struct PermissionCard: View {
    let request: PermissionRequest
    let harnessName: String
    var resolve: (PermissionOption) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.shield")
                    .font(.system(size: 14, weight: .medium))
                Text("\(harnessName) pede permissão para usar \(request.displayName ?? request.toolName)")
                    .font(.system(size: 13, weight: .medium))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .foregroundStyle(Theme.alertText)

            if let detail = detail(of: request) {
                Text(detail)
                    .font(.system(size: 12.5, design: .monospaced))
                    .foregroundStyle(Theme.text)
                    .textSelection(.enabled)
                    .lineLimit(4)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.terminal, in: RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(Theme.border, lineWidth: 1))
            }

            HStack(spacing: 8) {
                ForEach(request.options, id: \.id) { option in
                    let button = Button {
                        resolve(option)
                    } label: {
                        Text(option.label).pillLabel()
                    }

                    if option.kind == .allowOnce {
                        button
                            .buttonStyle(.denPrimary)
                            .keyboardShortcut(.defaultAction)
                    } else {
                        button.buttonStyle(.denSecondary)
                    }
                }
                Spacer(minLength: 0)
            }
        }
        .padding(14)
        .background(Theme.alertFill, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
            .strokeBorder(Theme.alertBorder, lineWidth: 1))
    }

    private func detail(of request: PermissionRequest) -> String? {
        request.input["command"]?.stringValue
        ?? request.input["file_path"]?.stringValue
        ?? request.description
    }
}
