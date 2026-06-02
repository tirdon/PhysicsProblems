import JavaScriptEventLoop
import JavaScriptKit

// swift package --package-path .src --scratch-path .build --swift-sdk 6.3-RELEASE-wasm32-unknown-wasip1-threads --allow-writing-to-directory script  js --use-cdn  --output script

@main
struct PhysicsProblems {
	static func main() throws {
		JavaScriptEventLoop.installGlobalExecutor()
//		let s = JSSending(.init())
		
		
		print("Hello, world!")
		Task {
			print("task")
			print("")
			
			try await asdf()
			print("tasks")
		}
		print("done")
    }
}

func asdf() async throws {
	print("asdfasdf")
}

//@_expose(wasm, "add")
@JS
func add(_ obj: JSObject) -> Int {
	10
}
