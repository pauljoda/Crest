extension BrowserMediaPermission {
    var displayName: String {
        switch self {
        case .camera:
            "camera"
        case .microphone:
            "microphone"
        case .cameraAndMicrophone:
            "camera and microphone"
        }
    }

    var settingsLabel: String {
        switch self {
        case .camera:
            "Camera"
        case .microphone:
            "Microphone"
        case .cameraAndMicrophone:
            "Camera & Microphone"
        }
    }
}
