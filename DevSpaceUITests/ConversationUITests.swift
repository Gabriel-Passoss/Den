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
            .appending(path: "DevSpaceUITests-" + UUID().uuidString)
        claude = try FakeCLI(appRoot: root, harness: "claude-code")
        openCode = try FakeCLI(appRoot: root, harness: "opencode")
    }

    override func tearDownWithError() throws {
        claude.remove()
        openCode.remove()
    }

    @MainActor
    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["DEVSPACE_UI_TEST_ROOT"] = root.path
        for cli in [claude!, openCode!] {
            app.launchEnvironment.merge(cli.launchEnvironment) { $1 }
        }
        app.launchEnvironment["DEVSPACE_CLI_claude-code"] = claude.executable
        app.launchEnvironment["DEVSPACE_CLI_opencode"] = openCode.executable
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
        app.outlines["Sidebar"].staticTexts[title]
    }

    /// Opens a conversation from the empty window and sends its first turn.
    @MainActor
    private func startConversation(_ text: String, in app: XCUIApplication) {
        require(app.staticTexts["Nenhuma conversa aberta"], in: app)
        app.buttons["Nova conversa"].click()
        let composer = app.textViews["Peça uma alteração…"]
        require(composer, in: app)
        composer.click()
        composer.typeText(text + "\n")
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
        XCTAssertTrue(claude.received.last?.contains(#""behavior":"allow""#) == true)
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
