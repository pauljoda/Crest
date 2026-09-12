#!/usr/bin/env python3
"""Published-site integrity, discovery, and user support contracts.

Editorial copy, CSS spellings, and obsolete layouts are deliberately not
snapshots. Rendering and interaction changes need browser validation.
"""

from __future__ import annotations

from html.parser import HTMLParser
import json
import pathlib
import re
import struct
import unittest
from urllib.parse import unquote, urljoin, urlsplit
import xml.etree.ElementTree as ET

REPOSITORY_ROOT = pathlib.Path(__file__).resolve().parents[2]
WEBSITE_ROOT = REPOSITORY_ROOT / "Website"
SITE_URL = "https://" + (WEBSITE_ROOT / "CNAME").read_text().strip() + "/"
PUBLIC_ROUTES = ("", "docs/", "privacy/", "support/")


class Page(HTMLParser):
    def __init__(self, path: pathlib.Path):
        super().__init__()
        self.elements = []
        self.source = path.read_text()
        self.feed(self.source)

    def handle_starttag(self, tag, attrs):
        self.elements.append((tag, dict(attrs)))

    def attributes(self, tag, **matching):
        return [attrs for name, attrs in self.elements if name == tag
                and all(attrs.get(key) == value for key, value in matching.items())]


class ProductSiteTests(unittest.TestCase):
    def test_public_pages_use_the_published_domain_for_discovery(self):
        for route in PUBLIC_ROUTES:
            with self.subTest(route=route):
                page = Page(WEBSITE_ROOT / route / "index.html")
                canonical = urljoin(SITE_URL, route)
                self.assertEqual(page.attributes("link", rel="canonical"),
                                 [{"rel": "canonical", "href": canonical}])
                self.assertEqual(page.attributes("meta", property="og:url")[0]["content"], canonical)
                self.assertTrue(page.attributes("meta", name="description")[0]["content"].strip())
                self.assertTrue(page.attributes("meta", property="og:image:alt")[0]["content"].strip())
                image = page.attributes("meta", property="og:image")[0]["content"]
                self.assertEqual(urlsplit(image).netloc, urlsplit(SITE_URL).netloc)
                self.assertTrue((WEBSITE_ROOT / unquote(urlsplit(image).path).lstrip("/")).is_file())
                blocks = re.findall(r'<script type="application/ld\+json">(.*?)</script>',
                                    page.source, re.DOTALL)
                self.assertTrue(blocks)
                for block in blocks:
                    data = json.loads(block)
                    for item in data.get("@graph", [data]):
                        self.assertTrue(item["@type"])
                        if "url" in item:
                            self.assertEqual(urlsplit(item["url"]).netloc, urlsplit(SITE_URL).netloc)

    def test_download_help_privacy_and_support_routes_are_reachable(self):
        page = Page(WEBSITE_ROOT / "index.html")
        links = {urljoin(SITE_URL, attrs["href"]) for attrs in page.attributes("a") if "href" in attrs}
        for route in ("guides/", "privacy/", "support/"):
            self.assertIn(urljoin(SITE_URL, route), links)
        self.assertIn("https://github.com/pauljoda/Crest/releases/latest", links)
        self.assertTrue(any(urlsplit(link).netloc == "apps.apple.com" for link in links))
        support = Page(WEBSITE_ROOT / "support/index.html")
        support_links = {attrs.get("href") for attrs in support.attributes("a")}
        self.assertTrue({
            "https://www.reddit.com/r/CrestBrowser",
            "https://github.com/pauljoda/Crest/issues/new/choose",
            "https://github.com/pauljoda/Crest/security/advisories/new",
        }.issubset(support_links))

    def test_published_html_links_and_assets_resolve_locally(self):
        pages = {path: Page(path) for path in WEBSITE_ROOT.rglob("*.html")}
        self.assertTrue(pages)
        for path, page in pages.items():
            base = urljoin(SITE_URL, path.relative_to(WEBSITE_ROOT).as_posix())
            for tag, attrs in page.elements:
                for attribute in ("href", "src", "poster"):
                    reference = attrs.get(attribute)
                    if not reference:
                        continue
                    url = urlsplit(urljoin(base, reference))
                    if url.scheme not in ("http", "https") or url.netloc != urlsplit(SITE_URL).netloc:
                        continue
                    target = WEBSITE_ROOT / unquote(url.path).lstrip("/")
                    if target.is_dir():
                        target /= "index.html"
                    with self.subTest(page=str(path.relative_to(WEBSITE_ROOT)), link=reference):
                        self.assertTrue(target.is_file(), f"Missing published target: {target}")
                        if url.fragment and target in pages:
                            identifiers = {a.get("id") for _, a in pages[target].elements}
                            identifiers.update(a.get("name") for a in pages[target].attributes("a"))
                            self.assertIn(unquote(url.fragment), identifiers)

    def test_manifest_icons_have_their_declared_dimensions_and_valid_start_route(self):
        manifest = json.loads((WEBSITE_ROOT / "site.webmanifest").read_text())
        self.assertTrue(manifest["name"])
        self.assertTrue(manifest["icons"])
        for icon in manifest["icons"]:
            data = (WEBSITE_ROOT / icon["src"]).read_bytes()
            self.assertEqual(data[:8], b"\x89PNG\r\n\x1a\n")
            self.assertEqual(data[12:16], b"IHDR")
            width, height = struct.unpack(">II", data[16:24])
            self.assertEqual(icon["sizes"], f"{width}x{height}")
        start = urlsplit(urljoin(SITE_URL, manifest["start_url"]))
        self.assertEqual(start.netloc, urlsplit(SITE_URL).netloc)
        self.assertTrue((WEBSITE_ROOT / start.path.lstrip("/") / "index.html").is_file())

    def test_sitemaps_publish_existing_routes_on_the_public_domain(self):
        robots = (WEBSITE_ROOT / "robots.txt").read_text()
        for sitemap in ("sitemap.xml", "guides/sitemap.xml"):
            self.assertIn(f"Sitemap: {urljoin(SITE_URL, sitemap)}", robots)
            root = ET.parse(WEBSITE_ROOT / sitemap).getroot()
            locations = [entry.text for entry in root.findall(".//{*}loc")]
            self.assertTrue(locations)
            for location in locations:
                with self.subTest(url=location):
                    url = urlsplit(location)
                    self.assertEqual(url.netloc, urlsplit(SITE_URL).netloc)
                    self.assertTrue((WEBSITE_ROOT / url.path.lstrip("/") / "index.html").is_file())

    def test_every_authored_guide_is_published_and_legacy_redirect_survives(self):
        sources = list((REPOSITORY_ROOT / "HelpCenter/docs").rglob("*.md*"))
        self.assertTrue(sources)
        for source in sources:
            slug = re.search(r"^slug:\s*(\S+)", source.read_text(), re.MULTILINE)
            with self.subTest(guide=source.name):
                self.assertIsNotNone(slug)
                self.assertTrue((WEBSITE_ROOT / "guides" / slug[1].lstrip("/") / "index.html").is_file())
        redirect = Page(WEBSITE_ROOT / "guides/onepassword-coming-soon/index.html")
        self.assertIn("onepassword/", redirect.attributes("meta", **{"http-equiv": "refresh"})[0]["content"])

    def test_published_help_center_contains_no_build_machine_paths(self):
        patterns = (re.compile(r"/Users/[^/]+/"), re.compile(r"/home/[^/]+/"),
                    re.compile(r"[A-Za-z]:\\\\Users\\\\[^\\]+\\\\"))
        for path in (WEBSITE_ROOT / "guides").rglob("*"):
            if path.is_file() and path.suffix in {".css", ".html", ".js", ".json", ".map", ".xml"}:
                source = path.read_text(errors="ignore")
                for pattern in patterns:
                    with self.subTest(path=str(path.relative_to(WEBSITE_ROOT))):
                        self.assertIsNone(pattern.search(source))


if __name__ == "__main__":
    unittest.main()
