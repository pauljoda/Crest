import Observation

@Observable
@MainActor
final class BrowserPasskeyAccessController {
    static let shared = BrowserPasskeyAccessController()
    typealias CapabilityCheck = @MainActor () -> Bool
    typealias DeviceConfigurationCheck =
        @MainActor () -> BrowserPasskeyDeviceConfiguration
    typealias AuthorizationCheck = @MainActor () -> BrowserPasskeyAuthorizationState
    typealias AuthorizationRequester =
        @MainActor () async -> BrowserPasskeyAuthorizationState

    private(set) var status = BrowserPasskeyAccessStatus.checking
    private(set) var isRequesting = false

    @ObservationIgnored private let capabilityCheck: CapabilityCheck
    @ObservationIgnored private let deviceConfigurationCheck: DeviceConfigurationCheck
    @ObservationIgnored private let authorizationCheck: AuthorizationCheck
    @ObservationIgnored private let authorizationRequester: AuthorizationRequester
    @ObservationIgnored private var authorizationTask: Task<BrowserPasskeyAuthorizationState, Never>?

    init(
        capabilityCheck: @escaping CapabilityCheck =
            BrowserPasskeyAccessSystem.hasManagedCapability,
        deviceConfigurationCheck: @escaping DeviceConfigurationCheck =
            BrowserPasskeyAccessSystem.deviceConfiguration,
        authorizationCheck: @escaping AuthorizationCheck =
            BrowserPasskeyAccessSystem.authorizationState,
        authorizationRequester: @escaping AuthorizationRequester =
            BrowserPasskeyAccessSystem.requestAuthorization
    ) {
        self.capabilityCheck = capabilityCheck
        self.deviceConfigurationCheck = deviceConfigurationCheck
        self.authorizationCheck = authorizationCheck
        self.authorizationRequester = authorizationRequester
    }

    var canRequestAccess: Bool {
        status == .notDetermined && !isRequesting
    }

    func refreshStatus() {
        status = evaluatedStatus()
    }

    func requestAccess() async {
        if let authorizationTask {
            status = evaluatedStatus(authorizationState: await authorizationTask.value)
            return
        }
        guard canRequestAccess else { return }
        isRequesting = true
        defer {
            isRequesting = false
            authorizationTask = nil
        }

        let task = Task { await authorizationRequester() }
        authorizationTask = task
        let authorizationState = await task.value
        status = evaluatedStatus(authorizationState: authorizationState)
    }

    private func evaluatedStatus(
        authorizationState: BrowserPasskeyAuthorizationState? = nil
    ) -> BrowserPasskeyAccessStatus {
        guard capabilityCheck() else {
            return .managedCapabilityRequired
        }

        return BrowserPasskeyAccessPolicy.status(
            hasManagedCapability: true,
            deviceConfiguration: deviceConfigurationCheck(),
            authorizationState: authorizationState ?? authorizationCheck()
        )
    }
}
