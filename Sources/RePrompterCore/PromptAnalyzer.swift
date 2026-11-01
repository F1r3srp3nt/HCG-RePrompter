import Foundation

/// The role a unit of prompt text plays.
public enum UnitRole: String, Sendable, Codable, CaseIterable {
    case objective
    case requirement
    case constraint
    case output
    case context
    case reference // verbatim code or headings
}

/// Broad subject area of a prompt, used to tailor missing-information questions.
public enum PromptDomain: String, Sendable, Codable, CaseIterable {
    case software
    case writing
    case research
    case dataAnalysis
    case business
    case education
    case creative
    case general
}

public struct ClassifiedUnit: Sendable, Equatable {
    public var unit: PromptUnit
    public var role: UnitRole
    /// True when the unit also states something about output length or format.
    public var mentionsOutput: Bool
    /// True when the unit contains a limit or prohibition, even if it was
    /// chosen as the objective.
    public var containsConstraint: Bool

    public init(unit: PromptUnit, role: UnitRole, mentionsOutput: Bool, containsConstraint: Bool = false) {
        self.unit = unit
        self.role = role
        self.mentionsOutput = mentionsOutput
        self.containsConstraint = containsConstraint || role == .constraint
    }
}

/// A vague or underspecified expression found in the prompt.
public struct Ambiguity: Sendable, Equatable, Hashable {
    public var term: String
    public var note: String
    public var suggestion: String

    public init(term: String, note: String, suggestion: String) {
        self.term = term
        self.note = note
        self.suggestion = suggestion
    }
}

/// Deterministic analysis of a prompt. Never invents content: every item is
/// either a verbatim unit of the original prompt or a question/observation
/// about it.
public struct PromptAnalysis: Sendable, Equatable {
    public var units: [ClassifiedUnit]
    public var domain: PromptDomain
    public var ambiguities: [Ambiguity]
    /// Questions about information the prompt does not provide.
    public var missingInformation: [String]
    public var wordCount: Int

    public var objective: String? { units.first { $0.role == .objective }?.unit.text }
    public func texts(for role: UnitRole) -> [String] { units.filter { $0.role == role }.map(\.unit.text) }
    public var requirements: [String] { texts(for: .requirement) }
    /// Constraint units, plus the objective when it also states a constraint.
    public var constraints: [String] {
        units.filter { $0.role == .constraint || ($0.role == .objective && $0.containsConstraint) }.map(\.unit.text)
    }
    public var outputExpectations: [String] { texts(for: .output) }
    public var context: [String] { texts(for: .context) }
    public var codeBlocks: [String] { units.filter { $0.unit.kind == .codeBlock }.map(\.unit.text) }
}

public enum PromptAnalyzer {
    // MARK: Vocabulary

    static let negationPhrases = [
        "don't", "dont", "do not", "never", "avoid", "must not", "mustn't", "should not", "shouldn't",
        "without", "exclude", "excluding", "cannot", "can't", "won't", "no more than", "not ",
    ]
    static let limitPhrases = [
        "at most", "at least", "maximum", "minimum", "max ", "min ", "limit", "only ", "under ",
        "less than", "fewer than", "more than", "within", "no longer than", "no later than", "up to ",
        "deadline", "budget", "strictly", "exactly",
    ]
    static let outputNouns: Set<String> = [
        "list", "table", "json", "markdown", "csv", "yaml", "xml", "bullet", "bullets", "bullet-point",
        "paragraph", "paragraphs", "words", "word", "sentences", "pages", "page", "slides", "slide", "headings",
        "outline", "summary", "report", "essay", "email", "diagram", "chart", "format", "formatted",
        "output", "template", "checklist", "tldr", "step-by-step", "steps", "code", "snippet",
    ]
    static let outputVerbs = [
        "format", "output", "return", "respond", "reply", "present", "structure the", "write it as",
        "give me", "deliver", "provide a", "provide the", "answer in", "answer with", "keep it",
    ]
    static let requirementMarkers = [
        "must", "should", "need to", "needs to", "have to", "has to", "required", "require", "make sure",
        "ensure", "include", "i want", "i need", "i'd like", "i would like", "we need", "we want",
        "please", "it should", "it must", "support", "be able to",
    ]
    static let imperativeVerbs: Set<String> = [
        "add", "analyze", "analyse", "answer", "assess", "build", "calculate", "check", "clarify",
        "classify", "compare", "compile", "compose", "convert", "create", "debug", "define", "describe",
        "design", "detect", "develop", "document", "draft", "edit", "estimate", "evaluate", "explain",
        "explore", "extract", "find", "fix", "generate", "give", "help", "identify", "implement",
        "improve", "investigate", "list", "make", "map", "migrate", "model", "optimize", "optimise",
        "organize", "outline", "plan", "predict", "prepare", "produce", "propose", "provide", "recommend",
        "refactor", "research", "review", "rewrite", "show", "simplify", "sketch", "solve", "suggest",
        "summarize", "summarise", "teach", "tell", "test", "translate", "update", "use", "validate",
        "verify", "visualize", "write", "brainstorm", "proofread", "rank", "score", "audit", "set",
        "configure", "deploy", "port", "rename", "remove", "replace", "split", "merge", "parse",
        "mention", "highlight", "emphasize", "emphasise", "cover", "discuss", "address", "keep", "focus",
    ]
    static let questionStarters: Set<String> = [
        "how", "what", "why", "which", "when", "where", "who", "can", "could", "would", "is", "are",
        "should", "do", "does",
    ]

    static let vagueTerms: [(term: String, note: String, suggestion: String)] = [
        ("something", "“something” leaves the subject open.", "Name the specific thing you want."),
        ("stuff", "“stuff” is non-specific.", "List the items you mean."),
        ("things", "“things” is non-specific.", "List the items you mean."),
        ("etc", "“etc.” leaves the list open-ended.", "Complete the list, or say whether it is exhaustive."),
        ("and so on", "“and so on” leaves the list open-ended.", "Complete the list, or say whether it is exhaustive."),
        ("some", "“some” does not specify a quantity.", "State how many or how much."),
        ("a few", "“a few” does not specify a quantity.", "State an exact number or range."),
        ("several", "“several” does not specify a quantity.", "State an exact number or range."),
        ("a lot", "“a lot” does not specify a quantity.", "State an exact number or range."),
        ("various", "“various” does not specify which ones.", "List the specific items."),
        ("good", "“good” is subjective.", "Describe what good means here (criteria or examples)."),
        ("nice", "“nice” is subjective.", "Describe the qualities you want."),
        ("better", "“better” needs a reference point.", "Say better than what, and by which measure."),
        ("best", "“best” needs criteria.", "State how “best” should be judged."),
        ("properly", "“properly” is undefined.", "Describe the expected behaviour or standard."),
        ("appropriate", "“appropriate” is undefined.", "State the standard or criteria to apply."),
        ("fast", "“fast” is not measurable as written.", "Give a measurable target (e.g. a time or rate)."),
        ("quickly", "“quickly” is not measurable as written.", "Give a time frame or performance target."),
        ("soon", "“soon” has no date.", "Give a deadline or time frame."),
        ("simple", "“simple” is subjective.", "Describe the level of complexity or audience you have in mind."),
        ("easy", "“easy” is subjective.", "Describe who should find it easy and in what way."),
        ("modern", "“modern” is open to interpretation.", "Name the style, standard or era you mean."),
        ("clean", "“clean” is open to interpretation.", "Describe the conventions or qualities you expect."),
        ("user-friendly", "“user-friendly” is open to interpretation.", "Describe the users and what they must be able to do."),
        ("robust", "“robust” is open to interpretation.", "State which failures or conditions it must handle."),
        ("scalable", "“scalable” needs a target.", "State the expected load or growth."),
        ("efficient", "“efficient” needs a measure.", "State the resource or metric that matters."),
        ("optimal", "“optimal” needs criteria.", "State what should be optimized."),
        ("as needed", "“as needed” leaves the decision open.", "State when or how much."),
        ("if possible", "“if possible” makes the requirement optional.", "Say whether it is required or optional."),
        ("maybe", "“maybe” makes the intent uncertain.", "Say whether it is wanted."),
        ("kind of", "“kind of” is imprecise.", "Describe exactly what you mean."),
        ("sort of", "“sort of” is imprecise.", "Describe exactly what you mean."),
        ("whatever", "“whatever” leaves the choice open.", "State a preference or say any choice is acceptable."),
        ("high quality", "“high quality” is subjective.", "State the quality criteria."),
        ("professional", "“professional” can mean different registers.", "Describe the tone and audience."),
    ]

    static let domainKeywords: [PromptDomain: Set<String>] = [
        .software: ["code", "app", "application", "api", "function", "bug", "swift", "python", "javascript",
                    "typescript", "java", "kotlin", "rust", "go", "golang", "c#", "c++", "sql", "database",
                    "backend", "frontend", "ui", "ux", "server", "deploy", "test", "tests", "unit", "refactor",
                    "repository", "repo", "git", "endpoint", "framework", "library", "compile", "build",
                    "swiftui", "react", "django", "node", "ios", "macos", "android", "docker", "kubernetes",
                    "class", "method", "variable", "script", "cli", "software", "implement", "feature"],
        .writing: ["essay", "article", "blog", "post", "email", "letter", "copy", "write", "rewrite",
                   "proofread", "edit", "paragraph", "tone", "headline", "newsletter", "draft"],
        .research: ["research", "study", "studies", "literature", "sources", "citations", "evidence",
                    "paper", "papers", "hypothesis", "methodology", "survey", "findings", "cite"],
        .dataAnalysis: ["data", "dataset", "csv", "spreadsheet", "excel", "chart", "statistics",
                        "regression", "trend", "trends", "metrics", "kpi", "dashboard", "analysis", "analyze"],
        .business: ["business", "strategy", "market", "customers", "revenue", "competitors", "pricing",
                    "stakeholders", "investors", "pitch", "plan", "roadmap", "sales", "marketing", "company"],
        .education: ["teach", "lesson", "students", "student", "course", "curriculum", "quiz", "exam",
                     "learn", "learning", "explain", "beginner", "beginners", "class", "tutorial"],
        .creative: ["story", "poem", "song", "lyrics", "character", "characters", "novel", "script",
                    "scene", "fiction", "illustration", "image", "artwork", "painting", "design", "logo",
                    "mood", "style", "screenplay", "plot", "worldbuilding"],
    ]

    /// Nouns that already imply the form of the response.
    static let deliverableNouns: Set<String> = [
        "poem", "poems", "story", "stories", "essay", "email", "letter", "report", "summary", "article", "post",
        "song", "lyrics", "script", "screenplay", "function", "class", "app", "table", "list", "plan", "outline",
        "presentation", "slides", "image", "logo", "illustration", "haiku", "tweet", "caption", "memo",
        "proposal", "itinerary", "checklist", "diagram", "chart", "code", "snippet", "query", "recipe", "quiz",
    ]

    static let languageOrPlatformTerms: Set<String> = [
        "swift", "swiftui", "uikit", "appkit", "python", "javascript", "typescript", "java", "kotlin", "go",
        "golang", "rust", "c", "c#", "c++", "ruby", "php", "sql", "html", "css", "react", "vue", "angular",
        "svelte", "node", "node.js", "django", "flask", "fastapi", "rails", "spring", ".net", "ios", "macos",
        "android", "linux", "windows", "web", "docker", "kubernetes", "aws", "azure", "gcp", "postgres",
        "postgresql", "mysql", "sqlite", "mongodb", "redis", "bash", "shell", "powershell", "terraform",
        "flutter", "dart", "scala", "elixir", "haskell", "r", "matlab", "julia", "unity", "unreal",
    ]
    static let audienceTerms = [
        "audience", "reader", "readers", "for my", "for our", "for a ", "for an ", "beginner", "beginners",
        "executive", "executives", "students", "customers", "clients", "team", "stakeholders", "kids",
        "children", "experts", "engineers", "developers", "managers", "investors", "users", "board",
    ]
    static let lengthTerms = [
        "words", "word", "pages", "page", "sentences", "sentence", "paragraph", "paragraphs", "short",
        "brief", "concise", "detailed", "in-depth", "length", "long", "minutes", "slides", "characters",
        "tl;dr", "tldr", "one-pager", "summary",
    ]
    static let toneTerms = ["tone", "style", "mood", "voice", "feel", "genre", "register", "formal", "informal", "casual", "playful", "serious", "witty"]
    static let testTerms = ["test", "tests", "testing", "unit test", "unit tests", "qa", "coverage", "tdd", "xctest", "pytest", "jest"]
    static let acceptanceTerms = ["acceptance", "criteria", "done when", "definition of done", "success", "succeed", "pass", "expected result"]

    // MARK: Analysis

    public static func analyze(_ text: String, mode: EnhancementMode = .structured) -> PromptAnalysis {
        let units = TextSegmenter.segment(TextSanitizer.sanitize(text))
        var classified = units.map(classify)

        // Choose the objective: the first requirement-like or question unit,
        // otherwise the first sentence.
        if let index = classified.firstIndex(where: { $0.role == .requirement && isObjectiveCandidate($0.unit.text) })
            ?? classified.firstIndex(where: { $0.role != .reference && isObjectiveCandidate($0.unit.text) })
            ?? classified.firstIndex(where: { $0.role == .requirement })
            ?? classified.firstIndex(where: { $0.role == .context && $0.unit.kind != .heading }) {
            classified[index].role = .objective
        }

        let lowered = text.lowercased()
        let words = Tokenizer.words(text)
        let domain = detectDomain(words: words)

        return PromptAnalysis(
            units: classified,
            domain: domain,
            ambiguities: detectAmbiguities(units: units),
            missingInformation: missingInformation(
                lowered: lowered,
                words: Set(words),
                units: classified,
                domain: domain,
                mode: mode
            ),
            wordCount: words.count
        )
    }

    static func classify(_ unit: PromptUnit) -> ClassifiedUnit {
        switch unit.kind {
        case .codeBlock, .heading:
            return ClassifiedUnit(unit: unit, role: .reference, mentionsOutput: false)
        case .sentence, .listItem:
            break
        }
        let lower = " " + unit.text.lowercased() + " "
        let words = Tokenizer.words(unit.text)
        let mentionsOutput = isOutputStatement(lower: lower, words: words)

        if isConstraint(lower: lower) {
            return ClassifiedUnit(unit: unit, role: .constraint, mentionsOutput: mentionsOutput)
        }
        if mentionsOutput {
            return ClassifiedUnit(unit: unit, role: .output, mentionsOutput: true)
        }
        if isRequirement(lower: lower, words: words, raw: unit.text) {
            return ClassifiedUnit(unit: unit, role: .requirement, mentionsOutput: false)
        }
        return ClassifiedUnit(unit: unit, role: .context, mentionsOutput: false)
    }

    static func isConstraint(lower: String) -> Bool {
        if negationPhrases.contains(where: { lower.contains(" " + $0) }) { return true }
        if lower.hasPrefix(" no ") { return true }
        return limitPhrases.contains(where: { lower.contains(" " + $0) })
    }

    static let formatLeadIns: Set<String> = ["as", "in", "into", "using"]

    static func isOutputStatement(lower: String, words: [String]) -> Bool {
        if lower.contains(" format") { return true }
        let hasVerb = outputVerbs.contains(where: { lower.contains(" " + $0) })
        for (index, word) in words.enumerated() where outputNouns.contains(word) {
            if hasVerb { return true }
            // "as a table", "in JSON", "into bullet points", "under 200 words", "3 paragraphs"
            let previous = words[max(0, index - 2)..<index]
            if previous.contains(where: { formatLeadIns.contains($0) || Int($0) != nil }) { return true }
        }
        return false
    }

    static func isRequirement(lower: String, words: [String], raw: String) -> Bool {
        if requirementMarkers.contains(where: { lower.contains(" " + $0 + " ") || lower.contains(" " + $0 + ",") }) {
            return true
        }
        if let first = words.first, imperativeVerbs.contains(first) { return true }
        if raw.trimmingCharacters(in: .whitespaces).hasSuffix("?") { return true }
        if let first = words.first, questionStarters.contains(first), words.count > 2 { return true }
        return false
    }

    static let interjections: Set<String> = ["hey", "hi", "hello", "so", "ok", "okay", "um", "uh", "basically", "please"]

    static func isObjectiveCandidate(_ text: String) -> Bool {
        var words = Tokenizer.words(text)
        while let first = words.first, interjections.contains(first), words.count > 1 { words.removeFirst() }
        guard let first = words.first else { return false }
        let lower = words.joined(separator: " ")
        return imperativeVerbs.contains(first)
            || questionStarters.contains(first)
            || ["i want", "i need", "i'd like", "i would like", "we need", "we want", "help me", "please"].contains { lower.hasPrefix($0) }
    }

    static func detectDomain(words: [String]) -> PromptDomain {
        var best: (PromptDomain, Int) = (.general, 0)
        for domain in PromptDomain.allCases where domain != .general {
            let keywords = domainKeywords[domain] ?? []
            let score = words.reduce(0) { $0 + (keywords.contains($1) ? 1 : 0) }
            if score > best.1 { best = (domain, score) }
        }
        return best.1 >= 1 ? best.0 : .general
    }

    static func detectAmbiguities(units: [PromptUnit]) -> [Ambiguity] {
        var found: [Ambiguity] = []
        var seen = Set<String>()
        let prose = units.filter { $0.kind != .codeBlock }
        let joined = " " + prose.map { $0.text.lowercased() }.joined(separator: " ") + " "
        let normalized = joined.map { ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "'") ? $0 : " " }
        let spaced = " " + String(normalized).split(separator: " ").joined(separator: " ") + " "

        for entry in vagueTerms where !seen.contains(entry.term) {
            if spaced.contains(" " + entry.term + " ") {
                found.append(Ambiguity(term: entry.term, note: entry.note, suggestion: entry.suggestion))
                seen.insert(entry.term)
            }
        }

        if let first = prose.first(where: { $0.kind != .heading }) {
            let firstWord = Tokenizer.words(first.text).first ?? ""
            if ["it", "this", "that", "they", "these", "those"].contains(firstWord) {
                found.insert(
                    Ambiguity(
                        term: firstWord,
                        note: "The prompt opens with “\(firstWord)”, which has no clear referent.",
                        suggestion: "Name what “\(firstWord)” refers to."
                    ),
                    at: 0
                )
            }
        }
        return found
    }

    static func missingInformation(
        lowered: String,
        words: Set<String>,
        units: [ClassifiedUnit],
        domain: PromptDomain,
        mode: EnhancementMode
    ) -> [String] {
        var questions: [String] = []
        let padded = " " + lowered + " "
        func mentions(_ terms: [String]) -> Bool {
            terms.contains { term in
                term.contains(" ") ? padded.contains(term) : words.contains(term)
            }
        }
        let hasOutputSpec = units.contains { $0.mentionsOutput || $0.role == .output }
            || !words.isDisjoint(with: deliverableNouns)
        let substantive = units.filter { $0.unit.kind != .codeBlock }.count

        if !hasOutputSpec {
            questions.append("What form should the response take (for example a list, table, paragraphs or code)?")
        }
        let isSoftware = mode == .developer || domain == .software
        if isSoftware {
            if !words.contains(where: { languageOrPlatformTerms.contains($0) }) {
                questions.append("Which programming language, framework or platform should be used?")
            }
            if mode == .developer {
                if !mentions(acceptanceTerms) {
                    questions.append("How will you judge the work complete (acceptance criteria)?")
                }
                if !mentions(testTerms) {
                    questions.append("What testing is expected (for example unit tests, integration tests, or none)?")
                }
            }
        } else {
            if [.structured, .professional, .creative].contains(mode), !mentions(audienceTerms) {
                questions.append("Who is the intended audience?")
            }
            if !mentions(lengthTerms), mode != .quickImprove {
                questions.append("How long or detailed should the response be?")
            }
        }
        if mode == .creative, !mentions(toneTerms) {
            questions.append("What tone or style should the piece have?")
        }
        if substantive <= 1, (units.first.map { Tokenizer.words($0.unit.text).count } ?? 0) < 6 {
            questions.append("Can you add context about the situation or purpose behind this request?")
        }
        return questions
    }
}
