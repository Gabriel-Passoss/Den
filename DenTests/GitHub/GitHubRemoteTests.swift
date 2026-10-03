import Testing
import Foundation
@testable import Den

private let expected = GitHubRemote(host: "github.com", owner: "den", name: "app")

@Test func httpsRemotesAreRead() {
    #expect(GitHubRemote(remoteURL: "https://github.com/den/app.git") == expected)
    #expect(GitHubRemote(remoteURL: "https://github.com/den/app") == expected)
    #expect(GitHubRemote(remoteURL: "http://GitHub.com/den/app\n") == expected)
}

@Test func sshRemotesAreRead() {
    #expect(GitHubRemote(remoteURL: "git@github.com:den/app.git") == expected)
    #expect(GitHubRemote(remoteURL: "ssh://git@github.com/den/app") == expected)
    #expect(GitHubRemote(remoteURL: "ssh://git@github.com:22/den/app.git") == expected)
}

@Test func anEnterpriseHostIsKept() {
    #expect(GitHubRemote(remoteURL: "git@git.acme.com:den/app.git")
            == GitHubRemote(host: "git.acme.com", owner: "den", name: "app"))
}

@Test func localAndMalformedRemotesAreNotGitHub() {
    #expect(GitHubRemote(remoteURL: "../origin.git") == nil)
    #expect(GitHubRemote(remoteURL: "/tmp/origin.git") == nil)
    #expect(GitHubRemote(remoteURL: "file:///tmp/origin.git") == nil)
    #expect(GitHubRemote(remoteURL: "https://github.com/onlyowner") == nil)
}
