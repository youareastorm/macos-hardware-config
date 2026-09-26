import Foundation

public final class FileManagerExternalStorageProvider: ExternalStorageProviding {
    private let fileManager: FileManager

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    public func mountedExternalVolumeNames() -> [String] {
        let keys: [URLResourceKey] = [.volumeNameKey, .volumeIsInternalKey]
        guard let volumes = fileManager.mountedVolumeURLs(includingResourceValuesForKeys: keys, options: [.skipHiddenVolumes]) else {
            return []
        }
        return volumes.compactMap { url in
            guard let values = try? url.resourceValues(forKeys: Set(keys)),
                  values.volumeIsInternal == false,
                  let name = values.volumeName else { return nil }
            return name
        }
    }
}
