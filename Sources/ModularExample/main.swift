import Foundation
import Katana

let app = await App()
let repo = await app.resolve(TodoRepository.self)
await repo.add("Modular example task 1")
await repo.add("Modular example task 2")

let logger = await app.resolve(Logger.self)
logger.log("hello from ModularExample")

let analytics = await app.resolve(AnalyticsClient.self)
analytics.track("first run")

let all = await repo.all()
print("\n— Tasks —")
for item in all { print(" •", item) }

let snap = await app.snapshot()
let again = snap.resolve(TodoRepository.self)
print("\nsnapshot returns same repo:", repo === again)

// MARK: - TestApp smoke test (would normally live in a Tests target)

print("\n— TestApp smoke test —")
final class SpyLogger: Logger, @unchecked Sendable {
    nonisolated(unsafe) var lines: [String] = []
    required init() { super.init() }
    override func log(_ msg: String) { lines.append(msg) }
}

let testApp = await TestApp { c in
    await c.override(Logger.self, with: SpyLogger())
}
let testLogger = await testApp.resolve(Logger.self)
testLogger.log("captured by spy")
print("spy is a SpyLogger:", testLogger is SpyLogger)
print("spy captured:", (testLogger as? SpyLogger)?.lines ?? [])

// Post-construction override.
let testApp2 = await TestApp()
let anotherSpy = SpyLogger()
await testApp2.override(Logger.self, with: anotherSpy)
let postLogger = await testApp2.resolve(Logger.self)
postLogger.log("after construction")
print("post-construction override took effect:", postLogger === anotherSpy)

// Marker conformance compiles → @KatanaTestApp emitted it.
let _: any TestContainerMarker = testApp
