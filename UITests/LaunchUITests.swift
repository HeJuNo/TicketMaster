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

    @MainActor func testLoginShownWithoutAccount() {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.buttons["Sign In"].waitForExistence(timeout: 10))
    }
}
