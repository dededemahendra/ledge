import Testing
import Foundation
@testable import AgentService

private func line(_ s: String) -> Data { Data(s.utf8) }

@Test func onlyAnExactUserTextIsAnInterrupt() {
    let by = #"{"type":"user","message":{"role":"user","content":[{"type":"text","text":"[Request interrupted by user]"}]}}"#
    let tool = #"{"type":"user","message":{"role":"user","content":[{"type":"text","text":"[Request interrupted by user for tool use]"}]}}"#
    let plain = #"{"type":"user","message":{"role":"user","content":"[Request interrupted by user]"}}"#
    let result = #"{"type":"user","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"x","content":"[Request interrupted by user]"}]}}"#
    let resultList = #"{"type":"user","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"x","content":[{"type":"text","text":"[Request interrupted by user]"}]}]}}"#
    let assistant = #"{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"[Request interrupted by user]"}]}}"#
    let more = #"{"type":"user","message":{"role":"user","content":[{"type":"text","text":"[Request interrupted by user] and more"}]}}"#
    #expect(AgentTranscript.isInterrupt(line(by)))
    #expect(AgentTranscript.isInterrupt(line(tool)))
    #expect(AgentTranscript.isInterrupt(line(plain)))
    #expect(!AgentTranscript.isInterrupt(line(result)))
    #expect(!AgentTranscript.isInterrupt(line(resultList)))
    #expect(!AgentTranscript.isInterrupt(line(assistant)))
    #expect(!AgentTranscript.isInterrupt(line(more)))
    #expect(!AgentTranscript.isInterrupt(line("not json")))
    #expect(!AgentTranscript.isInterrupt(line("[1,2]")))
}
