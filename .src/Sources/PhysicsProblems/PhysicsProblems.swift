import JavaScriptKit
import JavaScriptEventLoop

@main
struct PhysicsProblems {
	static func main() {
		JavaScriptEventLoop.installGlobalExecutor()
		
        print("Hello, world!")
		Task {
			print("task")
			await asdf()
			print("tasks")
		}
		print("done")
    }
}


nonisolated func asdf() async {
	print("asdfasdf")
}
