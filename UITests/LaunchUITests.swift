import XCTest

final class LaunchUITests: XCTestCase {
    /// Rows and articles combine their texts into one accessibility element.
    @MainActor func element(_ app: XCUIApplication, containing text: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
    }

    @MainActor func testDemoTicketOpensWithArticles() {
        let app = XCUIApplication()
        app.launchArguments = ["-demo", "YES"]
        app.launch()
        XCTAssertTrue(app.staticTexts["Service Desk"].waitForExistence(timeout: 10))  // queues come first
        app.buttons["All Queues"].tap()
        let ticket = element(app, containing: "Order 777555")
        XCTAssertTrue(ticket.waitForExistence(timeout: 10))
        ticket.tap()
        XCTAssertTrue(element(app, containing: "Melange is out of stock").waitForExistence(timeout: 10))
    }

    @MainActor func testOwnerMenuOffersAssignAndUnassign() {
        let app = XCUIApplication()
        app.launchArguments = ["-demo", "YES", "-demoTicket", "2"]
        app.launch()
        app.buttons["Change State, Priority or Owner"].tap()
        XCTAssertTrue(app.buttons["Unassign"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["Assign to Me"].exists)  // ticket 2 already belongs to the signed-in user
        app.buttons["Assign to…"].tap()
        XCTAssertTrue(app.buttons["Chris Miller"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Ben Reader"].exists)  // read-only access to the group
        try? XCUIScreen.main.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: "/tmp/tmshots/owner-menu.png"))
    }

    @MainActor func testPasswordSignInShowsTickets() {
        let app = XCUIApplication()
        app.launchArguments = ["-demoLogin", "YES"]
        app.launch()
        let server = app.textFields["helpdesk.example.com"]
        XCTAssertTrue(server.waitForExistence(timeout: 10))
        server.tap()
        server.typeText("demo.zammad.invalid")
        app.buttons["Continue"].tap()
        XCTAssertTrue(app.buttons["Sign in with Microsoft"].waitForExistence(timeout: 10))
        let user = app.textFields["Username or Email"]
        user.tap()
        user.typeText("emma")
        let password = app.secureTextFields["Password"]
        password.tap()
        password.typeText("secret")
        app.buttons["Sign In"].tap()
        XCTAssertTrue(app.staticTexts["Sales"].waitForExistence(timeout: 10))
    }
}
