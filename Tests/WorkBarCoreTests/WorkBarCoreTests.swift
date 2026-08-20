import Testing
@testable import WorkBarCore

@Test
func packageExposesSchemaVersion() {
    #expect(WorkBarCore.schemaVersion == 1)
}
