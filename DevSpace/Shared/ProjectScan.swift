import Foundation

nonisolated enum ProjectScan {
    static let skippedFolders: Set<String> = [
        "node_modules", ".git", ".build", "DerivedData", ".next", "dist", "build",
        "Pods", ".venv", "vendor",
    ]
}
