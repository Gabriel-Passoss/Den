import Testing
import Foundation
import DenMemory
@testable import Den

@Test func everyStateOfACaptureHasWordsForIt() {
    #expect(MemoryModel.Status.idle.caption == "A memória captura sozinha a cada poucas mensagens.")
    #expect(MemoryModel.Status.capturing.caption == "Capturando…")
    #expect(MemoryModel.Status.saved(1).caption == "1 memória salva")
    #expect(MemoryModel.Status.saved(3).caption == "3 memórias salvas")
    #expect(MemoryModel.Status.nothingNew.caption == "Nada novo para guardar")
    #expect(MemoryModel.Status.failed("a chamada ao harness falhou").caption == "a chamada ao harness falhou")
}

@Test func onlyAFailedCaptureReadsAsAFailure() {
    #expect(MemoryModel.Status.failed("x").isFailure)
    #expect(!MemoryModel.Status.saved(2).isFailure)
    #expect(!MemoryModel.Status.idle.isFailure)
}

@Test func eachLayerHasANameAndSaysWhatItWillHold() {
    #expect(MemoryLayer.project.title == "Projeto")
    #expect(MemoryLayer.user.title == "Usuário")
    #expect(MemoryLayer.project.emptyExplanation.contains("deste repositório"))
    #expect(MemoryLayer.user.emptyExplanation.contains("qualquer projeto"))
}

@Test func everyPaneOfTheInspectorHasItsShortcut() {
    #expect(InspectorPane.changes.shortcut == "⌥⌘0")
    #expect(InspectorPane.run.shortcut == "⌥⌘9")
    #expect(InspectorPane.memory.shortcut == "⌥⌘8")
    #expect(InspectorPane(rawValue: "memory") == .memory)
}
