//
//  RepoMindUITests.swift
//  RepoMindUITests
//
//  Created by Daniel Benito Diaz on 29/1/26.
//

import XCTest

final class RepoMindUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testLoginAndNavigationFlow() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-reset"]  // Ensure a clean state if app supports it
        app.launch()

        // 1. Login Flow (Mock Pro)
        let manualEntryButton = app.buttons["enter_token_manually_button"]
        if manualEntryButton.waitForExistence(timeout: 5) {
            manualEntryButton.tap()

            let tokenField = app.secureTextFields["access_token_field"]
            XCTAssertTrue(tokenField.waitForExistence(timeout: 2), "Token field should appear")
            tokenField.tap()
            tokenField.typeText("mock-pro")

            let validateButton = app.buttons["validate_connect_button"]
            validateButton.tap()
        }

        // 2. Verify Home Screen (Sync)
        let reposTitle = app.staticTexts["Repositorios"]
        XCTAssertTrue(reposTitle.waitForExistence(timeout: 5), "Should reach Home Screen")

        // 3. Navigate to Kanban
        // Attempt to find the first repository in the list.
        // Since we are using List, we look for cells/buttons.
        let firstRepo = app.buttons.firstMatch
        if firstRepo.waitForExistence(timeout: 3) {
            firstRepo.tap()

            // 4. Verify Kanban
            // Check for localized "Añadir Columna" or typical Kanban elements
            let addColumnButton = app.buttons["add_new_column_button"]
            // Or check title if it's dynamic.
            XCTAssertTrue(app.navigationBars.firstMatch.exists)
        }
    }
}
