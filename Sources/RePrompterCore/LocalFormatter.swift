import Foundation

/// Deterministic, offline prompt formatting. This is explicitly **not** AI: it
/// reorganizes and tidies the user's own words. Every unit of the original
/// prompt is placed in the output exactly once (code blocks verbatim), so no
/// requirement can be lost, and nothing mandatory is ever added — questions and
/// suggestions are clearly labelled as such.
public enum LocalFormatter {
    public struct Output: Sendable, Equatable {
        public var text: String
        public var report: EnhancementReport
        public var warnings: [ValidationWarning]
    }

    public static func format(_ request: EnhancementRequest) -> Output {
        let analysis = PromptAnalyzer.analyze(request.originalPrompt, mode: request.mode)
        var changes = ChangeLog()
        var warnings: [ValidationWarning] = []

        let text: String
        switch request.mode {
        case .quickImprove:
            text = quickImprove(request.originalPrompt, changes: &changes)
        case .structured:
            text = structured(analysis, changes: &changes)
        case .professional:
            text = professional(analysis, changes: &changes)
        case .developer:
            text = developer(analysis, changes: &changes)
        case .creative:
            text = creative(analysis, changes: &changes)
        case .custom:
            text = structured(analysis, changes: &changes)
            warnings.append(ValidationWarning(
                kind: .customInstructionsIgnored,
                message: "Local formatting cannot interpret custom style instructions; the Structured layout was used. Use an AI provider to apply them."
            ))
        }

        let report = EnhancementReport(
            objective: analysis.objective.map(cleanSentence) ?? "",
            explicitRequirements: analysis.requirements.map(cleanSentence),
            constraints: analysis.constraints.map(cleanSentence),
            intendedOutput: analysis.outputExpectations.isEmpty
                ? "Not specified in the original prompt."
                : analysis.outputExpectations.map(cleanSentence).joined(separator: " "),
            structuralChanges: changes.entries.isEmpty ? ["No structural changes were needed."] : changes.entries,
            optionalSuggestions: analysis.ambiguities.map { "\($0.note) \($0.suggestion)" },
            missingInformation: analysis.missingInformation,
            assumptions: [],
            ambiguities: analysis.ambiguities.map(\.note)
        )
        return Output(text: text, report: report, warnings: warnings)
    }

    // MARK: Change tracking

    struct ChangeLog {
        private(set) var entries: [String] = []
        private var counters: [String: Int] = [:]

        mutating func note(_ entry: String) {
            if !entries.contains(entry) { entries.append(entry) }
        }

        mutating func count(_ key: String) { counters[key, default: 0] += 1 }

        mutating func flushCounters() {
            for (key, value) in counters.sorted(by: { $0.key < $1.key }) where value > 0 {
                note(key.replacingOccurrences(of: "#", with: "\(value)"))
            }
            counters = [:]
        }
    }

    // MARK: Sentence clean-up

    static let fillerOpeners = [
        "hey there,", "hi there,", "hey,", "hi,", "hello,", "ok so", "okay so", "so,", "um,", "uh,",
        "basically,", "i was wondering if you could", "i was wondering if you can", "could you please",
        "can you please", "would you please",
    ]
    static let casualReplacements: [(String, String)] = [
        ("w/o", "without"), ("w/", "with"), ("b/c", "because"), ("pls", "please"), ("plz", "please"),
        ("thx", "thanks"), ("idk", "I don't know"),
        ("dont", "don't"), ("doesnt", "doesn't"), ("didnt", "didn't"), ("isnt", "isn't"), ("arent", "aren't"),
        ("wasnt", "wasn't"), ("werent", "weren't"), ("cant", "can't"), ("couldnt", "couldn't"),
        ("shouldnt", "shouldn't"), ("wouldnt", "wouldn't"), ("havent", "haven't"), ("hasnt", "hasn't"),
        ("im", "I'm"), ("ive", "I've"), ("youre", "you're"), ("theyre", "they're"), ("thats", "that's"),
    ]
    static let professionalReplacements: [(String, String)] = [
        ("gonna", "going to"), ("wanna", "want to"), ("gotta", "need to"), ("kinda", "somewhat"),
        ("sorta", "somewhat"), ("yeah", "yes"), ("nope", "no"), ("ok", "OK"), ("asap", "as soon as possible"),
        ("lots of", "many"), ("a bunch of", "several"),
    ]

    /// Cleans a single sentence without changing its meaning.
    static func cleanSentence(_ sentence: String) -> String {
        var log = ChangeLog()
        return cleanSentence(sentence, professional: false, changes: &log)
    }

    static func cleanSentence(_ sentence: String, professional: Bool, changes: inout ChangeLog) -> String {
        var text = sentence.split(whereSeparator: { $0 == " " || $0 == "\t" }).joined(separator: " ")
        if text != sentence.trimmingCharacters(in: .whitespaces) { changes.note("Normalized spacing.") }

        // Spaces before punctuation.
        for mark in [",", ".", ";", ":", "!", "?"] where text.contains(" " + mark + " ") || text.hasSuffix(" " + mark) {
            text = text.replacingOccurrences(of: " " + mark, with: mark)
            changes.note("Fixed spacing around punctuation.")
        }

        // Filler openers.
        let lower = text.lowercased()
        for filler in fillerOpeners where lower.hasPrefix(filler) {
            let remainder = text.dropFirst(filler.count).trimmingCharacters(in: .whitespaces)
            if Tokenizer.words(remainder).count >= 2 {
                text = remainder
                changes.note("Removed conversational filler (“\(filler.trimmingCharacters(in: CharacterSet(charactersIn: ",")))”).")
            }
            break
        }

        // Word-level replacements.
        var words = text.split(separator: " ", omittingEmptySubsequences: false).map(String.init)
        var replacements = casualReplacements
        if professional { replacements += professionalReplacements }
        var index = 0
        while index < words.count {
            let word = words[index]
            let core = Tokenizer.trimPunctuation(word)
            let lowerCore = core.lowercased()
            // Standalone pronoun "i".
            if core == "i" {
                words[index] = word.replacingOccurrences(of: "i", with: "I")
                changes.count("Capitalized the pronoun “I” (#×).")
            } else if core == lowerCore, let replacement = replacements.first(where: { $0.0 == lowerCore && !$0.0.contains(" ") }) {
                // Only replace exact lowercase tokens so identifiers like `R` or `OK` stay intact.
                words[index] = word.replacingOccurrences(of: core, with: replacement.1)
                changes.note("Expanded “\(replacement.0)” to “\(replacement.1)”.")
            }
            // Doubled words ("the the").
            if index > 0, lowerCore.count > 1, lowerCore.allSatisfy(\.isLetter), !["that", "had"].contains(lowerCore),
               Tokenizer.trimPunctuation(words[index - 1]).lowercased() == lowerCore,
               words[index - 1].last?.isLetter == true {
                words.remove(at: index)
                changes.note("Removed a repeated word (“\(core)”).")
                continue
            }
            index += 1
        }
        text = words.joined(separator: " ")

        if professional {
            for (phrase, replacement) in professionalReplacements where phrase.contains(" ") {
                if let range = text.range(of: phrase, options: [.caseInsensitive]) {
                    text.replaceSubrange(range, with: replacement)
                    changes.note("Replaced informal phrasing (“\(phrase)” → “\(replacement)”).")
                }
            }
        }

        // Capitalize sentence start when the first word is plain lowercase prose.
        if let first = text.split(separator: " ").first,
           first.allSatisfy({ $0.isLetter && $0.isLowercase }),
           Tokenizer.words(text).count >= 2,
           let firstChar = text.first {
            text = firstChar.uppercased() + text.dropFirst()
            changes.count("Capitalized the start of # sentence(s).")
        }

        // Terminal punctuation for complete sentences.
        if let last = text.last, last.isLetter || last.isNumber || last == ")", Tokenizer.words(text).count >= 2 {
            let isQuestion = PromptAnalyzer.questionStarters.contains(Tokenizer.words(text).first ?? "")
                && !PromptAnalyzer.imperativeVerbs.contains(Tokenizer.words(text).first ?? "")
            text += isQuestion ? "?" : "."
            changes.count("Added closing punctuation to # sentence(s).")
        }
        return text
    }

    // MARK: Quick Improve

    static func quickImprove(_ original: String, changes: inout ChangeLog) -> String {
        let units = TextSegmenter.segment(TextSanitizer.sanitize(original))
        var output: [String] = []
        var currentParagraph = -1
        var paragraphSentences: [String] = []
        var seenSentences = Set<String>()
        var lastListParagraph = -1

        func flushParagraph() {
            if !paragraphSentences.isEmpty {
                output.append(paragraphSentences.joined(separator: " "))
                paragraphSentences = []
            }
        }

        for unit in units {
            if unit.paragraph != currentParagraph {
                flushParagraph()
                currentParagraph = unit.paragraph
            }
            switch unit.kind {
            case .codeBlock:
                flushParagraph()
                output.append(unit.text)
            case .heading:
                flushParagraph()
                output.append("## " + unit.text)
            case .listItem:
                flushParagraph()
                let cleaned = cleanSentence(unit.text, professional: false, changes: &changes)
                if appendIfNew(cleaned, to: &seenSentences, changes: &changes) {
                    // Keep list items grouped within the paragraph.
                    if let last = output.last, last.hasPrefix("- "), lastListParagraph == unit.paragraph {
                        output[output.count - 1] = last + "\n- " + cleaned
                    } else {
                        output.append("- " + cleaned)
                    }
                    lastListParagraph = unit.paragraph
                }
            case .sentence:
                lastListParagraph = -1
                let cleaned = cleanSentence(unit.text, professional: false, changes: &changes)
                if appendIfNew(cleaned, to: &seenSentences, changes: &changes) {
                    paragraphSentences.append(cleaned)
                }
            }
        }
        flushParagraph()
        changes.flushCounters()
        return output.joined(separator: "\n\n")
    }

    /// Exact duplicate sentences are removed (they add nothing). Returns false
    /// when the sentence was a duplicate.
    static func appendIfNew(_ sentence: String, to seen: inout Set<String>, changes: inout ChangeLog) -> Bool {
        let key = sentence.lowercased().filter { $0.isLetter || $0.isNumber }
        guard !key.isEmpty else { return true }
        if seen.contains(key) {
            changes.note("Removed a duplicated sentence (“\(PreservationChecker.truncate(sentence, 60))”).")
            return false
        }
        seen.insert(key)
        return true
    }

    // MARK: Sectioned layouts

    struct Section {
        var title: String
        var items: [String]
        var style: Style = .bullets

        enum Style { case bullets, numbered, checklist, paragraph, verbatim }
    }

    static func render(_ sections: [Section], headingPrefix: String = "## ") -> String {
        sections.filter { !$0.items.isEmpty }.map { section in
            let body: String
            switch section.style {
            case .bullets: body = section.items.map { "- " + $0 }.joined(separator: "\n")
            case .numbered: body = section.items.enumerated().map { "\($0.offset + 1). " + $0.element }.joined(separator: "\n")
            case .checklist: body = section.items.map { "- [ ] " + $0 }.joined(separator: "\n")
            case .paragraph: body = section.items.joined(separator: " ")
            case .verbatim: body = section.items.joined(separator: "\n\n")
            }
            return headingPrefix + section.title + "\n" + body
        }.joined(separator: "\n\n")
    }

    /// Cleans and de-duplicates the texts for a role.
    static func cleaned(
        _ analysis: PromptAnalysis,
        roles: Set<UnitRole>,
        where predicate: (ClassifiedUnit) -> Bool = { _ in true },
        professional: Bool = false,
        seen: inout Set<String>,
        changes: inout ChangeLog
    ) -> [String] {
        analysis.units
            .filter { roles.contains($0.role) && $0.unit.kind != .codeBlock && $0.unit.kind != .heading && predicate($0) }
            .compactMap { unit in
                let text = cleanSentence(unit.unit.text, professional: professional, changes: &changes)
                return appendIfNew(text, to: &seen, changes: &changes) ? text : nil
            }
    }

    static func headings(_ analysis: PromptAnalysis) -> [String] {
        analysis.units.filter { $0.unit.kind == .heading }.map(\.unit.text)
    }

    static func structured(_ analysis: PromptAnalysis, changes: inout ChangeLog) -> String {
        var seen = Set<String>()
        let objective = cleaned(analysis, roles: [.objective], seen: &seen, changes: &changes)
        let context = cleaned(analysis, roles: [.context], seen: &seen, changes: &changes)
        let requirements = cleaned(analysis, roles: [.requirement], seen: &seen, changes: &changes)
        let constraints = cleaned(analysis, roles: [.constraint], seen: &seen, changes: &changes)
        let output = cleaned(analysis, roles: [.output], seen: &seen, changes: &changes)
        let headingNotes = headings(analysis)

        let sections = [
            Section(title: "Objective", items: objective, style: .paragraph),
            Section(title: "Context", items: headingNotes.map { "Topic: \($0)" } + context),
            Section(title: "Requirements", items: requirements),
            Section(title: "Constraints", items: constraints),
            Section(title: "Expected Output", items: output),
            Section(title: "Reference Material", items: analysis.codeBlocks, style: .verbatim),
            Section(title: "Open Questions (answer if you can, otherwise state your assumptions)", items: analysis.missingInformation),
        ]
        noteSections(sections, changes: &changes)
        changes.flushCounters()
        return render(sections)
    }

    static func professional(_ analysis: PromptAnalysis, changes: inout ChangeLog) -> String {
        var seen = Set<String>()
        let objective = cleaned(analysis, roles: [.objective], professional: true, seen: &seen, changes: &changes)
        let context = cleaned(analysis, roles: [.context], professional: true, seen: &seen, changes: &changes)
        let details = cleaned(analysis, roles: [.requirement, .constraint], professional: true, seen: &seen, changes: &changes)
        let output = cleaned(analysis, roles: [.output], professional: true, seen: &seen, changes: &changes)

        var parts: [String] = []
        let opening = (objective + context).joined(separator: " ")
        if !opening.isEmpty { parts.append(opening) }
        let headingNotes = headings(analysis)
        if !headingNotes.isEmpty { parts.append("Topic: " + headingNotes.joined(separator: "; ")) }
        if !details.isEmpty {
            parts.append("Please observe the following:\n" + details.map { "- " + $0 }.joined(separator: "\n"))
            changes.note("Grouped requirements and constraints into a single list.")
        }
        if !output.isEmpty {
            parts.append("Deliverable: " + output.joined(separator: " "))
            changes.note("Stated the deliverable separately.")
        }
        parts.append(contentsOf: analysis.codeBlocks)
        changes.flushCounters()
        return parts.joined(separator: "\n\n")
    }

    static func developer(_ analysis: PromptAnalysis, changes: inout ChangeLog) -> String {
        var seen = Set<String>()
        func mentions(_ unit: ClassifiedUnit, _ terms: [String]) -> Bool {
            let lower = " " + unit.unit.text.lowercased() + " "
            return terms.contains { lower.contains($0) }
        }
        let testing: (ClassifiedUnit) -> Bool = { mentions($0, [" test", "testing", " qa ", "coverage", "xctest", "pytest", "jest"]) }
        let acceptance: (ClassifiedUnit) -> Bool = { mentions($0, ["acceptance", "criteria", "done when", "definition of done", "should pass", "must pass"]) }

        let goal = cleaned(analysis, roles: [.objective], seen: &seen, changes: &changes)
        let acceptanceItems = cleaned(analysis, roles: [.requirement, .constraint, .output, .context], where: acceptance, seen: &seen, changes: &changes)
        let testingItems = cleaned(analysis, roles: [.requirement, .constraint, .output, .context], where: testing, seen: &seen, changes: &changes)
        let context = cleaned(analysis, roles: [.context], seen: &seen, changes: &changes)
        let requirements = cleaned(analysis, roles: [.requirement], seen: &seen, changes: &changes)
        let constraints = cleaned(analysis, roles: [.constraint], seen: &seen, changes: &changes)
        let output = cleaned(analysis, roles: [.output], seen: &seen, changes: &changes)

        let sections = [
            Section(title: "Goal", items: goal, style: .paragraph),
            Section(title: "Context", items: headings(analysis).map { "Topic: \($0)" } + context),
            Section(title: "Functional Requirements", items: requirements, style: .numbered),
            Section(title: "Constraints", items: constraints),
            Section(title: "Expected Output", items: output),
            Section(title: "Acceptance Criteria", items: acceptanceItems, style: .checklist),
            Section(title: "Testing Expectations", items: testingItems),
            Section(title: "Reference Material", items: analysis.codeBlocks, style: .verbatim),
            Section(title: "Open Questions (answer if you can, otherwise state your assumptions)", items: analysis.missingInformation),
        ]
        noteSections(sections, changes: &changes)
        changes.flushCounters()
        return render(sections)
    }

    static func creative(_ analysis: PromptAnalysis, changes: inout ChangeLog) -> String {
        var seen = Set<String>()
        let styleTerms = PromptAnalyzer.toneTerms + ["inspired", "like ", "reminiscent", "aesthetic", "vibe", "palette", "colour", "color", "atmosphere"]
        let isStyle: (ClassifiedUnit) -> Bool = { unit in
            let lower = " " + unit.unit.text.lowercased() + " "
            return styleTerms.contains { lower.contains($0) }
        }
        let concept = cleaned(analysis, roles: [.objective], seen: &seen, changes: &changes)
        let direction = cleaned(analysis, roles: [.context, .requirement], where: isStyle, seen: &seen, changes: &changes)
        let background = cleaned(analysis, roles: [.context], seen: &seen, changes: &changes)
        let include = cleaned(analysis, roles: [.requirement], seen: &seen, changes: &changes)
        let avoid = cleaned(analysis, roles: [.constraint], seen: &seen, changes: &changes)
        let format = cleaned(analysis, roles: [.output], seen: &seen, changes: &changes)

        let sections = [
            Section(title: "Concept", items: concept, style: .paragraph),
            Section(title: "Background", items: headings(analysis).map { "Topic: \($0)" } + background),
            Section(title: "Direction & Style", items: direction),
            Section(title: "Must Include", items: include),
            Section(title: "Boundaries", items: avoid),
            Section(title: "Format", items: format),
            Section(title: "Reference Material", items: analysis.codeBlocks, style: .verbatim),
            Section(title: "Open Questions (answer if you can, otherwise make a choice and say what it was)", items: analysis.missingInformation),
        ]
        noteSections(sections, changes: &changes)
        changes.flushCounters()
        return render(sections)
    }

    static func noteSections(_ sections: [Section], changes: inout ChangeLog) {
        let titles = sections.filter { !$0.items.isEmpty }.map(\.title)
            .map { $0.components(separatedBy: " (").first ?? $0 }
        if !titles.isEmpty {
            changes.note("Organized the prompt into sections: \(titles.joined(separator: ", ")).")
        }
        if sections.contains(where: { $0.title.hasPrefix("Open Questions") && !$0.items.isEmpty }) {
            changes.note("Added open questions for information the prompt does not provide (questions only — no new requirements).")
        }
    }
}
