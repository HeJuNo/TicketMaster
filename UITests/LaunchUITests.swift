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
        let ticket = element(app, containing: "Order 777555")
        XCTAssertTrue(ticket.waitForExistence(timeout: 10))
        ticket.tap()
        XCTAssertTrue(element(app, containing: "Melange is out of stock").waitForExistence(timeout: 10))
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
        XCTAssertTrue(element(app, containing: "Order 777555").waitForExistence(timeout: 10))
    }
}
