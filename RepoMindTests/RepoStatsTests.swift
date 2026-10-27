import XCTest

@testable import RepoMind

// MARK: - Contract decoding

final class RepoStatsTests: XCTestCase {
    private let fixture = """
    {
      "schema": 1,
      "app": "InSync",
      "generatedAt": "2026-10-27T01:30:00.123456+00:00",
      "periodDays": 30,
      "headline": [
        { "key": "active_day", "label": "Activas hoy", "value": 12, "previous": null },
        { "key": "active_week", "label": "Activas 7 días", "value": 31, "previous": null, "primary": true },
        { "key": "paying", "label": "De pago", "value": 4, "previous": 3 }
      ],
      "signals": [
        { "key": "pantalla.compra", "current": 320, "previous": 280 },
        { "key": "pantalla.calendario", "current": 900, "previous": 950 },
        { "key": "app.abierta", "current": 400, "previous": 0 },
        { "key": "evento.creado", "current": 50, "previous": 40 }
      ],
      "features": [
        { "key": "compra", "label": "Compra", "adopters": 30, "activeAdopters": 18, "population": 40 }
      ],
      "series": [
        { "key": "app.abierta", "label": "Aperturas", "points": [ { "date": "2026-10-01", "value": 40 } ] }
      ],
      "versions": [
        { "version": "1.0.12", "current": 300 },
        { "version": null, "current": 12 }
      ],
      "issues": [
        { "kind": "crash", "title": "excepción 6", "at": "2026-10-26T20:11:00+00:00", "count": 3,
          "version": "1.0.12", "url": null, "status": "crash" },
        { "kind": "report", "title": "No me deja invitar", "at": "2026-10-25T09:00:00Z", "count": 1,
          "version": "1.0.12", "url": "https://github.com/idanidev/InSync/issues/90", "status": "nuevo" }
      ]
    }
    """

    func testDecodesTheContractWithPostgresDates() throws {
        let stats = try RepoStats.decode(Data(fixture.utf8))

        XCTAssertEqual(stats.app, "InSync")
        XCTAssertEqual(stats.periodDays, 30)
        XCTAssertEqual(stats.headline.count, 3)
        XCTAssertEqual(stats.signals.count, 4)
        XCTAssertEqual(stats.features.first?.activeAdopters, 18)
        XCTAssertEqual(stats.versions.last?.version, nil)
        XCTAssertEqual(stats.issues.count, 2)
        XCTAssertTrue(stats.issues[0].isCrash)
        XCTAssertFalse(stats.issues[1].isCrash)

        let expected = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-10-27T01:30:00Z"))
        XCTAssertEqual(expected.timeIntervalSince1970, stats.generatedAt.timeIntervalSince1970, accuracy: 1)
    }

    func testParsesEveryDateShapeTheBackendsEmit() throws {
        let plain = try XCTUnwrap(RepoStats.date(fromISO8601: "2026-10-27T01:30:00Z")).timeIntervalSince1970
        func seconds(_ text: String) throws -> TimeInterval {
            try XCTUnwrap(RepoStats.date(fromISO8601: text), text).timeIntervalSince1970
        }
        XCTAssertEqual(try seconds("2026-10-27T01:30:00+00:00"), plain, accuracy: 0.001)
        XCTAssertEqual(try seconds("2026-10-27T01:30:00.1Z"), plain + 0.1, accuracy: 0.001)
        XCTAssertEqual(try seconds("2026-10-27T01:30:00.123456+00:00"), plain + 0.123, accuracy: 0.001)
        XCTAssertEqual(try seconds("2026-10-27T03:30:00.5+02:00"), plain + 0.5, accuracy: 0.001)
        XCTAssertNil(RepoStats.date(fromISO8601: "yesterday"))
    }

    func testPrimaryHeadlineIsTheMarkedOne() throws {
        let stats = try RepoStats.decode(Data(fixture.utf8))
        XCTAssertEqual(stats.primaryHeadline?.key, "active_week")

        var unmarked = stats
        unmarked.headline = [RepoStats.Headline(key: "a", label: "A", value: 1, previous: nil, primary: nil)]
        XCTAssertEqual(unmarked.primaryHeadline?.key, "a")
    }

    func testSignalsGroupByFamilyAndOrderByUse() throws {
        let stats = try RepoStats.decode(Data(fixture.utf8))
        let families = stats.signalFamilies

        XCTAssertEqual(families.map(\.family), ["pantalla", "app", "evento"])
        XCTAssertEqual(families[0].signals.map(\.key), ["pantalla.calendario", "pantalla.compra"])
    }

    func testChangeIsNilWithoutAPreviousPeriod() throws {
        XCTAssertNil(RepoStats.change(current: 10, previous: 0))
        XCTAssertNil(RepoStats.change(current: 10, previous: nil))
        XCTAssertEqual(try XCTUnwrap(RepoStats.change(current: 150, previous: 100)), 0.5, accuracy: 0.0001)
        XCTAssertEqual(try XCTUnwrap(RepoStats.change(current: 50, previous: 100)), -0.5, accuracy: 0.0001)
    }

    func testRejectsAnotherSchema() {
        let other = fixture.replacingOccurrences(of: "\"schema\": 1", with: "\"schema\": 2")
        XCTAssertThrowsError(try RepoStats.decode(Data(other.utf8)))
    }

    func testDayParsesCalendarDates() {
        XCTAssertNotNil(RepoStats.day(from: "2026-10-01"))
        XCTAssertNil(RepoStats.day(from: "yesterday"))
    }
}

// MARK: - Store

@MainActor
final class RepoStatsStoreTests: XCTestCase {
    private let repoID = 990_001

    override func tearDown() async throws {
        await RepoStatsStore.shared.disconnect(repoID: repoID)
    }

    func testConfigureAndDisconnect() async throws {
        let store = RepoStatsStore.shared
        XCTAssertFalse(store.isConfigured(repoID))
        XCTAssertTrue(store.isStale(repoID))

        let url = try XCTUnwrap(URL(string: "https://example.supabase.co/functions/v1/repomind-stats"))
        try await store.configure(repoID: repoID, endpoint: url, token: "secret")
        XCTAssertTrue(store.isConfigured(repoID))
        XCTAssertEqual(store.endpoint(for: repoID), url)

        await store.disconnect(repoID: repoID)
        XCTAssertFalse(store.isConfigured(repoID))
        XCTAssertNil(store.stats(for: repoID))
    }

    func testRefreshDoesNothingWithoutAnEndpoint() async {
        let store = RepoStatsStore.shared
        await store.refresh(repoID: repoID, force: true)
        XCTAssertNil(store.stats(for: repoID))
        XCTAssertNil(store.failures[repoID])
    }
}
