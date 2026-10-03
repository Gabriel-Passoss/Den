import XCTest

/// Drives the real app through its accessibility tree. Each test gets its own
/// data root and fake CLIs, so no real session, preference or CLI is touched.
///
/// This runner is sandboxed: it can read anywhere but write only inside its
/// container, which the app cannot reach. So the app owns the data root, under
/// /tmp, and the fake CLIs' steps travel in the launch environment.
final class ConversationUITests: XCTestCase {
    private var root: URL!
    private var claude: FakeCLI!
    private var openCode: FakeCLI!

    private let patience: TimeInterval = 15

    override func setUpWithError() throws {
        continueAfterFailure = false
        root = URL(fileURLWithPath: "/private/tmp")
            .appending(path: "DenUITests-" + UUID().uuidString)
        claude = try FakeCLI(appRoot: root, harness: "claude-code")
        openCode = try FakeCLI(appRoot: root, harness: "opencode")
    }

    override func tearDownWithError() throws {
        claude.remove()
        openCode.remove()
    }

    @MainActor
    private func launch(projectSetup: String? = nil,
                        extraEnvironment: [String: String] = [:]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["DEN_UI_TEST_ROOT"] = root.path
        app.launchEnvironment["DEN_PROJECT_SETUP"] = projectSetup
        app.launchEnvironment.merge(extraEnvironment) { $1 }
        for cli in [claude!, openCode!] {
            app.launchEnvironment.merge(cli.launchEnvironment) { $1 }
        }
        app.launchEnvironment["DEN_CLI_claude-code"] = claude.executable
        app.launchEnvironment["DEN_CLI_opencode"] = openCode.executable
        app.launch()
        return app
    }

    /// Fails with the accessibility tree attached, which is what to read when a
    /// query stops matching.
    @MainActor
    private func require(_ element: XCUIElement, in app: XCUIApplication,
                         file: StaticString = #filePath, line: UInt = #line) {
        guard !element.waitForExistence(timeout: patience) else { return }
        let tree = XCTAttachment(string: app.debugDescription)
        tree.name = "accessibility tree"
        tree.lifetime = .keepAlways
        add(tree)
        XCTFail("never appeared: \(element)", file: file, line: line)
    }

    @MainActor
    private func text(containing fragment: String, in app: XCUIApplication) -> XCUIElement {
        app.staticTexts.containing(NSPredicate(format: "value CONTAINS %@ OR label CONTAINS %@",
                                               fragment, fragment)).firstMatch
    }

    @MainActor
    private func sidebarRow(_ title: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: "Sidebar").firstMatch
            .staticTexts[title]
    }

    @MainActor
    private func openComposer(in app: XCUIApplication) -> XCUIElement {
        require(app.staticTexts["Nenhuma conversa aberta"], in: app)
        app.buttons["Nova conversa"].click()
        let composer = app.textViews["Peça uma alteração…"]
        require(composer, in: app)
        composer.click()
        return composer
    }

    /// Opens a conversation from the empty window and sends its first turn.
    @MainActor
    private func startConversation(_ text: String, in app: XCUIApplication) {
        openComposer(in: app).typeText(text + "\n")
    }

    private let repositoryWithOrigin = """
        git init -q -b main
        git -c user.name=Den -c user.email=den@den.invalid -c commit.gpgsign=false commit -q --allow-empty -m init
        git clone -q --bare . ../origin.git
        git remote add origin https://github.com/den/fixture.git
        git config url."$(cd ../origin.git && pwd)".insteadOf https://github.com/den/fixture.git
        git fetch -q origin
        git remote set-head origin main
        """

    @MainActor
    private func element(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    @MainActor
    func testTheWorktreeChipMovesTheFirstTurnIntoItsOwnWorktree() throws {
        try claude.on(FakeCLI.userTurn, reply: RecordedSession.claude("hello"))
        try claude.answerTitles(with: "Saudação curta")
        let app = launch(projectSetup: repositoryWithOrigin)

        let composer = openComposer(in: app)
        let chip = element("worktree-chip", in: app)
        require(chip, in: app)
        chip.click()
        composer.click()
        composer.typeText("Diga apenas OK e nada mais.\n")

        require(app.staticTexts["OK"], in: app)
        let badge = element("worktree-branch", in: app)
        require(badge, in: app)
        XCTAssertEqual(badge.label, "feat/saudacao-curta")
        require(text(containing: "⑂ feat/saudacao-curta", in: app), in: app)
        let directory = claude.launches.last?.directory ?? ""
        XCTAssertTrue(directory.hasSuffix("/worktrees/project/feat-saudacao-curta"), "launched in \(directory)")
    }

    private let failingPullRequest = #"""
        [{"number":80,"title":"Diga apenas OK","url":"https://github.com/den/fixture/pull/80",
          "state":"OPEN","isDraft":false,"additions":3,"deletions":1,"baseRefName":"main",
          "reviewDecision":"","mergeable":"MERGEABLE","updatedAt":"2026-10-01T10:01:00Z",
          "statusCheckRollup":[{"__typename":"CheckRun","name":"lint","workflowName":"CI",
          "status":"COMPLETED","conclusion":"FAILURE",
          "detailsUrl":"https://github.com/den/fixture/actions/runs/1",
          "startedAt":"2026-10-01T10:00:00Z","completedAt":"2026-10-01T10:00:42Z"}]}]
        """#

    @MainActor
    func testThePullRequestOfTheTaskShowsAboveTheComposerAndInTheSidebar() throws {
        try claude.on(FakeCLI.userTurn, reply: RecordedSession.claude("hello"))
        try claude.answerTitles(with: "Saudação curta")
        let app = launch(projectSetup: repositoryWithOrigin,
                         extraEnvironment: ["DEN_GH": FakeCLI.gh, "FAKE_GH_PR_LIST": failingPullRequest])

        let composer = openComposer(in: app)
        let chip = element("worktree-chip", in: app)
        require(chip, in: app)
        chip.click()
        composer.click()
        composer.typeText("Diga apenas OK e nada mais.\n")

        require(element("pull-request-bar", in: app), in: app)
        require(app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "#80")).firstMatch, in: app)
        require(text(containing: "#80 · Checks falhando", in: app), in: app)
        let checks = app.buttons["Checks"].firstMatch
        require(checks, in: app)
        checks.click()
        require(app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "lint")).firstMatch,
                in: app)
    }

    @MainActor
    func testTheGitHubSetupBarAsksForALoginAndCanBeDismissed() throws {
        try claude.on(FakeCLI.userTurn, reply: RecordedSession.claude("hello"))
        try claude.answerTitles(with: "Saudação curta")
        let app = launch(projectSetup: repositoryWithOrigin,
                         extraEnvironment: ["DEN_GH": FakeCLI.gh, "FAKE_GH_AUTH_STATUS": "1"])

        let composer = openComposer(in: app)
        let chip = element("worktree-chip", in: app)
        require(chip, in: app)
        chip.click()
        composer.click()
        composer.typeText("Diga apenas OK e nada mais.\n")

        let message = text(containing: "O gh precisa de login em github.com", in: app)
        require(message, in: app)
        app.buttons["Dispensar"].firstMatch.click()
        XCTAssertTrue(message.waitForNonExistence(timeout: patience))
    }

    // MARK: - Conversation

    @MainActor
    func testAFirstConversationGetsItsReplyAndATitle() throws {
        try claude.on(FakeCLI.userTurn, reply: RecordedSession.claude("hello"))
        try claude.answerTitles(with: "Saudação curta")
        let app = launch()

        startConversation("Diga apenas OK e nada mais.", in: app)

        require(app.staticTexts["OK"], in: app)
        require(sidebarRow("Saudação curta", in: app), in: app)
        XCTAssertEqual(claude.launches.count, 1)
    }

    @MainActor
    func testAllowingFromThePermissionCardFinishesTheTurn() throws {
        let recorded = try RecordedSession.claudePermission()
        try claude.on(FakeCLI.userTurn, reply: recorded.untilAsking)
        try claude.on(FakeCLI.permissionAnswer, reply: recorded.afterAnswer)
        let app = launch()

        startConversation("Crie prova.txt com o texto ok.", in: app)
        let allow = app.buttons["Permitir"]
        require(allow, in: app)
        // The card's buttons answer the accessibility hit test as not hittable,
        // though a real click lands on them, so click where the button is.
        allow.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).click()

        require(text(containing: "criado com o conte", in: app), in: app)
        XCTAssertFalse(allow.exists)
        XCTAssertEqual(claude.received.last?.contains(#""behavior":"allow""#), true)
    }

    @MainActor
    func testAConversationIsStillThereAfterTheAppRelaunches() throws {
        try claude.on(FakeCLI.userTurn, reply: RecordedSession.claude("hello"))
        try claude.answerTitles(with: "Saudação curta")
        var app = launch()
        startConversation("Diga apenas OK e nada mais.", in: app)
        require(sidebarRow("Saudação curta", in: app), in: app)
        app.terminate()

        app = launch()
        let row = sidebarRow("Saudação curta", in: app)
        require(row, in: app)
        row.click()

        require(app.staticTexts["OK"], in: app)
    }

    // MARK: - Mentions

    private let bigProject = """
        mkdir -p admin-web/src orders-api/src
        : > orders-api/pom.xml
        i=0
        while [ $i -lt 4100 ]; do
          : > admin-web/src/f$i; : > orders-api/src/f$i
          i=$((i + 1))
        done
        """

    private let backendWithWorktree = """
        java=orders-domain/src/main/java/com/example/orders
        for copy in orders-api worktrees/feature-1/orders-api; do
          mkdir -p $copy/$java $copy/src
          : > $copy/$java/OrderRepository.java
        done
        mkdir -p orders-api/.git orders-api/target/classes
        echo "gitdir: $(pwd -P)/orders-api/.git/worktrees/orders-api" > worktrees/feature-1/orders-api/.git
        i=0
        while [ $i -lt 4100 ]; do
          : > orders-api/src/f$i; : > orders-api/target/classes/f$i.class
          : > worktrees/feature-1/orders-api/src/f$i
          i=$((i + 1))
        done
        """

    @MainActor
    func testMentionsReachEveryFolderOfABigProject() {
        let app = launch(projectSetup: bigProject)
        let composer = openComposer(in: app)

        composer.typeText("@admin-web")
        require(app.staticTexts["admin-web"], in: app)
        composer.typeKey("a", modifierFlags: .command)
        composer.typeText("@orders")
        require(app.staticTexts["orders-api"], in: app)

        composer.typeText("\t")
        XCTAssertEqual(composer.value as? String, "@orders-api/")
    }

    @MainActor
    func testMentionsReachADeepSourceBesideBuildOutputAndAWorktree() {
        let app = launch(projectSetup: backendWithWorktree)
        let composer = openComposer(in: app)

        composer.typeText("@OrderRepo")

        require(text(containing: "orders-api/orders-domain/src/main/java", in: app), in: app)
        XCTAssertFalse(text(containing: "worktrees/feature-1/orders-api", in: app).exists)
    }

    // MARK: - Sidebar

    @MainActor
    func testRenamingASessionFromTheSidebar() throws {
        try claude.on(FakeCLI.userTurn, reply: RecordedSession.claude("hello"))
        try claude.answerTitles(with: "Saudação curta")
        let app = launch()
        startConversation("Diga apenas OK e nada mais.", in: app)
        let row = sidebarRow("Saudação curta", in: app)
        require(row, in: app)

        row.rightClick()
        app.menuItems["Renomear"].click()
        app.typeKey("a", modifierFlags: .command)
        app.typeText("Renomeada\n")

        require(sidebarRow("Renomeada", in: app), in: app)
        XCTAssertFalse(sidebarRow("Saudação curta", in: app).exists)
    }

    @MainActor
    func testDeletingASessionAsksFirstAndEmptiesTheWindow() throws {
        try claude.on(FakeCLI.userTurn, reply: RecordedSession.claude("hello"))
        try claude.answerTitles(with: "Saudação curta")
        let app = launch()
        startConversation("Diga apenas OK e nada mais.", in: app)
        let row = sidebarRow("Saudação curta", in: app)
        require(row, in: app)

        row.rightClick()
        app.menuItems["Apagar sessão…"].click()
        // The Touch Bar mirrors the alert's buttons, so look inside the sheet.
        let confirm = app.sheets.buttons["Apagar"]
        require(confirm, in: app)
        confirm.click()

        require(app.staticTexts["Nenhuma conversa aberta"], in: app)
        XCTAssertFalse(row.exists)
    }
}
