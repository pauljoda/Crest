extension BrowserSitePermission {
    var settingsLabel: String {
        switch self {
        case .camera:
            "Camera"
        case .microphone:
            "Microphone"
        case .cameraAndMicrophone:
            "Camera & Microphone"
        case .popups:
            "Pop-ups"
        case .automaticDownloads:
            "Automatic Downloads"
        case .externalApplications:
            "External Apps"
        }
    }

    var symbol: String {
        switch self {
        case .camera:
            "video"
        case .microphone:
            "mic"
        case .cameraAndMicrophone:
            "video.and.waveform"
        case .popups:
            "macwindow.on.rectangle"
        case .automaticDownloads:
            "arrow.down.circle"
        case .externalApplications:
            "arrow.up.forward.app"
        }
    }
}
