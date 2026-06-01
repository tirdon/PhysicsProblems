import JavaScriptEventLoop
import JavaScriptKit

// swift package --package-path .src --scratch-path .build --swift-sdk 6.3-RELEASE-wasm32-unknown-wasip1-threads --allow-writing-to-directory script  js --use-cdn  --output script

typealias DedicatedTaskExecutor = JavaScriptEventLoop

@main
struct PhysicsProblems {
	static func main() throws {
		JavaScriptEventLoop.installGlobalExecutor()
		let useDedicatedWorker = !(JSObject.global.disableDedicatedWorker.boolean ?? false)
		
		print("Hello, world!")
		Task {
			if useDedicatedWorker {
				print("task")
				print("")
			}
			
			try await asdf()
			print("tasks")
		}
		print("done")
    }
}

func asdf() async throws {
	print("asdfasdf")
	_ = try await WebWorkerTaskExecutor(numberOfThreads: 2)
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
