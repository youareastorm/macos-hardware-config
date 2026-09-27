public enum UADConsoleSessionLoaderError: Error, Equatable {
    case appleScriptFailed(String)
}

public protocol UADConsoleSessionLoading {
    /// Asks UAD Console, already running, to load a different session file — see
    /// `AppleScriptUADConsoleSessionLoader` for why this needs more than a plain file-open.
    func loadSession(atPath path: String) throws
}
