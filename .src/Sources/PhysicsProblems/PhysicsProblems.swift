import JavaScriptEventLoop
import JavaScriptKit

// swift package --package-path .src --scratch-path .build --swift-sdk 6.3-RELEASE-wasm32-unknown-wasip1-threads --allow-writing-to-directory script  js --use-cdn  --output script

typealias DedicatedTaskExecutor = JavaScriptEventLoop

@main
struct PhysicsProblems {
	static func main() throws {
		DedicatedTaskExecutor.installGlobalExecutor()
		
		print("Hello, world!")
		Task {
#if wasi_pthread
//			let executor = try await WebWorkerDedicatedExecutor()
			let executor = try await WebWorkerTaskExecutor(numberOfThreads: 1)
			
			defer { executor.terminate() }
#endif
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


#if canImport(wasi_pthread)
import wasi_pthread
import WASILibc

/// Trick to avoid blocking the main thread. pthread_mutex_lock function is used by
/// the Swift concurrency runtime.
@_cdecl("pthread_mutex_lock")
func pthread_mutex_lock(_ mutex: UnsafeMutablePointer<pthread_mutex_t>) -> Int32 {
	// DO NOT BLOCK MAIN THREAD
	var ret: Int32
	repeat {
		ret = pthread_mutex_trylock(mutex)
	} while ret == EBUSY
	return ret
}
#endif
