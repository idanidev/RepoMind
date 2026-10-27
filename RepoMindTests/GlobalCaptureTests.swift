import SwiftData
import XCTest

@testable import RepoMind

@MainActor
final class GlobalCaptureTests: XCTestCase {
    private var container: ModelContainer?

    /// The container is dropped here, in a synchronous `tearDown`, as the other suites do.
    override func tearDown() {
        container = nil
    }

    private let apps = [
        CaptureRepoOption(id: "1", name: "InSync", columns: ["To Do", "Doing", "Done"], ideaColumn: "Ideas"),
        CaptureRepoOption(id: "2", name: "RepoMind", columns: ["Backlog", "Doing"]),
        CaptureRepoOption(id: "3", name: "mi-api"),
        CaptureRepoOption(id: "4", name: "api-legacy"),
    ]

    // MARK: Folding and matching

    func testFoldIgnoresCaseAccentsAndPunctuation() {
        XCTAssertEqual(CaptureRepoResolver.fold("Añade, la  App!"), "anade la app")
        XCTAssertEqual(CaptureRepoResolver.squash("In-Sync"), "insync")
        XCTAssertEqual(CaptureRepoResolver.squash("repo mind"), "repomind")
    }

    func testMatchFindsTheAppHowevertheRecognizerSpelledIt() {
        XCTAssertEqual(CaptureRepoResolver.match("in sync", in: apps)?.id, "1")
        XCTAssertEqual(CaptureRepoResolver.match("Repo Mind", in: apps)?.id, "2")
        XCTAssertEqual(CaptureRepoResolver.match("mi api", in: apps)?.id, "3")
    }

    func testMatchRefusesAnAmbiguousOrUnknownName() {
        // "api" is inside two names: guessing would file the task under the wrong project.
        XCTAssertNil(CaptureRepoResolver.match("api", in: apps))
        XCTAssertNil(CaptureRepoResolver.match("nothing", in: apps))
        XCTAssertNil(CaptureRepoResolver.match("", in: apps))
    }

    // MARK: Detection

    func testAnAppNamedFirstIsTakenOutOfTheText() {
        let direct = CaptureRepoResolver.detect(in: "En InSync, arreglar el login", options: apps)
        XCTAssertEqual(direct?.option.id, "1")
        XCTAssertEqual(direct?.rest, "Arreglar el login")
        XCTAssertEqual(direct?.stripped, true)

        let command = CaptureRepoResolver.detect(in: "Añade una tarea en InSync arreglar el login", options: apps)
        XCTAssertEqual(command?.option.id, "1")
        XCTAssertEqual(command?.rest, "Arreglar el login")

        let colon = CaptureRepoResolver.detect(in: "InSync: arreglar el login", options: apps)
        XCTAssertEqual(colon?.rest, "Arreglar el login")

        let english = CaptureRepoResolver.detect(in: "In sync, fix the login crash", options: apps)
        XCTAssertEqual(english?.option.id, "1")
        XCTAssertEqual(english?.rest, "Fix the login crash")

        let longer = CaptureRepoResolver.detect(in: "para api legacy borrar el endpoint viejo", options: apps)
        XCTAssertEqual(longer?.option.id, "4")
        XCTAssertEqual(longer?.rest, "Borrar el endpoint viejo")
    }

    func testAnAppNamedLastIsTakenOutOfTheText() {
        let suffix = CaptureRepoResolver.detect(in: "Arreglar el login en InSync", options: apps)
        XCTAssertEqual(suffix?.option.id, "1")
        XCTAssertEqual(suffix?.rest, "Arreglar el login")

        let polite = CaptureRepoResolver.detect(
            in: "Arreglar la app de pagos en la app de InSync por favor", options: apps)
        XCTAssertEqual(polite?.option.id, "1")
        XCTAssertEqual(polite?.rest, "Arreglar la app de pagos")
    }

    func testAnAppMentionedInTheMiddleKeepsTheWholeText() {
        let text = "Arreglar el botón del login en InSync para que no se cierre"
        let found = CaptureRepoResolver.detect(in: text, options: apps)
        XCTAssertEqual(found?.option.id, "1")
        XCTAssertEqual(found?.rest, text)
        XCTAssertEqual(found?.stripped, false)

        let subject = CaptureRepoResolver.detect(in: "El widget de RepoMind no carga", options: apps)
        XCTAssertEqual(subject?.option.id, "2")
        XCTAssertEqual(subject?.stripped, false)
    }

    func testTwoAppsOrNoneIsNoAnswer() {
        XCTAssertNil(CaptureRepoResolver.detect(in: "Compara InSync con RepoMind", options: apps))
        XCTAssertNil(CaptureRepoResolver.detect(in: "arreglar el login", options: apps))
        XCTAssertNil(CaptureRepoResolver.detect(in: "", options: apps))
    }

    // MARK: Drafts

    func testFallbackFilesTheDictationUnderTheAppItNames() {
        let named = GlobalCaptureRouting.fallbackDraft(transcript: "En InSync, arreglar el login", options: apps)
        XCTAssertEqual(named.repoID, "1")
        XCTAssertEqual(named.title, "Arreglar el login")

        let unnamed = GlobalCaptureRouting.fallbackDraft(transcript: "arreglar el login", options: apps)
        XCTAssertNil(unnamed.repoID)
        XCTAssertEqual(unnamed.title, "arreglar el login")
    }

    func testFallbackUsesTheRecognizersHintOrTheOnlyApp() {
        // "…, añadir a InSync" at the end reaches the view model as a column name.
        let hinted = GlobalCaptureRouting.fallbackDraft(transcript: "arreglar el login", options: apps, hint: "in sync")
        XCTAssertEqual(hinted.repoID, "1")

        let alone = GlobalCaptureRouting.fallbackDraft(transcript: "arreglar el login", options: [apps[1]])
        XCTAssertEqual(alone.repoID, "2")
    }

    func testTheModelsAppAndColumnAreCheckedAgainstTheRealOnes() {
        let draft = GlobalCaptureRouting.draft(
            title: "Arreglar el login", details: "", kind: "bug", repo: "in sync", column: "doing",
            transcript: "en in sync arreglar el login", options: apps)
        XCTAssertEqual(draft.repoID, "1")
        XCTAssertEqual(draft.kind, .bug)
        XCTAssertEqual(draft.columnName, "Doing")

        // A column of another app is not a column of this one.
        let foreign = GlobalCaptureRouting.draft(
            title: "x", details: "", kind: "feature", repo: "InSync", column: "Backlog",
            transcript: "algo de InSync", options: apps)
        XCTAssertEqual(foreign.repoID, "1")
        XCTAssertNil(foreign.columnName)
    }

    func testTheModelNamingNoAppFallsBackToTheTextThenToTheOnlyApp() {
        let fromText = GlobalCaptureRouting.draft(
            title: "Widget", details: "", kind: "idea", repo: "", column: "",
            transcript: "El widget de RepoMind no carga", options: apps)
        XCTAssertEqual(fromText.repoID, "2")

        let none = GlobalCaptureRouting.draft(
            title: "Widget", details: "", kind: "idea", repo: "", column: "",
            transcript: "un widget", options: apps)
        XCTAssertNil(none.repoID)

        let idea = GlobalCaptureRouting.draft(
            title: "Widget", details: "", kind: "idea", repo: "InSync", column: "",
            transcript: "una idea para InSync", options: apps)
        XCTAssertEqual(idea.columnName, "Ideas")
    }

    func testTheModelCannotInventTheAppNobodySaid() {
        // The sheet is meant to ask. A model that names an app the dictation never mentions would make it
        // look as if the app had been said, and the task would be filed there without a word.
        let invented = GlobalCaptureRouting.draft(
            title: "Arreglar el login", details: "", kind: "bug", repo: "InSync", column: "",
            transcript: "arreglar el login", options: apps)
        XCTAssertNil(invented.repoID)
    }

    func testABoardsDraftHasNoApp() {
        XCTAssertNil(CaptureDraft(title: "x").repoID)
        XCTAssertNil(CaptureDraft.fallback(transcript: "x", columnName: nil).repoID)
    }


    // MARK: Detection, the cases that used to leave words behind

    func testTheWordsThatIntroduceTheAppLeaveWithIt() {
        let withTheApp = CaptureRepoResolver.detect(in: "Arreglar el login en la app InSync", options: apps)
        XCTAssertEqual(withTheApp?.rest, "Arreglar el login")

        let project = CaptureRepoResolver.detect(in: "Actualizar las dependencias del proyecto RepoMind", options: apps)
        XCTAssertEqual(project?.option.id, "2")
        XCTAssertEqual(project?.rest, "Actualizar las dependencias")

        let prefix = CaptureRepoResolver.detect(in: "En la app InSync, arreglar el login", options: apps)
        XCTAssertEqual(prefix?.rest, "Arreglar el login")
        XCTAssertEqual(prefix?.stripped, true)

        let english = CaptureRepoResolver.detect(in: "Add a task in InSync: fix the login", options: apps)
        XCTAssertEqual(english?.rest, "Fix the login")
        XCTAssertEqual(english?.stripped, true)
    }

    func testTheTaskKeepsTheCapitalsOfItsFirstWord() {
        let cloud = CaptureRepoResolver.detect(in: "En RepoMind, iCloud no sincroniza", options: apps)
        XCTAssertEqual(cloud?.rest, "iCloud no sincroniza")

        let dotfile = CaptureRepoResolver.detect(in: "En InSync, .gitignore sobra", options: apps)
        XCTAssertEqual(dotfile?.rest, ".gitignore sobra")
    }

    func testANameNeverSpansAComma() {
        let withWeb = apps + [CaptureRepoOption(id: "5", name: "InSync Web")]
        let found = CaptureRepoResolver.detect(in: "En InSync, web: arreglar el login", options: withWeb)
        XCTAssertEqual(found?.option.id, "1", "the comma ends the app's name; 'web' is part of the task")
        XCTAssertEqual(found?.rest, "Web: arreglar el login")

        let whole = CaptureRepoResolver.detect(in: "En InSync Web, arreglar el login", options: withWeb)
        XCTAssertEqual(whole?.option.id, "5")
    }

    // MARK: Which app, in order

    func testAnExplicitCommandBeatsAPassingMention() {
        // "…, añadir a InSync" is what the person asked for; RepoMind was only in the sentence.
        let draft = GlobalCaptureRouting.fallbackDraft(
            transcript: "el widget de RepoMind no carga", options: apps, hint: "InSync")
        XCTAssertEqual(draft.repoID, "1")

        // An app named at the start or the end is the strongest sign of all.
        let named = GlobalCaptureRouting.fallbackDraft(
            transcript: "En RepoMind, arreglar el widget", options: apps, hint: "InSync")
        XCTAssertEqual(named.repoID, "2")
    }

    func testTheAppTheCommandAskedForOverridesTheModelsGuess() {
        let guessed = CaptureDraft(title: "x", repoID: "2")
        XCTAssertEqual(GlobalCaptureModel.settingApp(guessed, named: "1", fallback: nil).repoID, "1")
        XCTAssertEqual(GlobalCaptureModel.settingApp(guessed, named: nil, fallback: "3").repoID, "2")

        let unsure = CaptureDraft(title: "x")
        XCTAssertEqual(GlobalCaptureModel.settingApp(unsure, named: nil, fallback: "3").repoID, "3")
        XCTAssertNil(GlobalCaptureModel.settingApp(unsure, named: nil, fallback: nil).repoID)
    }

    // MARK: Two projects that look the same

    private func memory() throws -> ModelContext {
        let config = ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        let container = try ModelContainer(
            for: ProjectRepo.self, TaskItem.self, KanbanColumn.self, GitHubAccount.self, configurations: config)
        self.container = container
        return container.mainContext
    }

    func testLocalProjectsWithTheSameRepoIDAreDifferentOptions() throws {
        let context = try memory()
        let first = ProjectRepo(repoID: 0, name: "Ideas", isLocal: true)
        let second = ProjectRepo(repoID: 0, name: "Ideas", isLocal: true)
        context.insert(first)
        context.insert(second)

        let options = GlobalCaptureModel.options(from: [first, second])

        XCTAssertEqual(options.count, 2)
        XCTAssertEqual(Set(options.map(\.id)).count, 2, "two local projects used to share the id 0")
    }

    func testATaskForTheSecondOfTwoIdenticalProjectsIsFiledInTheSecond() throws {
        let context = try memory()
        let first = ProjectRepo(repoID: 0, name: "Ideas", isLocal: true)
        let second = ProjectRepo(repoID: 0, name: "Ideas", isLocal: true)
        context.insert(first)
        context.insert(second)
        let options = GlobalCaptureModel.options(from: [first, second])
        let model = GlobalCaptureModel()
        model.refreshOptions(options)
        model.capture = VoiceCapture(
            transcript: "comprar dominio",
            drafts: [CaptureDraft(title: "Comprar dominio", repoID: second.homeCardID)],
            isComposing: false)
        XCTAssertTrue(model.canSave)

        XCTAssertTrue(model.save(repos: [first, second], context: context))

        XCTAssertEqual(first.tasks?.count ?? 0, 0)
        XCTAssertEqual(second.tasks?.map(\.content), ["Comprar dominio"])
    }

    func testAFreeAccountOnlyOffersTheAppsItsHomeShows() throws {
        let context = try memory()
        let repos = (1...5).map { ProjectRepo(repoID: $0, name: "app\($0)", htmlURL: "https://github.com/x/app\($0)") }
        repos.forEach(context.insert)
        repos[4].isFavorite = true

        let free = GlobalCaptureModel.options(from: repos, limit: 3)
        XCTAssertEqual(free.count, 3)
        XCTAssertEqual(free.first?.name, "app5", "favorites first")
        XCTAssertEqual(GlobalCaptureModel.options(from: repos, limit: nil).count, 5)
    }

    func testTheFreeTierCapKeepsFavoritesFirstAndFillsTheRest() {
        let items = [("a", false), ("b", false), ("c", true), ("d", false), ("e", true)]
        let visible = SubscriptionManager.visible(items, limit: 3, isFavorite: { $0.1 })
        XCTAssertEqual(visible.map(\.0), ["c", "e", "a"])
        XCTAssertEqual(SubscriptionManager.visible(items, limit: nil, isFavorite: { $0.1 }).count, 5)
        XCTAssertEqual(SubscriptionManager.visible(items, limit: 9, isFavorite: { $0.1 }).count, 5)
    }

    // MARK: Vocabulary and router

    func testVocabularyPutsTheAppsFirstAndStaysShort() {
        let terms = VoiceVocabulary.terms(repoNames: ["InSync", "RepoMind"], columns: ["Doing", "insync"])
        XCTAssertEqual(Array(terms.prefix(2)), ["InSync", "RepoMind"])
        XCTAssertEqual(terms.filter { $0.lowercased() == "insync" }.count, 1)
        XCTAssertLessThanOrEqual(terms.count, 120)
    }

    func testARequestIsConsumedOnce() {
        // Its own router: the shared one is listened to by the app the tests run in.
        let router = GlobalCaptureRouter()
        XCTAssertFalse(router.consumePending())
        router.request()
        XCTAssertTrue(router.consumePending())
        XCTAssertFalse(router.consumePending())
    }
}
