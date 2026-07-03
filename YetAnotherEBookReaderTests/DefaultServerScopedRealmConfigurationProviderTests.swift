import XCTest
import RealmSwift
@testable import YetAnotherEBookReader

final class DefaultServerScopedRealmConfigurationProviderTests: XCTestCase {
    private var provider: DefaultServerScopedRealmConfigurationProvider!
    
    override func setUp() {
        super.setUp()
        provider = DefaultServerScopedRealmConfigurationProvider()
    }
    
    override func tearDown() {
        provider = nil
        super.tearDown()
    }
    
    func testConfigurationIsCachedAndConsistent() {
        let server = CalibreServer(
            uuid: UUID(uuidString: "11111111-2222-3333-4444-555555555555")!,
            name: "Server A",
            baseUrl: "http://localhost:8080",
            hasPublicUrl: false,
            publicUrl: "",
            hasAuth: false,
            username: "",
            password: ""
        )
        
        let config1 = provider.configuration(for: server)
        let config2 = provider.configuration(for: server)
        
        XCTAssertEqual(config1.fileURL, config2.fileURL)
        XCTAssertEqual(config1.schemaVersion, config2.schemaVersion)
        
        // Assert schema version matches the AppContainer constant
        XCTAssertEqual(config1.schemaVersion, DatabaseSchema.version)
    }
    
    func testDifferentServersHaveDifferentConfigurations() {
        let serverA = CalibreServer(
            uuid: UUID(uuidString: "11111111-2222-3333-4444-555555555555")!,
            name: "Server A",
            baseUrl: "http://localhost:8080",
            hasPublicUrl: false,
            publicUrl: "",
            hasAuth: false,
            username: "",
            password: ""
        )
        let serverB = CalibreServer(
            uuid: UUID(uuidString: "99999999-8888-7777-6666-555555555555")!,
            name: "Server B",
            baseUrl: "http://localhost:9090",
            hasPublicUrl: false,
            publicUrl: "",
            hasAuth: false,
            username: "",
            password: ""
        )
        
        let configA = provider.configuration(for: serverA)
        let configB = provider.configuration(for: serverB)
        
        XCTAssertNotEqual(configA.fileURL, configB.fileURL)
        XCTAssertTrue(configA.fileURL?.lastPathComponent.contains("11111111-2222-3333-4444-555555555555") ?? false)
        XCTAssertTrue(configB.fileURL?.lastPathComponent.contains("99999999-8888-7777-6666-555555555555") ?? false)
    }
    
    func testConcurrentConfigurationAccess() {
        let server = CalibreServer(
            uuid: UUID(uuidString: "11111111-2222-3333-4444-555555555555")!,
            name: "Server A",
            baseUrl: "http://localhost:8080",
            hasPublicUrl: false,
            publicUrl: "",
            hasAuth: false,
            username: "",
            password: ""
        )
        
        let expectation = self.expectation(description: "Concurrent config loading completed")
        expectation.expectedFulfillmentCount = 20
        
        var results = [Realm.Configuration]()
        let resultsLock = NSLock()
        
        for _ in 0..<20 {
            DispatchQueue.global().async {
                let config = self.provider.configuration(for: server)
                resultsLock.lock()
                results.append(config)
                resultsLock.unlock()
                expectation.fulfill()
            }
        }
        
        waitForExpectations(timeout: 5, handler: nil)
        
        XCTAssertEqual(results.count, 20)
        for config in results {
            XCTAssertEqual(config.fileURL, results[0].fileURL)
            XCTAssertEqual(config.schemaVersion, results[0].schemaVersion)
        }
    }
}
