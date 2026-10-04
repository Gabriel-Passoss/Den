import Testing
import Foundation
import DenMemory

@Test func aRepositoryIsFoundFromItsRootAndFromAnyFolderInside() throws {
    let scratch = try Scratch()
    defer { scratch.remove() }
    let repository = try scratch.folder("code/den")
    _ = try scratch.folder("code/den/.git")
    let deep = try scratch.folder("code/den/Packages/HarnessKit/Sources")

    let fromRoot = try #require(ProjectLocator.project(containing: repository))
    let fromInside = try #require(ProjectLocator.project(containing: deep))

    #expect(fromRoot.root.path == repository.standardizedFileURL.path)
    #expect(fromRoot.name == "den")
    #expect(fromInside == fromRoot)
}

@Test func aWorktreeBelongsToTheRepositoryItCameFrom() throws {
    let scratch = try Scratch()
    defer { scratch.remove() }
    let origin = try scratch.folder("code/den")
    let administrative = try scratch.folder("code/den/.git/worktrees/fix-login")
    let inside = try scratch.folder("worktrees/den/fix-login/apps/web")
    try scratch.write("gitdir: \(administrative.path)\n", to: "worktrees/den/fix-login/.git")

    let project = try #require(ProjectLocator.project(containing: inside))

    #expect(project == ProjectLocator.project(containing: origin))
    #expect(project.name == "den")
}

@Test func aWorktreeWithARelativePointerStillFindsItsRepository() throws {
    let scratch = try Scratch()
    defer { scratch.remove() }
    let origin = try scratch.folder("code/den")
    _ = try scratch.folder("code/den/.git/worktrees/side")
    let worktree = try scratch.folder("code/side")
    try scratch.write("gitdir: ../den/.git/worktrees/side", to: "code/side/.git")

    #expect(ProjectLocator.project(containing: worktree) == ProjectLocator.project(containing: origin))
}

@Test func aGitFileThatIsNotAWorktreePointerMakesTheFolderItsOwnProject() throws {
    let scratch = try Scratch()
    defer { scratch.remove() }
    let submodule = try scratch.folder("code/den/vendor/lib")
    try scratch.write("gitdir: ../../.git/modules/lib\n", to: "code/den/vendor/lib/.git")
    let unreadable = try scratch.folder("code/odd")
    try scratch.write("nada que se pareça com um ponteiro", to: "code/odd/.git")

    #expect(ProjectLocator.project(containing: submodule)?.root.path == submodule.standardizedFileURL.path)
    #expect(ProjectLocator.project(containing: unreadable)?.root.path == unreadable.standardizedFileURL.path)
}

@Test func aFolderOutsideAnyRepositoryHasNoProject() throws {
    let scratch = try Scratch()
    defer { scratch.remove() }
    let loose = try scratch.folder("downloads/coisas")

    #expect(ProjectLocator.project(containing: loose) == nil)
}

@Test func twoRepositoriesWithTheSameNameGetDifferentFoldersInTheWiki() {
    let work = ProjectIdentity(root: URL(fileURLWithPath: "/Users/gabi/work/Meu App"))
    let personal = ProjectIdentity(root: URL(fileURLWithPath: "/Users/gabi/personal/Meu App"))
    let again = ProjectIdentity(root: URL(fileURLWithPath: "/Users/gabi/work/Meu App/"))

    #expect(work.slug != personal.slug)
    #expect(work.slug == again.slug)
    #expect(work == again)
    #expect(work.slug.wholeMatch(of: /meu-app-[0-9a-f]{8}/) != nil)
    #expect(work.slug == "meu-app-" + String(work.slug.suffix(8)))
}
