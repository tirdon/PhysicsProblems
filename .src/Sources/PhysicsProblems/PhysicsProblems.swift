import JavaScriptEventLoop
import JavaScriptKit

// swift package --package-path .src --scratch-path .build --swift-sdk 6.3-RELEASE-wasm32-unknown-wasip1-threads --allow-writing-to-directory script js --use-cdn --output script

@main
struct PhysicsProblems {
    nonisolated(unsafe) private static var app: BrowserSceneApp?

    static func main() {
        JavaScriptEventLoop.installGlobalExecutor()

        let sceneApp = BrowserSceneApp()
        app = sceneApp
		
		print(SIMD3<Int32>.zero &+ SIMD3<Int32>([1,2,3]))

        Task {
            do throws(JSException) {
                try await sceneApp.start()
            } catch {
				_ = JSObject.global.console.error("Failed to start PhysicsProblems:", error.thrownValue)
            }
        }
    }
}
