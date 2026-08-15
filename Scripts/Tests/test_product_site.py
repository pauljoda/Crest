#!/usr/bin/env python3
"""Product-site contracts for Crest branding, interaction, and framing."""

from __future__ import annotations

import hashlib
import json
import pathlib
import re
import struct
import unittest
import xml.etree.ElementTree as element_tree


REPOSITORY_ROOT = pathlib.Path(__file__).resolve().parents[2]
WEBSITE_ROOT = REPOSITORY_ROOT / "Website"
HELP_CENTER_ROOT = REPOSITORY_ROOT / "HelpCenter"


class ProductSiteTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.homepage = (WEBSITE_ROOT / "index.html").read_text()
        cls.documentation = (WEBSITE_ROOT / "docs/index.html").read_text()
        cls.privacy = (WEBSITE_ROOT / "privacy/index.html").read_text()
        cls.support = (WEBSITE_ROOT / "support/index.html").read_text()
        cls.extension_compatibility = (
            REPOSITORY_ROOT / "Documentation/ExtensionCompatibility.md"
        ).read_text()
        cls.styles = (WEBSITE_ROOT / "styles.css").read_text()
        cls.help_styles = (HELP_CENTER_ROOT / "src/css/custom.css").read_text()
        cls.script = (WEBSITE_ROOT / "site.js").read_text()
        cls.readme = (REPOSITORY_ROOT / "README.md").read_text()
        cls.source_demo = (WEBSITE_ROOT / "demos/source/index.html").read_text()
        cls.trail_demo = (WEBSITE_ROOT / "demos/trail/index.html").read_text()
        cls.manifest = json.loads((WEBSITE_ROOT / "site.webmanifest").read_text())

    @staticmethod
    def png_size(path: pathlib.Path) -> tuple[int, int]:
        with path.open("rb") as image:
            assert image.read(8) == b"\x89PNG\r\n\x1a\n"
            assert struct.unpack(">I", image.read(4))[0] == 13
            assert image.read(4) == b"IHDR"
            return struct.unpack(">II", image.read(8))

    def test_product_logo_is_the_site_brand_and_favicon(self) -> None:
        self.assertTrue((WEBSITE_ROOT / "assets/crest-logo.svg").is_file())
        self.assertIn(
            '<link rel="icon" type="image/svg+xml" href="assets/crest-logo.svg">',
            self.homepage,
        )
        self.assertIn(
            '<link rel="icon" type="image/svg+xml" href="../assets/crest-logo.svg">',
            self.documentation,
        )
        self.assertIn(
            '<link rel="icon" type="image/svg+xml" href="../assets/crest-logo.svg">',
            self.privacy,
        )
        self.assertIn(
            '<link rel="icon" type="image/svg+xml" href="../assets/crest-logo.svg">',
            self.support,
        )
        self.assertGreaterEqual(self.homepage.count('class="brand-mark"'), 2)
        self.assertNotIn("wordmark-shield", self.homepage + self.documentation)
        self.assertNotIn("crest-icon.jpg", self.homepage + self.documentation + self.readme)

        expected_icons = {
            "assets/crest-icon-32.png": (32, 32),
            "assets/apple-touch-icon.png": (180, 180),
            "assets/crest-icon-192.png": (192, 192),
            "assets/crest-icon-512.png": (512, 512),
        }
        for filename, size in expected_icons.items():
            with self.subTest(filename=filename):
                self.assertEqual(self.png_size(WEBSITE_ROOT / filename), size)

        favicon = WEBSITE_ROOT / "favicon.ico"
        self.assertTrue(favicon.is_file())
        self.assertEqual(favicon.read_bytes()[:4], b"\x00\x00\x01\x00")
        self.assertIn('rel="apple-touch-icon"', self.homepage)
        self.assertIn('rel="manifest" href="site.webmanifest"', self.homepage)
        self.assertEqual(self.manifest["name"], "Crest Browser")
        self.assertEqual(
            {icon["sizes"] for icon in self.manifest["icons"]},
            {"192x192", "512x512"},
        )

    def test_search_and_social_discovery_metadata_is_complete(self) -> None:
        canonical_home = "https://pauljoda.github.io/Crest-Website/"
        canonical_docs = f"{canonical_home}docs/"
        canonical_privacy = f"{canonical_home}privacy/"
        canonical_support = f"{canonical_home}support/"
        preview_image = f"{canonical_home}assets/og-card-brand.jpg"
        preview_alt = "Crest app icon beside the words Your internet, under your colors"

        self.assertIn(f'<link rel="canonical" href="{canonical_home}">', self.homepage)
        self.assertIn(f'<link rel="canonical" href="{canonical_docs}">', self.documentation)
        self.assertIn(f'<link rel="canonical" href="{canonical_privacy}">', self.privacy)
        self.assertIn(f'<link rel="canonical" href="{canonical_support}">', self.support)
        for page, url in (
            (self.homepage, canonical_home),
            (self.documentation, canonical_docs),
            (self.privacy, canonical_privacy),
            (self.support, canonical_support),
        ):
            with self.subTest(url=url):
                self.assertIn(f'<meta property="og:url" content="{url}">', page)
                self.assertIn(f'<meta property="og:image" content="{preview_image}">', page)
                self.assertIn('<meta property="og:image:width" content="1200">', page)
                self.assertIn('<meta property="og:image:height" content="630">', page)
                self.assertIn(f'<meta property="og:image:alt" content="{preview_alt}">', page)
                self.assertIn('<meta name="twitter:card" content="summary_large_image">', page)
                self.assertIn(f'<meta name="twitter:image:alt" content="{preview_alt}">', page)
                self.assertIn('name="robots" content="index, follow, max-image-preview:large', page)

        preview_source = (WEBSITE_ROOT / "assets/og-card-source.svg").read_text()
        self.assertTrue((WEBSITE_ROOT / "assets/og-card-brand.jpg").is_file())
        self.assertFalse((WEBSITE_ROOT / "assets/og-card.jpg").exists())
        self.assertIn('href="crest-icon-512.png"', preview_source)
        self.assertIn("Your internet,", preview_source)
        self.assertIn("under your colors.", preview_source)
        self.assertIn("Native on Mac, iPad, and iPhone.", preview_source)
        self.assertNotIn("Four heraldic Crest Space banners", self.homepage + self.documentation + self.privacy + self.support)

        structured_blocks = re.findall(
            r'<script type="application/ld\+json">\s*(.*?)\s*</script>',
            self.homepage + self.documentation + self.privacy + self.support,
            re.DOTALL,
        )
        self.assertEqual(len(structured_blocks), 4)
        structured_data = [json.loads(block) for block in structured_blocks]
        homepage_types = {item["@type"] for item in structured_data[0]["@graph"]}
        self.assertEqual(homepage_types, {"WebSite", "SoftwareApplication"})
        self.assertEqual(structured_data[1]["@type"], "WebPage")
        self.assertEqual(structured_data[2]["@type"], "WebPage")
        self.assertEqual(structured_data[3]["@type"], "WebPage")

        self.assertIn('content="noindex, nofollow"', self.source_demo)
        self.assertIn('content="noindex, nofollow"', self.trail_demo)
        robots = (WEBSITE_ROOT / "robots.txt").read_text()
        self.assertIn(f"Sitemap: {canonical_home}sitemap.xml", robots)
        sitemap = element_tree.parse(WEBSITE_ROOT / "sitemap.xml").getroot()
        locations = {
            child.text
            for child in sitemap.findall("{http://www.sitemaps.org/schemas/sitemap/0.9}url/{http://www.sitemaps.org/schemas/sitemap/0.9}loc")
        }
        self.assertEqual(
            locations,
            {canonical_home, canonical_docs, canonical_privacy, canonical_support},
        )
        self.assertEqual((WEBSITE_ROOT / "CNAME").read_text().strip(), "crestbrowser.com")
        self.assertTrue((WEBSITE_ROOT / ".nojekyll").is_file())

    def test_privacy_policy_is_plain_language_complete_and_linked(self) -> None:
        self.assertIn('href="privacy/">Privacy</a>', self.homepage)
        self.assertIn('href="../privacy/">Privacy</a>', self.documentation)
        self.assertIn("Effective August 9, 2026", self.privacy)
        self.assertIn("Your browsing", self.privacy)
        self.assertIn("No analytics or ads", self.privacy)
        self.assertIn("No browsing-data server", self.privacy)
        self.assertIn("does not collect or receive your browsing history", self.privacy)
        self.assertIn("private CloudKit database", self.privacy)
        self.assertIn("Password values never enter CloudKit", self.privacy)
        self.assertIn("Search-source attribution", self.privacy)
        self.assertIn("does not add a Crest source or partner parameter", self.privacy)
        self.assertIn("fixed, app-wide source-attribution parameter", self.privacy)
        self.assertIn("person, device, Space, session, or account", self.privacy)
        self.assertIn("<code>t</code>", self.privacy)
        self.assertIn("https://duckduckgo.com/duckduckgo-help-pages/privacy/t", self.privacy)
        self.assertIn("https://developer.apple.com/documentation/cloudkit/ckcontainer/privateclouddatabase", self.privacy)
        self.assertIn("https://docs.github.com/en/pages/getting-started-with-github-pages/what-is-github-pages", self.privacy)
        self.assertIn("https://developer.apple.com/testflight/", self.privacy)
        self.assertNotIn("Google Analytics", self.privacy)
        self.assertNotIn("<form", self.privacy)
        self.assertNotIn("<iframe", self.privacy)

    def test_support_page_is_actionable_and_linked(self) -> None:
        self.assertIn('href="support/">Support</a>', self.homepage)
        self.assertIn('href="../support/">Support</a>', self.documentation)
        self.assertIn('href="../support/">Support</a>', self.privacy)
        self.assertIn("Find your way", self.support)
        self.assertIn("Use the smallest reset", self.support)
        self.assertIn("Spaces own their data", self.support)
        self.assertIn("When one website behaves differently", self.support)
        self.assertIn("Review before importing", self.support)
        self.assertIn("https://www.reddit.com/r/CrestBrowser", self.support)
        self.assertNotIn("<form", self.support)
        self.assertNotIn("<iframe", self.support)

    def test_hero_uses_layered_space_crests_and_arc_continuation_copy(self) -> None:
        crest_assets = (
            "space-crest-work.svg",
            "space-crest-personal.svg",
            "space-crest-lion.svg",
            "space-crest-river.svg",
            "space-crest-meadow.svg",
            "space-crest-storm.svg",
            "space-crest-winter.svg",
        )
        for filename in crest_assets:
            with self.subTest(filename=filename):
                path = WEBSITE_ROOT / "assets" / filename
                self.assertTrue(path.is_file())
                element_tree.parse(path)
                self.assertIn(f"assets/{filename}", self.homepage)

        self.assertEqual(self.homepage.count('class="hero-standard '), 4)
        self.assertIn('<p class="hero-kicker">Crest</p>', self.homepage)
        self.assertIn("The browser for life after", self.homepage)
        self.assertIn("Created by an Arc diehard", self.homepage)
        self.assertNotIn("I&rsquo;m Paul", self.homepage)
        self.assertNotIn("I wanted", self.homepage)
        self.assertNotIn("I loved", self.homepage)
        self.assertNotIn("I wished", self.homepage)
        self.assertNotIn("I read", self.homepage)
        self.assertNotIn("tell me", self.homepage)
        self.assertIn("real separation between contexts", self.homepage)
        self.assertIn("Mac, iPad, and iPhone", self.homepage)
        self.assertIn(
            'class="hero-testflight-button" href="https://testflight.apple.com/join/vV1CM49Q" target="_blank" rel="noopener noreferrer"',
            self.homepage,
        )
        self.assertIn('<link rel="stylesheet" href="styles.css?v=20260812-homepage-responsive">', self.homepage)
        self.assertIn('src="assets/testflight-icon.webp" alt="" width="32" height="32"', self.homepage)
        self.assertIn("Join the beta", self.homepage)
        self.assertIn(".hero .hero-copy.reveal", self.styles)
        self.assertNotIn("See what carries forward", self.homepage)
        self.assertEqual(
            hashlib.sha256((WEBSITE_ROOT / "assets/testflight-icon.webp").read_bytes()).hexdigest(),
            "5d12bafc9a9e2166a1adf4ca60daa6d5ad083fe5c937bba87c13329f47b9403d",
        )
        self.assertNotIn("banner-glyph", self.homepage + self.styles)
        self.assertNotIn("Made for Apple silicon", self.homepage)
        self.assertNotIn("Built for Apple.", self.homepage)

        work_crest = (WEBSITE_ROOT / "assets/space-crest-work.svg").read_text()
        personal_crest = (WEBSITE_ROOT / "assets/space-crest-personal.svg").read_text()
        for color in ("#0d2034", "#37699e", "#bd8e27"):
            self.assertIn(color, work_crest)
        for color in ("#557b5d", "#b5a381", "#b83b2d"):
            self.assertIn(color, personal_crest)

    def test_homepage_is_a_full_product_story(self) -> None:
        for section_id in (
            'id="story"',
            'id="platforms"',
            'id="spaces"',
            'id="customization"',
            'id="migration"',
            'id="extensions"',
            'id="features"',
            'id="early-access"',
        ):
            with self.subTest(section_id=section_id):
                self.assertIn(section_id, self.homepage)

        for story in (
            "Why Crest exists",
            "What Arc got right",
            "What Crest changes",
            "Every Space is its own browser",
            "Make each Space easy to recognize",
            "Bring over the browser you already have",
            "Bring the extensions you use into the right Space",
            "Small conveniences that stay out of the way",
        ):
            with self.subTest(story=story):
                self.assertIn(story, self.homepage)

        self.assertGreaterEqual(self.homepage.count("<article"), 30)
        self.assertNotIn("<video", self.homepage)
        self.assertNotIn("<audio", self.homepage)
        self.assertFalse((REPOSITORY_ROOT / "videos/crest-product-overview").exists())

    def test_early_access_and_community_links_are_branded_and_safe(self) -> None:
        self.assertIn(
            'class="brand-action" href="https://testflight.apple.com/join/vV1CM49Q" target="_blank" rel="noopener noreferrer"',
            self.homepage,
        )
        self.assertIn(
            'class="brand-action" href="https://www.reddit.com/r/CrestBrowser" target="_blank" rel="noopener noreferrer"',
            self.homepage,
        )
        self.assertIn('src="assets/testflight-official.png" alt="TestFlight"', self.homepage)
        self.assertIn('src="assets/reddit-official.png" alt="Reddit"', self.homepage)
        self.assertEqual(
            self.png_size(WEBSITE_ROOT / "assets/testflight-official.png"),
            (400, 400),
        )
        self.assertEqual(
            self.png_size(WEBSITE_ROOT / "assets/reddit-official.png"),
            (400, 400),
        )
        self.assertEqual(
            hashlib.sha256((WEBSITE_ROOT / "assets/testflight-official.png").read_bytes()).hexdigest(),
            "e38bafb2becc325273e439e508766d1ba38186eef0acec0d8b26fa4da9f65f51",
        )
        self.assertEqual(
            hashlib.sha256((WEBSITE_ROOT / "assets/reddit-official.png").read_bytes()).hexdigest(),
            "5f1d20624382019ea8655d5716c0cb53bfc95981dfdac1e95d10892fd569f17c",
        )
        self.assertIn("View in TestFlight", self.homepage)
        self.assertIn("Visit Reddit", self.homepage)
        self.assertIn("Feedback · updates · community", self.homepage)
        self.assertEqual(self.homepage.count('class="service-button"'), 2)
        self.assertIn("border: 1px solid var(--gold)", self.styles)
        self.assertNotIn(".service-button-testflight", self.styles)
        self.assertNotIn(".service-button-reddit", self.styles)
        self.assertIn("section:target .reveal", self.styles)
        self.assertNotIn("#ff4500", self.styles.lower())
        self.assertNotIn('<svg class="brand-action-icon"', self.homepage)

    def test_spaces_use_an_interactive_cross_platform_showcase(self) -> None:
        self.assertIn("data-space-browser", self.homepage)
        self.assertIn('data-space-choice="work"', self.homepage)
        self.assertIn('data-space-choice="personal"', self.homepage)
        self.assertIn('class="space-browser-actions"', self.homepage)
        self.assertIn("assets/space-crest-work.svg", self.homepage)
        self.assertIn("assets/space-crest-personal.svg", self.homepage)
        self.assertIn("assets/crest-work-mac-2026.png", self.homepage)
        self.assertIn("assets/crest-personal-mac-clean.png", self.homepage)
        self.assertIn("assets/crest-work-iphone-2026.png", self.homepage)
        self.assertIn("assets/crest-personal-iphone.png", self.homepage)
        self.assertIn("data-space-title", self.homepage)
        self.assertIn("data-space-detail", self.homepage)

        work_mobile_showcase = re.search(
            r'<figure class="space-browser-picture active" data-space-image="work".*?</figure>',
            self.homepage,
            re.DOTALL,
        )
        self.assertIsNotNone(work_mobile_showcase)
        self.assertIn(
            'class="space-browser-mobile-shot" src="assets/crest-work-iphone-sidebar-2026.png"',
            work_mobile_showcase.group(0),
        )
        self.assertNotIn(
            'class="space-browser-mobile-shot" src="assets/crest-work-iphone-2026.png"',
            work_mobile_showcase.group(0),
        )

        for interaction in ("pointerdown", "pointerup", "wheel", "keydown"):
            with self.subTest(interaction=interaction):
                self.assertIn(interaction, self.script)

        compact_styles = self.styles.replace(" ", "").replace("\n", "")
        self.assertIn(".space-browser-screen{position:relative;aspect-ratio:8/5;", compact_styles)
        self.assertIn(".space-browser-mobile-shot", self.styles)
        self.assertIn(".space-choice-crest", self.styles)

    def test_published_screenshots_are_current_clean_captures(self) -> None:
        expected_sizes = {
            "crest-work-mac-2026.png": (1329, 768),
            "crest-work-ipad-2026.png": (2420, 1668),
            "crest-work-iphone-2026.png": (1206, 2622),
            "crest-work-iphone-sidebar-2026.png": (1206, 2622),
            "crest-spaces-mac-2026.png": (900, 660),
            "crest-spaces-ipad-2026.png": (2420, 1668),
            "crest-spaces-iphone-2026.png": (1206, 2622),
            "crest-localhost-mac-2026.png": (1329, 768),
            "crest-personal-mac-clean.png": (1440, 900),
            "crest-traditional-gradient-mac-clean.png": (1440, 900),
            "crest-import-browser-selection-mac-2026.png": (2340, 1622),
            "crest-import-space-review-mac-2026.png": (2350, 1632),
            "crest-quick-window-mac-2026.png": (720, 460),
            "crest-peek-mac-2026.png": (1329, 768),
        }
        for filename, size in expected_sizes.items():
            with self.subTest(filename=filename):
                path = WEBSITE_ROOT / "assets" / filename
                self.assertTrue(path.is_file())
                self.assertEqual(self.png_size(path), size)
                self.assertIn(f"assets/{filename}", self.homepage)

        published_pages = self.homepage + self.readme
        for stale_capture in (
            "crest-work-mac.jpg",
            "crest-personal-mac.jpg",
            "crest-traditional-gradient-mac.jpg",
            "crest-quick-window-mac.jpg",
            "crest-peek-mac.jpg",
            "crest-quick-window-mac-clean.png",
            "crest-peek-mac-clean.png",
        ):
            with self.subTest(stale_capture=stale_capture):
                self.assertNotIn(stale_capture, published_pages)

    def test_platform_story_portrays_each_device_directly(self) -> None:
        self.assertIn("Made for Apple devices", self.homepage)
        for platform, class_name in (
            ("Crest for Mac", "platform-mac"),
            ("Crest for iPad", "platform-ipad"),
            ("Crest for iPhone", "platform-iphone"),
        ):
            with self.subTest(platform=platform):
                self.assertIn(platform, self.homepage)
                self.assertIn(class_name, self.homepage)
        self.assertIn("object-fit: contain", self.styles)
        self.assertIn('class="platform-field"', self.homepage)
        self.assertIn("The whole Space", self.homepage)
        compact_styles = "".join(self.styles.split())
        self.assertIn(".platform-ipad{display:flex;flex-direction:column;}", compact_styles)
        self.assertIn(".platform-iphone{display:flex;flex-direction:column;", compact_styles)
        self.assertIn(".platform-shot-phoneimg{width:auto;height:auto;max-width:100%;max-height:540px;}", compact_styles)
        self.assertIn(".platform-field{position:relative;min-height:", compact_styles)
        self.assertIn("flex:1;", compact_styles)
        self.assertIn("Beside the page on larger screens", self.homepage)
        self.assertIn("ready when you need it on iPhone", self.homepage)
        self.assertIn("sidebar-mobile-sequence", self.homepage + self.styles)
        self.assertIn(".sidebar-wide-pair {", self.styles)
        self.assertIn("gap: .8rem; align-items: start", self.styles)
        self.assertIn(".sidebar-wide-pair img { width: 100%; height: auto; object-fit: contain", self.styles)
        self.assertIn("full sidebar opens as a dedicated view", self.documentation)

    def test_feature_callouts_focus_on_visible_product_behavior(self) -> None:
        for feature in (
            "Quick Window",
            "Peek",
            "Localhost mode",
            "Command palette",
            "Crest Passwords",
            "Reader mode",
        ):
            with self.subTest(feature=feature):
                self.assertIn(feature, self.homepage)
        self.assertIn("Tiny Arc", self.homepage)
        self.assertIn("links opened from other apps", self.homepage)
        self.assertIn("close it when you are done", self.homepage)
        self.assertIn("keep it by opening it as a full tab", self.homepage)
        self.assertIn("Arc's Tiny Arc", self.documentation)
        self.assertIn("automatic localhost developer toolbar", self.homepage)
        self.assertNotIn("Google results reflect", self.homepage)
        self.assertNotIn("Favicons follow the current URL", self.homepage)
        self.assertNotIn("feature-product-shot", self.homepage + self.styles)

    def test_extensions_story_is_product_facing_with_details_in_guides(self) -> None:
        detailed_guidance = self.documentation + self.extension_compatibility
        self.assertIn('id="extensions"', self.homepage)
        self.assertIn('href="#extensions">Extensions</a>', self.homepage)
        self.assertIn('id="extensions"', self.documentation)
        self.assertIn(
            "Crest can install most standards-based extensions from the Chrome Web Store",
            self.homepage,
        )
        for product_detail in (
            "compatibility can vary",
            "Each Space keeps its own extensions",
            "currently available in Crest for Mac",
            "Chrome Web Store",
            "Firefox Add-ons",
            "Safari apps",
            "Per-Space controls",
            "requested permissions and website access",
            "Read the guides",
        ):
            with self.subTest(product_detail=product_detail):
                self.assertIn(product_detail, self.homepage)

        for technical_detail in (
            "signed CRX3 packages",
            "Unpacked WebExtensions",
            "Signed-package audit",
            "added with limited compatibility",
            "BrowserSignatureInvalid",
            "allowed_origins",
            "nativeMessaging",
            "com.apple.developer.web-browser.public-key-credential",
            "Developer ID signing",
            "Gatekeeper validation",
        ):
            with self.subTest(technical_detail=technical_detail):
                self.assertNotIn(technical_detail, self.homepage)

        for preserved_detail in (
            "signed CRX3 packages",
            "Unpacked WebExtensions",
            "verified Chrome Web Store installations",
            "Crest for Mac",
            "allowed_origins",
            "little-endian framed JSON",
            "sendNativeMessage",
            "connectNative",
            "Safari content blockers",
            "legacy Safari App Extensions",
            "BrowserSignatureInvalid",
            "Developer ID signing",
            "Gatekeeper validation",
        ):
            with self.subTest(preserved_detail=preserved_detail):
                self.assertIn(preserved_detail, detailed_guidance)

        self.assertNotIn("all Chrome extensions work", self.homepage)
        self.assertNotIn("wBlock is supported", detailed_guidance)

    def test_help_center_is_reusable_searchable_and_published(self) -> None:
        config = (HELP_CENTER_ROOT / "docusaurus.config.js").read_text()
        sidebars = (HELP_CENTER_ROOT / "sidebars.js").read_text()
        search_plugin = (
            HELP_CENTER_ROOT / "plugins/help-search-index/index.js"
        ).read_text()
        search_component = (
            HELP_CENTER_ROOT / "src/components/HelpSearch/index.js"
        ).read_text()
        help_home = (HELP_CENTER_ROOT / "docs/index.mdx").read_text()

        self.assertIn("@docusaurus/core", (HELP_CENTER_ROOT / "package.json").read_text())
        self.assertIn("routeBasePath: '/'", config)
        self.assertIn("baseUrl: '/guides/'", config)
        self.assertIn("trailingSlash: true", config)
        self.assertIn("sitemap:", config)
        self.assertNotIn("versions:", config)
        self.assertIn("helpSidebar", sidebars)
        self.assertIn("Compatibility & troubleshooting", sidebars)
        self.assertIn("setGlobalData", search_plugin)
        self.assertIn("markdownFiles", search_plugin)
        self.assertIn("usePluginData('help-search-index')", search_component)
        self.assertIn('aria-live="polite"', search_component)
        self.assertIn("<HelpSearch />", help_home)
        self.assertTrue(
            (HELP_CENTER_ROOT / "src/components/GuideScreenshot/index.js").is_file()
        )
        self.assertTrue((HELP_CENTER_ROOT / "static/img/guides/README.md").is_file())

        expected_guides = {
            "extensions/install-chrome-web-store.md": "/install-chrome-web-store",
            "extensions/install-firefox-add-ons.md": "/install-firefox-add-ons",
            "extensions/scan-safari-web-extensions.md": "/scan-safari-web-extensions",
            "extensions/manage-permissions-site-access.md": "/manage-extension-permissions",
            "extensions/pin-and-use-popups.md": "/pin-extensions-and-popups",
            "extensions/keyboard-shortcuts.md": "/extension-keyboard-shortcuts",
            "extensions/status-and-technical-details.md": "/extension-status",
            "spaces/crest-passwords.md": "/crest-passwords-per-space",
            "extensions/compatibility.md": "/extension-compatibility",
            "extensions/native-companion-limits.md": "/native-companion-limits",
            "extensions/troubleshoot-partial-compatibility.md": "/troubleshoot-extension-compatibility",
            "extensions/onepassword.md": "/onepassword",
            "extensions/icloud-passwords.md": "/icloud-passwords",
        }
        for relative, slug in expected_guides.items():
            with self.subTest(guide=relative):
                source = (HELP_CENTER_ROOT / "docs" / relative).read_text()
                self.assertIn(f"slug: {slug}", source)
                self.assertIn("description:", source)
                self.assertIn("keywords:", source)
                output = WEBSITE_ROOT / "guides" / slug.strip("/") / "index.html"
                self.assertTrue(output.is_file())

        self.assertTrue((WEBSITE_ROOT / "guides/index.html").is_file())
        self.assertTrue((WEBSITE_ROOT / "guides/sitemap.xml").is_file())
        old_onepassword_route = WEBSITE_ROOT / "guides/onepassword-coming-soon/index.html"
        self.assertTrue(old_onepassword_route.is_file())
        self.assertIn("../onepassword/", old_onepassword_route.read_text())
        self.assertIn('href="guides/">Help &amp; guides</a>', self.homepage)
        self.assertIn('href="../guides/">Help &amp; guides</a>', self.documentation)
        self.assertIn('href="../guides/">Help &amp; guides</a>', self.privacy)
        self.assertIn('href="../guides/">Help &amp; guides</a>', self.support)
        self.assertIn(
            "Sitemap: https://crestbrowser.com/guides/sitemap.xml",
            (WEBSITE_ROOT / "robots.txt").read_text(),
        )

    def test_published_help_center_contains_no_build_machine_paths(self) -> None:
        machine_path_patterns = (
            re.compile(r"/Users/[^/]+/"),
            re.compile(r"/home/[^/]+/"),
            re.compile(r"[A-Za-z]:\\\\Users\\\\[^\\]+\\\\"),
        )

        for path in (WEBSITE_ROOT / "guides").rglob("*"):
            if not path.is_file() or path.suffix not in {
                ".css",
                ".html",
                ".js",
                ".json",
                ".map",
                ".xml",
            }:
                continue

            content = path.read_text(errors="ignore")
            for pattern in machine_path_patterns:
                with self.subTest(
                    path=path.relative_to(REPOSITORY_ROOT),
                    pattern=pattern.pattern,
                ):
                    self.assertIsNone(pattern.search(content))

    def test_help_center_navbar_blur_does_not_clip_the_mobile_flyout(self) -> None:
        navbar_rule = re.search(r"\.navbar\s*\{(?P<body>[^}]*)\}", self.help_styles)
        self.assertIsNotNone(navbar_rule)
        self.assertNotIn("backdrop-filter", navbar_rule.group("body"))

        navbar_inner_rule = re.search(
            r"\.navbar__inner\s*\{(?P<body>[^}]*)\}", self.help_styles
        )
        self.assertIsNotNone(navbar_inner_rule)
        self.assertIn("backdrop-filter: blur(18px)", navbar_inner_rule.group("body"))

    def test_help_center_preserves_verified_extension_boundaries(self) -> None:
        guide_sources = "\n".join(
            path.read_text()
            for path in sorted((HELP_CENTER_ROOT / "docs").rglob("*.md*"))
        )
        self.assertIn(
            "Install most standards-based Chrome extensions",
            guide_sources,
        )
        self.assertIn("Install most Firefox extensions", guide_sources)
        self.assertIn("Use it after installation", guide_sources)
        self.assertIn("Check for Updates Now", guide_sources)
        self.assertIn("reopen its Firefox Add-ons listing", guide_sources)
        self.assertIn("Compatibility varies where an extension depends on Chrome-only APIs", guide_sources)
        self.assertIn("Apple-managed capability", guide_sources)
        self.assertIn("Per-Space and per-device", guide_sources)
        self.assertIn("signed CRX3 packages", guide_sources)
        self.assertIn("Scan for Apps", guide_sources)
        self.assertIn("Load Unpacked", guide_sources)
        self.assertIn("Running", guide_sources)
        self.assertIn("Limited compatibility", guide_sources)
        self.assertIn("added with limited compatibility", guide_sources)
        self.assertIn("Needs attention", guide_sources)
        self.assertIn("Technical Details", guide_sources)
        self.assertIn("five Safari-only content-blocker extensions", guide_sources)
        self.assertIn("1Password for Mac 8.10.16 or later", guide_sources)
        self.assertIn("Add Browser", guide_sources)
        self.assertIn("Authorize", guide_sources)
        self.assertIn("/Applications/Crest.app", guide_sources)
        self.assertIn("my.1password.com", guide_sources)
        self.assertIn("1Password-BrowserSupport", guide_sources)
        self.assertIn("BrowserSignatureInvalid", guide_sources)
        self.assertIn("Developer ID signed pairing", guide_sources)
        self.assertIn("https://support.1password.com/additional-browsers/", guide_sources)
        self.assertIn("https://support.1password.com/code-signature/", guide_sources)
        self.assertIn("https://help.kagi.com/orion/browser-extensions/1password.html", guide_sources)
        self.assertIn("https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.developer.web-browser.public-key-credential", guide_sources)
        self.assertIn("Apple capability approval is pending", guide_sources)
        self.assertIn("Pairing, unlock, save, and autofill", guide_sources)
        self.assertIn("distributed through GitHub Releases", guide_sources)
        self.assertIn("Developer ID signs", guide_sources)
        self.assertIn("notarizes the app", guide_sources)
        self.assertIn("validates it with Gatekeeper", guide_sources)
        self.assertIn("signed Sparkle appcast", guide_sources)
        self.assertIn("Partial / experimental", guide_sources)
        self.assertIn("little-endian framed JSON", guide_sources)
        self.assertIn("official Mac release", guide_sources)
        self.assertIn("unpacked package has no verified Chrome Web Store identity", guide_sources)
        self.assertNotIn("all Chrome extensions work", guide_sources)
        self.assertNotIn("Coming soon", guide_sources)

    def test_migration_story_shows_the_real_mac_review_flow(self) -> None:
        self.assertIn('id="migration"', self.homepage)
        self.assertIn("Move in without starting over", self.homepage)
        self.assertIn("pull in open tabs", self.homepage)
        self.assertIn("supported passwords", self.homepage)
        self.assertIn("Nothing moves until it looks right", self.homepage)
        self.assertIn("Customize Space", self.homepage)
        self.assertIn("One Mac setup, every Apple device", self.homepage)
        self.assertIn("crest-import-browser-selection-mac-2026.png", self.homepage)
        self.assertIn("crest-import-space-review-mac-2026.png", self.homepage)
        for browser in ("Arc", "Zen", "Chrome", "Safari", "Firefox"):
            with self.subTest(browser=browser):
                self.assertIn(f"<strong>{browser}</strong>", self.homepage)

        self.assertIn('id="migration"', self.documentation)
        self.assertIn("direct browser migration happens in Crest for Mac", self.documentation)
        self.assertIn("Spaces and tabs can sync to iPad and iPhone", self.documentation)

    def test_homepage_calls_out_arc_inspiration_and_independence(self) -> None:
        self.assertIn("the parts of Arc worth carrying forward", self.homepage)
        self.assertIn("Arc diehard", self.homepage)
        self.assertIn("not affiliated with Arc", self.homepage)
        self.assertIn("real separation between contexts", self.homepage)
        for platform in ("Mac", "iPad", "iPhone"):
            with self.subTest(platform=platform):
                self.assertIn(platform, self.homepage)

    def test_public_site_stays_product_facing(self) -> None:
        public_pages = self.homepage + self.documentation
        self.assertNotIn("github.com", public_pages)
        self.assertNotIn("Site source", public_pages)

        for developer_content in (
            'id="architecture"',
            'id="build"',
            "CrestShared/",
            "Scripts/bootstrap.sh",
            "XcodeGen",
        ):
            with self.subTest(developer_content=developer_content):
                self.assertNotIn(developer_content, self.documentation)

        for user_section in (
            'id="spaces"',
            'id="tabs"',
            'id="quick-and-peek"',
            'id="migration"',
            'id="extensions"',
            'id="passwords"',
            'id="data"',
            'id="tools"',
            'id="platforms"',
        ):
            with self.subTest(user_section=user_section):
                self.assertIn(user_section, self.documentation)

    def test_customization_uses_current_cross_platform_controls(self) -> None:
        self.assertIn("Space Forge", self.homepage)
        self.assertIn("The same standard · across your Apple devices", self.homepage)
        self.assertNotIn("The same standard · everywhere", self.homepage)
        self.assertIn("Banner or Gradient", self.homepage)
        self.assertIn("Traditional Gradient", self.homepage)
        self.assertIn("familiar Arc-style option", self.homepage)
        self.assertIn("Not every Space needs a coat of arms", self.homepage)
        self.assertIn("assets/crest-traditional-gradient-mac-clean.png", self.homepage)
        self.assertIn("backplate", self.homepage)
        self.assertIn("divide the field", self.homepage)
        self.assertIn("ordinary", self.homepage)
        self.assertIn("trim", self.homepage)
        self.assertIn("charges", self.homepage)
        self.assertIn("Banner or Traditional Gradient", self.documentation)
        self.assertIn("familiar Arc-style theme", self.documentation)
        compact_styles = "".join(self.styles.split())
        self.assertIn(
            ".crest-anatomyarticle:nth-child(5){grid-column:4/span2;}",
            compact_styles,
        )
        self.assertIn(
            ".crest-anatomyarticle:nth-child(5){grid-column:1/-1;}",
            compact_styles,
        )
        for filename in (
            "crest-spaces-mac-2026.png",
            "crest-spaces-ipad-2026.png",
            "crest-spaces-iphone-2026.png",
        ):
            with self.subTest(filename=filename):
                self.assertIn(f"assets/{filename}", self.homepage)

    def test_customization_media_stays_inside_the_mobile_viewport(self) -> None:
        compact_styles = "".join(self.styles.split())
        self.assertIn("html,body{max-width:100%;overflow-x:hidden;}", compact_styles)
        self.assertIn("html,body{overflow-x:clip;}", compact_styles)
        self.assertIn(
            ".forge-grid{min-width:0;width:100%;max-width:100%;",
            compact_styles,
        )
        self.assertIn(
            ".forge-shot{min-width:0;width:100%;max-width:100%;",
            compact_styles,
        )
        self.assertIn(
            ".forge-traditional.forge-shotimg{height:auto;aspect-ratio:8/5;}",
            compact_styles,
        )


if __name__ == "__main__":
    unittest.main()
