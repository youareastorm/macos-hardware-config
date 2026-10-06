import Foundation

/// Runs an AppleScript on the main thread, whichever thread asks. Apple's `NSAppleScript` isn't
/// thread-safe and is documented for main-thread use only; this app drives it from background
/// queues (activation, the plug-in watcher), where running it directly is the prime suspect for a
/// session switch that worked from a Terminal script but not from the app. Blocks the caller (not
/// the main thread, unless the caller is on it) until the script finishes.
func runAppleScriptOnMainThread(_ source: String) -> (result: NSAppleEventDescriptor?, error: NSDictionary?) {
    let run = { () -> (NSAppleEventDescriptor?, NSDictionary?) in
        guard let script = NSAppleScript(source: source) else {
            return (nil, ["NSAppleScriptErrorMessage": "could not parse AppleScript source"])
        }
        var errorInfo: NSDictionary?
        let result = script.executeAndReturnError(&errorInfo)
        return errorInfo == nil ? (result, nil) : (nil, errorInfo)
    }
    return Thread.isMainThread ? run() : DispatchQueue.main.sync(execute: run)
}
