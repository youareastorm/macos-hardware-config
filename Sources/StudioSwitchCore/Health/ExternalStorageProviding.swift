public protocol ExternalStorageProviding {
    func mountedExternalVolumeNames() -> [String]
}
