public enum UADConsoleSessionLoaderError: Error, Equatable {
    case appleScriptFailed(String)
}

public protocol UADConsoleSessionLoading {
    /// Asks UAD Console, already running, to load a different session file — see
    /// `AppleScriptUADConsoleSessionLoader` for why this needs more than a plain file-open.
    /// `discardingUnsavedChanges`: the open session has unsaved changes, so UAD Console will first
    /// ask whether to save them; answer "Don't Save".
    func loadSession(atPath path: String, discardingUnsavedChanges: Bool) throws
}
