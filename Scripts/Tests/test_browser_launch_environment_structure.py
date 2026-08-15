#!/usr/bin/env python3
"""Structural contracts for typed launch-environment ownership."""

from __future__ import annotations

from pathlib import Path
import re
import unittest


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
REPOSITORY_CONTRACT = REPOSITORY_ROOT / "Documentation/RepositoryGuardrails.md"
APPLICATION_ROOT = REPOSITORY_ROOT / "CrestShared/Application/BrowserLaunch"
ENVIRONMENT_OWNER = APPLICATION_ROOT / "Models/BrowserLaunchEnvironment.swift"
ISOLATION_POLICY = APPLICATION_ROOT / "Policies/BrowserLaunchIsolationPolicy.swift"
PROCESS_ADAPTER = (
    REPOSITORY_ROOT
    / "CrestShared/Infrastructure/BrowserLaunch/BrowserLaunchEnvironment+Process.swift"
)
STORE_COMPOSITION = (
    REPOSITORY_ROOT
    / "CrestShared/Infrastructure/BrowserStore/BrowserStore+Composition.swift"
)
SHORTCUT_STORE_COMPOSITION = (
    REPOSITORY_ROOT
    / "CrestShared/Infrastructure/BrowserShortcuts/"
    "BrowserShortcutStore+LaunchComposition.swift"
)
WINDOW_TRANSPARENCY_COMPOSITION = (
    REPOSITORY_ROOT
    / "CrestMac/Infrastructure/BrowserWindowTransparency/BrowserWindowTransparencyStore+LaunchComposition.swift"
)
MAC_APP = REPOSITORY_ROOT / "CrestMac/App/CrestApp.swift"
MOBILE_APP = REPOSITORY_ROOT / "CrestMobile/App/CrestMobileApp.swift"
MOBILE_WINDOW_SCENE = (
    REPOSITORY_ROOT / "CrestMobile/App/MobileBrowserWindowScene.swift"
)
MOBILE_WINDOW_MODEL = (
    REPOSITORY_ROOT
    / "CrestMobile/App/MobileBrowserWindowScene/Models/MobileBrowserWindowSceneModel.swift"
)
MOBILE_ONBOARDING_POLICY = (
    REPOSITORY_ROOT
    / "CrestMobile/App/MobileBrowserAutomaticOnboardingPolicy.swift"
)
ONBOARDING_COMPOSITION = (
    REPOSITORY_ROOT
    / "CrestShared/Infrastructure/BrowserOnboardingProgressStore+Composition.swift"
)
LINK_PREFERENCE_COMPOSITION = (
    REPOSITORY_ROOT
    / "CrestShared/Infrastructure/BrowserLinkPreferences/BrowserLinkPreferenceStore+Composition.swift"
)
CONTENT_RULE_PROVIDER = (
    REPOSITORY_ROOT
    / "CrestShared/Infrastructure/BrowserFilterLists/ContentBlocking/BrowserContentRuleListProvider.swift"
)
MAC_PAGE_POOL = (
    REPOSITORY_ROOT / "CrestMac/Infrastructure/WebKit/BrowserPagePool.swift"
)
MOBILE_PAGE_STORE = (
    REPOSITORY_ROOT / "CrestMobile/Infrastructure/WebKit/MobileBrowserPageStore.swift"
)
MOBILE_PAGE = (
    REPOSITORY_ROOT / "CrestMobile/Infrastructure/WebKit/MobileBrowserPage.swift"
)
EXTENSION_POOL = (
    REPOSITORY_ROOT
    / "CrestShared/Infrastructure/BrowserExtensionControllerPool.swift"
)
EXTENSION_RUNTIME = (
    REPOSITORY_ROOT
    / "CrestShared/Infrastructure/BrowserExtensions/Controller/BrowserExtensionRuntimeContextController.swift"
)
WEBSITE_DATA_STORE = (
    REPOSITORY_ROOT / "CrestShared/Infrastructure/BrowserWebsiteDataStore.swift"
)
PAGE_CONFIGURATION = (
    REPOSITORY_ROOT / "CrestShared/Infrastructure/BrowserPageConfiguration.swift"
)
MANUAL_SETUP_DRAFT_STORE = (
    REPOSITORY_ROOT
    / "CrestShared/Infrastructure/BrowserManualSetup/BrowserManualSetupDraftStore.swift"
)
IMPORT_ACCESS_STORE = (
    REPOSITORY_ROOT
    / "CrestMac/Features/Onboarding/Support/BrowserInstalledImportSource/BrowserImportAccessStore.swift"
)
SAFE_STORAGE_ADAPTER = (
    REPOSITORY_ROOT
    / "CrestMac/Features/Onboarding/Support/BrowserPasswordImport/LaunchScopedBrowserSafeStorage.swift"
)
PASSWORD_IMPORT_READER = (
    REPOSITORY_ROOT
    / "CrestMac/Features/Onboarding/Services/BrowserPasswordImport/BrowserPasswordImportReader.swift"
)
IMPORT_COMMITTER = (
    REPOSITORY_ROOT
    / "CrestMac/Features/Onboarding/BrowserOnboardingWindow/Services/LiveBrowserOnboardingImportCommitter.swift"
)
SYSTEM_PASSWORD_WRITE_THROUGH = (
    REPOSITORY_ROOT
    / "CrestMobile/Infrastructure/BrowserPasskeyAccess/BrowserSystemPasswordWriteThroughSystem.swift"
)
SYSTEM_PASSWORD_AVAILABILITY = (
    REPOSITORY_ROOT
    / "CrestShared/Domain/BrowserPasskeyAccess/Models/BrowserSystemPasswordWriteThroughAvailability.swift"
)
SYSTEM_PASSWORD_POLICY = (
    REPOSITORY_ROOT
    / "CrestShared/Domain/BrowserPasskeyAccess/Policies/BrowserSystemPasswordWriteThroughPolicy.swift"
)
MOBILE_CREDENTIAL_PROMPT = (
    REPOSITORY_ROOT
    / "CrestMobile/Features/Credentials/MobileCredentialSavePrompt/MobileCredentialSavePrompt.swift"
)
PASSWORD_SETTINGS_PANE = (
    REPOSITORY_ROOT
    / "CrestShared/Features/Settings/BrowserPasswordSettingsPane/BrowserPasswordSettingsPane.swift"
)
LEGACY_POLICY = (
    REPOSITORY_ROOT
    / "CrestShared/Application/BrowserStore/Policies/BrowserLaunchIsolationPolicy.swift"
)
SOURCE_ROOTS = tuple(
    REPOSITORY_ROOT / root for root in ("CrestShared", "CrestMac", "CrestMobile")
)
LAUNCH_KEYS = (
    "CREST_ISOLATED_SESSION",
    "CREST_RESET_SESSION",
    "CREST_SHOWCASE_SESSION",
    "CREST_USE_IN_MEMORY_CREDENTIALS",
    "CREST_SHOW_ONBOARDING",
    "CREST_SHOW_SETUP",
    "CREST_FORCE_ONBOARDING_SETUP",
    "CREST_PERFORMANCE_BASE_URL",
    "CREST_PERFORMANCE_TAB_COUNT",
    "CREST_PERFORMANCE_RUN_ID",
)
ISOLATING_VALUES = (
    "explicitlyRequiresIsolation",
    "resetsSession",
    "presentsShowcaseSession",
    "usesInMemoryCredentialVault",
    "forcesOnboardingWelcome",
    "forcesMacOnboardingSetup",
    "forcesMobileOnboardingSetup",
    "performanceBaseURLString",
)
DECLARATION_PATTERN = re.compile(
    r"^(?:@[A-Za-z_][A-Za-z0-9_]*(?:\([^\n]*\))?\s*)*"
    r"(?:(?:public|internal|private|fileprivate|package|open|final|indirect|"
    r"nonisolated(?:\(unsafe\))?|distributed)\s+)*"
    r"(?:struct|enum|class|actor|protocol|typealias)\s+([A-Za-z_][A-Za-z0-9_]*)",
    re.MULTILINE,
)


class BrowserLaunchEnvironmentStructureTests(unittest.TestCase):
    def test_launch_values_policy_and_process_adapter_have_explicit_owners(self) -> None:
        for path in (
            ENVIRONMENT_OWNER,
            ISOLATION_POLICY,
            PROCESS_ADAPTER,
            MOBILE_ONBOARDING_POLICY,
        ):
            with self.subTest(path=path.relative_to(REPOSITORY_ROOT)):
                self.assertTrue(path.is_file())
        self.assertFalse(LEGACY_POLICY.exists())

    def test_each_launch_owner_has_matching_primary_declaration(self) -> None:
        paths = [
            path
            for root in (APPLICATION_ROOT, PROCESS_ADAPTER.parent)
            for path in root.rglob("*.swift")
        ] + [MOBILE_ONBOARDING_POLICY]
        for path in paths:
            declarations = DECLARATION_PATTERN.findall(path.read_text())
            expected = [] if "+" in path.stem else [path.stem]
            with self.subTest(path=path.relative_to(REPOSITORY_ROOT)):
                self.assertEqual(declarations, expected)

    def test_each_crest_launch_key_is_parsed_only_by_the_typed_owner(self) -> None:
        sources = {
            path: path.read_text()
            for root in SOURCE_ROOTS
            for path in root.rglob("*.swift")
        }
        for key in LAUNCH_KEYS:
            owners = [path for path, source in sources.items() if key in source]
            with self.subTest(key=key):
                self.assertEqual(owners, [ENVIRONMENT_OWNER])

    def test_composition_roots_consume_the_typed_launch_value(self) -> None:
        for path in (STORE_COMPOSITION, MAC_APP, MOBILE_APP):
            source = path.read_text()
            with self.subTest(path=path.relative_to(REPOSITORY_ROOT)):
                self.assertIn("BrowserLaunchEnvironment", source)
                self.assertNotIn("ProcessInfo.processInfo.environment", source)
                self.assertNotIn("NSClassFromString", source)

        process_source = PROCESS_ADAPTER.read_text()
        self.assertIn("ProcessInfo.processInfo", process_source)
        self.assertIn("process.environment", process_source)
        self.assertIn('NSClassFromString("XCTestCase")', process_source)
        self.assertIn("XCTestConfigurationFilePath", process_source)
        self.assertIn("XCODE_RUNNING_FOR_PREVIEWS", process_source)

        mobile_app_source = MOBILE_APP.read_text()
        self.assertNotIn("enum MobileBrowserAutomaticOnboardingPolicy", mobile_app_source)

    def test_installed_session_composition_is_reachable_only_from_app_roots(self) -> None:
        callers = [
            path
            for root in SOURCE_ROOTS
            for path in root.rglob("*.swift")
            if "BrowserStore.production(" in path.read_text()
        ]
        self.assertEqual(callers, [MAC_APP, MOBILE_APP])

        store_source = STORE_COMPOSITION.read_text()
        self.assertEqual(store_source.count("UserDefaultsBrowserSessionPersistence()"), 1)
        self.assertEqual(
            store_source.count("UserDefaultsBrowserSyncJournalPersistence()"),
            1,
        )
        self.assertEqual(store_source.count("KeychainCredentialVault()"), 1)

    def test_every_fixture_flag_selects_the_isolated_persistence_graph(self) -> None:
        policy_source = ISOLATION_POLICY.read_text()
        for value in ISOLATING_VALUES:
            with self.subTest(value=value):
                self.assertIn(f"environment.{value}", policy_source)
        self.assertNotIn(
            "guard environment.performanceBaseURLString == nil else",
            policy_source,
        )

        for path in (MAC_APP, MOBILE_APP):
            source = path.read_text()
            with self.subTest(path=path.relative_to(REPOSITORY_ROOT)):
                self.assertIn("BrowserStore.isolatedLaunch", source)
                self.assertIn("BrowserCloudSyncController.isolated", source)
                self.assertIn("usesEphemeralWebsiteDataStores: usesIsolatedLaunch", source)
                self.assertIn("BrowserOnboardingProgressStore.launchStore", source)
                self.assertIn("isIsolated: usesIsolatedLaunch", source)

        mac_app_source = MAC_APP.read_text()
        shortcut_store_source = SHORTCUT_STORE_COMPOSITION.read_text()
        self.assertIn("BrowserShortcutStore.launch(", mac_app_source)
        self.assertIn(
            "usesIsolatedLaunch: usesIsolatedLaunch",
            mac_app_source,
        )
        self.assertIn("return .inMemory()", shortcut_store_source)
        isolation_guard = shortcut_store_source.index(
            "guard !usesIsolatedLaunch"
        )
        persistent_construction = shortcut_store_source.index(
            "persistentPersistence()"
        )
        self.assertLess(isolation_guard, persistent_construction)

        store_source = STORE_COMPOSITION.read_text()
        self.assertIn(
            "BrowserLaunchIsolationPolicy.requiresIsolation(launchEnvironment)",
            store_source,
        )
        self.assertIn("return isolatedLaunch", store_source)
        self.assertIn("BrowserPerformanceSoakFixture.makeSession", store_source)

        mobile_scene_source = MOBILE_WINDOW_SCENE.read_text()
        mobile_model_source = MOBILE_WINDOW_MODEL.read_text()
        self.assertIn(
            "usesEphemeralWebsiteDataStores: usesEphemeralWebsiteDataStores",
            mobile_scene_source,
        )
        self.assertIn(
            "usesEphemeralWebsiteDataStores: usesEphemeralWebsiteDataStores",
            mobile_model_source,
        )

        for path in (MAC_PAGE_POOL, MOBILE_PAGE_STORE):
            source = path.read_text()
            with self.subTest(path=path.relative_to(REPOSITORY_ROOT)):
                self.assertIn(
                    "BrowserLaunchIsolationPolicy.requiresIsolation(.current)",
                    source,
                )

    def test_xctest_hosts_do_not_construct_installed_application_ui(self) -> None:
        policy_source = ISOLATION_POLICY.read_text()
        self.assertIn(
            "static func presentsInstalledApplicationUI(",
            policy_source,
        )
        self.assertIn("!environment.isXCTestRuntime", policy_source)

        for path in (MAC_APP, MOBILE_APP):
            source = path.read_text()
            with self.subTest(path=path.relative_to(REPOSITORY_ROOT)):
                self.assertIn(
                    "BrowserLaunchIsolationPolicy.presentsInstalledApplicationUI(",
                    source,
                )
                self.assertIn("if presentsInstalledApplicationUI", source)
                self.assertIn("EmptyView()", source)

        self.assertIn('"crest-xctest-host"', MAC_APP.read_text())

    def test_process_wide_shared_owners_respect_launch_isolation(self) -> None:
        for path in (
            LINK_PREFERENCE_COMPOSITION,
            CONTENT_RULE_PROVIDER,
            WEBSITE_DATA_STORE,
            MANUAL_SETUP_DRAFT_STORE,
            IMPORT_ACCESS_STORE,
        ):
            source = path.read_text()
            with self.subTest(path=path.relative_to(REPOSITORY_ROOT)):
                self.assertIn("BrowserLaunchIsolationPolicy.requiresIsolation(.current)", source)

        page_configuration_source = PAGE_CONFIGURATION.read_text()
        mobile_page_source = MOBILE_PAGE.read_text()
        self.assertIn(
            "BrowserWebsiteDataStore.launchScoped(for: profile)",
            page_configuration_source,
        )
        # The mobile page used to reach for a launch-scoped store itself. It now
        # builds its configuration through the shared factory asserted above, so
        # isolation has one owner instead of two; what matters here is that the
        # mobile page cannot acquire a store that bypasses it.
        self.assertIn("BrowserPageConfiguration.make(", mobile_page_source)
        self.assertNotIn("WKWebsiteDataStore.default()", mobile_page_source)
        self.assertNotIn("WKWebsiteDataStore(forIdentifier:", mobile_page_source)

        onboarding_source = ONBOARDING_COMPOSITION.read_text()
        self.assertIn("InMemoryBrowserOnboardingProgressPersistence", onboarding_source)
        self.assertIn("UserDefaultsBrowserOnboardingProgressPersistence", onboarding_source)

        transparency_source = WINDOW_TRANSPARENCY_COMPOSITION.read_text()
        self.assertIn("usesIsolatedLaunch", transparency_source)
        self.assertIn("makeIsolatedPersistence()", transparency_source)
        self.assertIn("makePersistentPersistence()", transparency_source)
        self.assertLess(
            transparency_source.index("makeIsolatedPersistence()"),
            transparency_source.index("makePersistentPersistence()"),
        )

        content_rule_source = CONTENT_RULE_PROVIDER.read_text()
        self.assertIn("ruleListStore: nil", content_rule_source)
        self.assertIn("guard let ruleListStore else { return [] }", content_rule_source)

        extension_pool_source = EXTENSION_POOL.read_text()
        extension_runtime_source = EXTENSION_RUNTIME.read_text()
        self.assertIn("usesEphemeralWebKitStorage: Bool = true", extension_pool_source)
        self.assertIn("usesEphemeralWebKitStorage: false", extension_pool_source)
        self.assertIn("configuration = .nonPersistent()", extension_runtime_source)
        self.assertIn("websiteDataStore = .nonPersistent()", extension_runtime_source)

        repository_contract = REPOSITORY_CONTRACT.read_text()
        self.assertIn("CREST_ISOLATED_SESSION=1", repository_contract)
        self.assertIn(
            "Never run sample Spaces against the installed profile",
            repository_contract,
        )

    def test_isolated_launches_cannot_reach_system_credential_services(self) -> None:
        self.assertTrue(SAFE_STORAGE_ADAPTER.is_file())
        safe_storage_source = SAFE_STORAGE_ADAPTER.read_text()
        password_reader_source = PASSWORD_IMPORT_READER.read_text()
        committer_source = IMPORT_COMMITTER.read_text()
        system_password_source = SYSTEM_PASSWORD_WRITE_THROUGH.read_text()
        system_password_availability_source = (
            SYSTEM_PASSWORD_AVAILABILITY.read_text()
        )
        system_password_policy_source = SYSTEM_PASSWORD_POLICY.read_text()
        prompt_source = MOBILE_CREDENTIAL_PROMPT.read_text()
        password_settings_source = PASSWORD_SETTINGS_PANE.read_text()

        self.assertIn(
            "BrowserLaunchIsolationPolicy.requiresIsolation(launchEnvironment)",
            safe_storage_source,
        )
        self.assertIn(
            "private let safeStorage: (any BrowserSafeStorageSecretProviding)?",
            safe_storage_source,
        )
        self.assertIn("safeStorage = nil", safe_storage_source)
        self.assertIn("systemStorage: () -> any", safe_storage_source)
        self.assertIn(
            "BrowserPasswordImportError.safeStorageUnavailable",
            safe_storage_source,
        )
        self.assertNotIn(
            "= SecurityBrowserSafeStorage()",
            password_reader_source,
        )
        self.assertIn("LaunchScopedBrowserSafeStorage()", committer_source)
        self.assertIn("case isolatedLaunch", system_password_availability_source)
        self.assertIn("isLaunchIsolated", system_password_policy_source)
        self.assertIn("return .isolatedLaunch", system_password_policy_source)
        self.assertIn(
            "availability(for: launchEnvironment)",
            system_password_source,
        )
        self.assertNotIn("static var availability:", system_password_source)
        self.assertLess(
            system_password_source.index("availability(for: launchEnvironment)"),
            system_password_source.index("ASCredentialDataManager().save"),
        )
        self.assertIn("launchAvailability", prompt_source)
        self.assertIn("launchAvailability", password_settings_source)
        self.assertNotIn("allowsSystemCredentialAccess", prompt_source)


if __name__ == "__main__":
    unittest.main()
