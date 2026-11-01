import Foundation
import Testing
@testable import Galley

struct PrettyNameTests {
    @Test(arguments: [
        ("2026-10-30_auth-migration-plan.md", "Auth migration plan"),
        ("03-onboarding.md", "Onboarding"),
        ("authMigrationPlan.md", "Auth migration plan"),
        ("README.md", "README"),
        ("CLAUDE.md", "CLAUDE"),
        ("api_design_notes.md", "API design notes"),
        ("prd-v2.md", "PRD v2"),
        ("20261030-1415-standup.md", "Standup"),
        ("2026.md", "2026"),
        ("plan.markdown", "Plan"),
        ("MCP-server-ideas.md", "MCP server ideas"),
        ("q3OKRs.md", "Q3 OKRs"),
    ])
    func names(input: String, expected: String) {
        #expect(PrettyName.make(fromFilename: input) == expected)
    }
}

struct RendererTests {
    let renderer = MarkdownRenderer(baseURL: URL(fileURLWithPath: "/tmp/docs"))

    @Test func headingsBecomeOutlineWithUniqueSlugs() {
        let doc = renderer.render("# Title\n\n## Setup\n\ntext\n\n## Setup\n\n### Deep *dive*")
        #expect(doc.title == "Title")
        #expect(doc.outline.map(\.id) == ["title", "setup", "setup-1", "deep-dive"])
        #expect(doc.outline.map(\.level) == [1, 2, 2, 3])
        #expect(doc.html.contains("<h3 id=\"deep-dive\""))
    }

    @Test func headingsOpenNestedFoldableSections() {
        let doc = renderer.render("intro\n\n# A\n\na\n\n## B\n\nb\n\n# C\n\nc")
        let opens = doc.html.components(separatedBy: "<section").count - 1
        let closes = doc.html.components(separatedBy: "</section>").count - 1
        #expect(opens == 3)
        #expect(closes == 3)
        #expect(doc.html.contains("data-sec=\"b\""))
        // B closes before C opens.
        let bClose = doc.html.range(of: "</section>")!.lowerBound
        let cOpen = doc.html.range(of: "data-sec=\"c\"")!.lowerBound
        #expect(bClose < cOpen)
    }

    @Test func everyLeafBlockIsAUnit() {
        let doc = renderer.render("# A\n\npara\n\n- one\n- two\n\n```swift\nlet x = 1\n```\n\n| a | b |\n|---|---|\n| 1 | 2 |")
        // heading, para, two list paragraphs, code, table head, one row
        #expect(doc.units.count == 7)
        #expect(doc.html.contains("data-lang=\"swift\""))
        #expect(doc.html.contains("<ul class=\"tight\">"))
    }

    @Test func taskListsAndStrikethrough() {
        let doc = renderer.render("- [x] done\n- [ ] todo ~~old~~")
        #expect(doc.html.contains("class=\"tasks tight\""))
        #expect(doc.html.contains("<li class=\"task done\">"))
        #expect(doc.html.contains("<del>old</del>"))
    }

    @Test func githubAlertsAndObsidianCallouts() {
        let alert = renderer.render("> [!WARNING]\n> Do not add a supplier.")
        #expect(alert.html.contains("callout warning"))
        #expect(alert.html.contains(">Warning</span>"))
        #expect(alert.html.contains("Do not add a supplier."))
        #expect(!alert.html.contains("[!WARNING]"))

        let folded = renderer.render("> [!faq]- Why paper?\n> Because.")
        #expect(folded.html.contains("<details class=\"callout question\">"))
        #expect(folded.html.contains(">Why paper?</span>"))

        let titleOnly = renderer.render("> [!tip] Just a title")
        #expect(titleOnly.html.contains("callout tip"))
        #expect(titleOnly.html.contains(">Just a title</span>"))
    }

    @Test func inlineAndDisplayMathSurviveParsing() {
        let doc = renderer.render("Energy $E = mc^2$ and $a_1 + b_1$ cost $5 and $10.\n\n$$\n\\int_0^1 x\\,dx\n$$")
        #expect(doc.html.contains("<span class=\"math\">E = mc^2</span>"))
        #expect(doc.html.contains("<span class=\"math\">a_1 + b_1</span>"))
        #expect(doc.html.contains("cost $5 and $10."))
        #expect(doc.html.contains("<div class=\"math display\""))
        #expect(doc.html.contains("\\int_0^1 x\\,dx"))
    }

    @Test func mathIsNotTouchedInCode() {
        let doc = renderer.render("`$x$` and\n\n```\n$$\nnot math\n$$\n```")
        #expect(!doc.html.contains("class=\"math"))
        #expect(doc.html.contains("<code>$x$</code>"))
    }

    @Test func mathAndMermaidFences() {
        let doc = renderer.render("```math\nx^2\n```\n\n```mermaid\ngraph TD; A-->B\n```")
        #expect(doc.html.contains("<div class=\"math display\""))
        #expect(doc.html.contains("<figure class=\"mermaid\""))
        #expect(doc.html.contains("A--&gt;B"))
    }

    @Test func footnotes() {
        let doc = renderer.render("Claim[^src] and again[^src].\n\n[^src]: Source.")
        #expect(doc.html.contains("<sup class=\"footnote-ref\"><a href=\"#fn-1\""))
        #expect(doc.html.contains("<section class=\"footnotes\">"))
        #expect(doc.html.contains("Source."))
    }

    @Test func emojiHighlightAndWikilinks() {
        let doc = renderer.render("Ship it :rocket: ==now== see [[Auth plan|the plan]].")
        #expect(doc.html.contains("🚀"))
        #expect(doc.html.contains("<mark>now</mark>"))
        #expect(doc.html.contains("<a href=\"wiki:Auth plan\" class=\"wikilink\">the plan</a>"))
    }

    @Test func frontMatterBecomesDefinitionList() {
        let doc = renderer.render("---\nname: grilling\ndescription: \"Stress test\"\n---\n# Body")
        #expect(doc.html.hasPrefix("<dl class=\"front-matter\""))
        #expect(doc.html.contains("<dt>description</dt><dd>Stress test</dd>"))
        #expect(doc.title == "Body")
    }

    @Test func imagesResolveIntoTheWorkspace() {
        let doc = renderer.render("![diagram](img/a%20b.png) ![remote](https://x.com/a.png)")
        #expect(doc.html.contains("src=\"galley://file/tmp/docs/img/a%20b.png\""))
        #expect(doc.html.contains("class=\"remote-image\""))
    }

    @Test func htmlIsEscapedInText() {
        let doc = renderer.render("a < b & `<script>`")
        #expect(doc.html.contains("a &lt; b &amp; <code>&lt;script&gt;</code>"))
    }
}

struct DiffTests {
    let renderer = MarkdownRenderer(baseURL: nil)

    @Test func identicalDocumentsHaveNoChanges() {
        let a = renderer.render("# A\n\nOne.\n\nTwo.")
        #expect(BlockDiff.changes(from: a.units, to: a.units).isEmpty)
    }

    @Test func addedParagraphIsAdded() {
        let old = renderer.render("# A\n\nOne.\n\nTwo.")
        let new = renderer.render("# A\n\nOne.\n\nInserted paragraph here.\n\nTwo.")
        let changes = BlockDiff.changes(from: old.units, to: new.units)
        #expect(changes.units == [2: .added])
        #expect(changes.removed == 0)
    }

    @Test func editedParagraphIsModified() {
        let old = renderer.render("# A\n\nPrices arrive in the supplier's currency and leave in cents.")
        let new = renderer.render("# A\n\nPrices arrive in the supplier's currency and leave in cents, converted at the run's rate.")
        let changes = BlockDiff.changes(from: old.units, to: new.units)
        guard case .modified(let oldHTML)? = changes.units[1] else {
            Issue.record("expected a modified unit, got \(changes)")
            return
        }
        #expect(oldHTML.contains("leave in cents."))
        #expect(changes.removed == 0)
    }

    @Test func unrelatedReplacementIsAddedPlusRemoved() {
        let old = renderer.render("Alpha beta gamma.")
        let new = renderer.render("Completely different words entirely.")
        let changes = BlockDiff.changes(from: old.units, to: new.units)
        #expect(changes.units == [0: .added])
        #expect(changes.removed == 1)
    }

    @Test func editedTableRowIsModified() {
        let old = renderer.render("| Tier | Limit |\n|---|---|\n| Free | 60 |\n| Team | 600 |")
        let new = renderer.render("| Tier | Limit |\n|---|---|\n| Free | 60 |\n| Team | 900 |")
        let changes = BlockDiff.changes(from: old.units, to: new.units)
        #expect(changes.modified == 1)
        #expect(changes.added == 0)
        #expect(changes.removed == 0)
    }

    @Test func mathNumberingDoesNotFakeChanges() {
        let old = renderer.render("Intro.\n\nLater $y$.")
        let new = renderer.render("Intro $x$.\n\nLater $y$.")
        let changes = BlockDiff.changes(from: old.units, to: new.units)
        #expect(changes.units.keys.sorted() == [0])
    }
}

struct FuzzyTests {
    @Test func matchesWordStartsAndRanksThemFirst() {
        let plan = Fuzzy.score("amp", in: "Auth migration plan")
        let other = Fuzzy.score("amp", in: "Example mapping")
        #expect(plan != nil)
        #expect(other != nil)
        #expect(plan! > other!)
    }

    @Test func rejectsMissingCharacters() {
        #expect(Fuzzy.score("xyz", in: "Auth migration plan") == nil)
    }
}

struct PerformanceTests {
    /// A long agent document — about 4,000 lines — must render and diff fast
    /// enough to stay on the main thread.
    @Test func largeDocumentRendersQuickly() {
        var parts: [String] = []
        for section in 0..<200 {
            parts.append("## Section \(section)\n\nParagraph with **bold**, `code`, $x_\(section)$ and a [link](other.md).\n\n- one\n- two :rocket:\n\n```swift\nlet value = \(section)\n```\n\n| a | b |\n|---|---|\n| \(section) | x |\n")
        }
        let source = parts.joined(separator: "\n")
        let renderer = MarkdownRenderer(baseURL: nil)
        let clock = ContinuousClock()
        var rendered: RenderedDocument?
        let renderTime = clock.measure { rendered = renderer.render(source) }
        let edited = source.replacingOccurrences(of: "## Section 100", with: "## Section one hundred")
        let diffTime = clock.measure {
            _ = BlockDiff.changes(from: rendered!.units, to: renderer.render(edited).units)
        }
        print("render \(renderTime), render+diff \(diffTime), \(rendered!.units.count) units")
        #expect(renderTime < .milliseconds(400))
        #expect(diffTime < .milliseconds(800))
    }
}

struct ReviewRegressionTests {
    let renderer = MarkdownRenderer(baseURL: nil)

    @Test func emptyWikilinksAreLeftAsText() {
        let doc = renderer.render("a [[|]] b [[ ]] c [[#]] d [[x|]]")
        #expect(doc.html.contains("[[|]]"))
        #expect(doc.html.contains("<a href=\"wiki:x\" class=\"wikilink\">x</a>"))
    }

    @Test func inlineDisplayMathDoesNotSwallowLaterLines() {
        let doc = renderer.render("$$x$$ is small.\n\nNext paragraph stays.")
        #expect(doc.html.contains("Next paragraph stays."))
        #expect(doc.html.contains("<span class=\"math display\">x</span>"))
    }

    @Test func displayMathKeepsItsListIndentation() {
        let doc = renderer.render("1. Step\n\n   $$\n   x^2\n   $$\n\n2. Step")
        // One list, with the math inside it.
        #expect(doc.html.components(separatedBy: "<ol").count == 2)
        let mathAt = doc.html.range(of: "math display")!.lowerBound
        let listEnd = doc.html.range(of: "</ol>")!.lowerBound
        #expect(mathAt < listEnd)
    }

    @Test func libraryDecodesWithMissingFields() throws {
        let json = #"{"workspaces":[{"id":"3F2504E0-4F89-11D3-9A0C-0305E82C3301","path":"/tmp/x"}]}"#
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let state = try decoder.decode(LibraryState.self, from: Data(json.utf8))
        #expect(state.workspaces.count == 1)
        #expect(state.workspaces[0].files.isEmpty)
        #expect(state.level == 3)
    }
}

struct AxisLockTests {
    private func decide(_ steps: [(CGFloat, CGFloat)]) -> AxisLock.Axis? {
        var lock = AxisLock()
        var axis: AxisLock.Axis?
        for (x, y) in steps where axis == nil { axis = lock.add(x: x, y: y) }
        return axis
    }

    @Test func waitsForEnoughTravel() {
        #expect(decide([(3, 1), (2, 1)]) == nil)
    }

    @Test func sidewaysSwipeWithAWobbleIsHorizontal() {
        // Mostly rightward, with a vertical-looking sample in the middle.
        #expect(decide([(3, 1), (1, 3), (4, 1), (4, 0)]) == .horizontal)
    }

    @Test func slantedScrollStaysVertical() {
        #expect(decide([(2, -4), (3, -4), (2, -5)]) == .vertical)
    }

    @Test func diagonalGoesToTheScroll() {
        #expect(decide([(5, 5), (5, 5)]) == .vertical)
    }
}
