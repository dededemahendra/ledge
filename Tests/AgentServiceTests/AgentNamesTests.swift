import Testing
@testable import AgentService

@Test(arguments: [
    ("ledge", "Ledge"), ("mornington-green", "Mornington green"), ("my_app.v2", "My app v2"),
    ("API-server", "API server"), ("fairwill", "Fairwill"), ("agent  island", "Agent island"),
    ("MyApp", "MyApp"), ("  -  ", "Claude"), ("", "Claude"), ("a--b__c", "A b c"),
])
func namesReadInSentenceCase(raw: String, shown: String) {
    #expect(AgentNames.display(raw) == shown)
}
