public protocol UADConsoleSessionInspecting {
    /// Best-effort name of the session currently open in UAD Console (e.g. its window title),
    /// or nil when UAD Console isn't running or no session window could be read.
    func currentSessionName() -> String?
}
