import Testing
import Foundation
import HarnessCore
@testable import DevSpace

private func request(_ input: JSONValue, id: String = "req-1") -> PermissionRequest {
    PermissionRequest(id: id, toolName: "AskUserQuestion", input: input)
}

private func question(_ members: [String: JSONValue]) -> JSONValue {
    .object(members)
}

private let oneOption: JSONValue = .array([
    .object(["label": .string("Yes"), "description": .string("Go ahead")]),
])

@Test func promptReadsQuestionsOptionsAndFlags() throws {
    let prompt = try #require(QuestionPrompt(from: request(.object([
        "questions": .array([
            question([
                "question": .string("Which database?"),
                "header": .string("Database"),
                "multiSelect": .bool(true),
                "options": .array([
                    .object(["label": .string("Postgres"),
                             "description": .string("Relational")]),
                    .object(["label": .string("SQLite"),
                             "description": .string("Embedded")]),
                ]),
            ]),
        ]),
    ]), id: "req-42")))

    #expect(prompt.id == "req-42")
    #expect(prompt.questions.count == 1)
    let first = try #require(prompt.questions.first)
    #expect(first.text == "Which database?")
    #expect(first.header == "Database")
    #expect(first.multiSelect)
    #expect(first.options.map(\.label) == ["Postgres", "SQLite"])
    #expect(first.options.map(\.detail) == ["Relational", "Embedded"])
}

@Test func promptFillsInTheOptionalFields() throws {
    let withoutDescription: JSONValue = .array([.object(["label": .string("Yes")])])
    let prompt = try #require(QuestionPrompt(from: request(.object([
        "questions": .array([
            question(["question": .string("Proceed?"), "options": withoutDescription]),
        ]),
    ]))))

    let first = try #require(prompt.questions.first)
    #expect(first.header.isEmpty)
    #expect(first.multiSelect == false)
    #expect(first.options.first?.detail.isEmpty == true)
}

@Test func promptRefusesInputWithoutQuestions() {
    #expect(QuestionPrompt(from: request(.null)) == nil)
    #expect(QuestionPrompt(from: request(.object([:]))) == nil)
    #expect(QuestionPrompt(from: request(.object(["questions": .array([])]))) == nil)
    #expect(QuestionPrompt(from: request(.object(["questions": .string("nope")]))) == nil)
}

@Test func promptDropsQuestionsThatCannotBeDrawn() {
    let withoutText = question(["header": .string("No text"), "options": oneOption])
    let withoutOptions = question(["question": .string("No options")])
    let optionsWithoutLabel = question([
        "question": .string("Invalid options"),
        "options": .array([.object(["description": .string("no label")])]),
    ])

    for broken in [withoutText, withoutOptions, optionsWithoutLabel] {
        #expect(QuestionPrompt(from: request(.object(["questions": .array([broken])]))) == nil)
    }
}

@Test func promptKeepsTheGoodQuestionsBesideTheBadOnes() throws {
    let prompt = try #require(QuestionPrompt(from: request(.object([
        "questions": .array([
            question(["header": .string("dropped")]),
            question(["question": .string("Kept?"), "options": oneOption]),
        ]),
    ]))))

    #expect(prompt.questions.map(\.text) == ["Kept?"])
}

@Test func promptCarriesTheRequestForTheAnswer() throws {
    let original = request(.object([
        "questions": .array([
            question(["question": .string("Proceed?"), "options": oneOption]),
        ]),
    ]), id: "req-7")

    let prompt = try #require(QuestionPrompt(from: original))
    #expect(prompt.request == original)
}
