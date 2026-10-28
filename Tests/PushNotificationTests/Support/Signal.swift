/// A one-shot, awaitable signal, used to coordinate a test with a suspended call it wants to
/// cancel mid-flight: `wait()` suspends until `fire()` is called (from anywhere), or returns
/// immediately if `fire()` already happened.
actor Signal {
    private var fired = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func fire() {
        guard !fired else { return }
        fired = true
        for waiter in waiters {
            waiter.resume()
        }
        waiters.removeAll()
    }

    func wait() async {
        if fired {
            return
        }
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }
}
