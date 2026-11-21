#!/usr/bin/env python3
"""Build the product site's credits page from `Documentation/Credits.json`.

Writes `Website/credits/`, which is generated at deploy time and never committed:

- `index.html`: the developer, the community, the code contributors GitHub
  lists, any other roles, and the supporters by tier.
- `credits.json`: the same people, for Crest itself.
- `images/`: each contributor's avatar and each link's site icon, so the page
  loads nothing from other sites.

Code contributors come from GitHub's contributor list for the repository,
without bots; `GITHUB_TOKEN` raises the rate limit.

Supporters come from the file and, when `PATREON_ACCESS_TOKEN` holds the
campaign's creator access token, from its active patrons, each at the highest
tier their pledge reaches and marked as Patreon's, by their first names and the
initial of their last. A file entry whose `patreon` holds a patron's member ID,
or whose name is theirs, gives them its spelling and link; one that holds a
member ID, or is marked `"source": "patreon"`, drops out once that patron is no
longer active. Member IDs keep patrons' Patreon names out of the file. Ko-fi offers no list, so its
supporters are file entries marked `"source": "ko-fi"`. Anyone named in
`hidden` never appears, from either source. When Patreon cannot be reached, the
page lists what the file holds.
"""

from __future__ import annotations

import argparse
from dataclasses import dataclass
import html
import json
import os
import pathlib
import shutil
import sys
from typing import Callable, Optional
import urllib.error
import urllib.parse
import urllib.request

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from site_page import FOOTER, banner, head_html, header_html, icon  # noqa: E402


CREDITS_PATH = pathlib.PurePosixPath("Documentation/Credits.json")
STYLESHEET = "/assets/credits.css?v=20261121-credits-2"
PAGE_PATH = "/credits/"
USER_AGENT = "crestbrowser.com credits"
TIMEOUT = 20
PATREON_API = "https://www.patreon.com/api/oauth2/v2"

# Each tier, by its place from the top, wears one of the brand colors.
TIER_COLORS = ("var(--coral)", "var(--sky)", "var(--sage)")


# MARK: - Types


@dataclass(frozen=True)
class Link:
    url: str

    @property
    def host_with_prefix(self) -> str:
        return urllib.parse.urlsplit(self.url).hostname or ""

    @property
    def host(self) -> str:
        return self.host_with_prefix.removeprefix("www.")

    @staticmethod
    def read(value: object) -> Optional["Link"]:
        """The web address `value` spells, given a scheme when it has none, or
        nil when it is not a web address."""
        if not isinstance(value, str) or not value.strip():
            return None
        text = value.strip()
        if "://" not in text:
            text = f"https://{text}"
        parts = urllib.parse.urlsplit(text)
        if parts.scheme not in ("http", "https") or not parts.hostname:
            return None
        return Link(text)


@dataclass(frozen=True)
class Person:
    name: str
    links: tuple[Link, ...] = ()

    @staticmethod
    def read(value: dict) -> Optional["Person"]:
        name = str(value.get("name", "")).strip()
        if not name:
            return None
        links = tuple(link for link in map(Link.read, value.get("links", [])) if link)
        return Person(name, links)


@dataclass(frozen=True)
class Role:
    title: str
    symbol: str
    people: tuple[Person, ...]


@dataclass(frozen=True)
class Contributor:
    login: str
    url: str
    avatar_url: str


@dataclass(frozen=True)
class Tier:
    id: str
    title: str
    monthly: int
    shows_links: bool
    color: str


@dataclass(frozen=True)
class Source:
    """A service supporters give through, in its own colors and mark."""

    id: str
    title: str
    color: str
    ink: str
    mark: str
    url: str

    def logo(self, css_class: str) -> str:
        return f'<svg class="{css_class}" viewBox="0 0 24 24" fill="currentColor" aria-hidden="true"><path d="{self.mark}"/></svg>'


@dataclass(frozen=True)
class Supporter:
    name: str
    tier: str
    link: Optional[Link] = None
    source: Optional[Source] = None


@dataclass(frozen=True)
class Patron:
    """An active patron as Patreon lists them: their membership's identity,
    their name and the monthly amount of the highest tier they are entitled
    to, in cents."""

    id: str
    name: str
    amount_cents: int


# MARK: - Icons


ICONS = {
    "people": icon('<circle cx="9" cy="8.5" r="3.2"/><path d="M3.5 19c.6-3.2 2.8-5 5.5-5s4.9 1.8 5.5 5"/><circle cx="17" cy="9.5" r="2.4"/><path d="M15.8 14.2c2.3.1 4 1.6 4.7 4.3"/>'),
    "code": icon('<path d="M8.5 7.5L4 12l4.5 4.5M15.5 7.5L20 12l-4.5 4.5M13.4 5l-2.8 14"/>'),
    "heart": icon('<path d="M12 20s-7.5-4.4-7.5-10A4.3 4.3 0 0 1 12 7.4 4.3 4.3 0 0 1 19.5 10C19.5 15.6 12 20 12 20z"/>'),
    "design": icon('<path d="M4 20l4.2-1 10.4-10.4a2.1 2.1 0 0 0-3-3L5.2 16z"/><path d="M14 7l3 3"/>'),
    "translation": icon('<path d="M4 6h8M8 4v2c0 4-2 7-4.5 8.5M6 10c1.2 2 3 3.4 5 4"/><path d="M13 20l3.5-8 3.5 8M14.2 17.4h4.6"/>'),
    "testing": icon('<path d="M12 3l7 3v5.5c0 4.3-3 7.9-7 9.5-4-1.6-7-5.2-7-9.5V6z"/><path d="M9 12l2.2 2.2L15.5 10"/>'),
    "docs": icon('<path d="M5 4.5h9.5L19 9v10.5H5z"/><path d="M14.5 4.5V9H19M8.5 13h7M8.5 16.5h5"/>'),
    "sparkles": icon('<path d="M10 3.5l1.6 4.6 4.6 1.6-4.6 1.6L10 15.9l-1.6-4.6-4.6-1.6 4.6-1.6z"/><path d="M18 14l.8 2.2 2.2.8-2.2.8L18 20l-.8-2.2-2.2-.8 2.2-.8z"/>'),
    "globe": icon('<circle cx="12" cy="12" r="8.5"/><path d="M3.5 12h17M12 3.5c2.4 2.4 3.4 5.3 3.4 8.5s-1 6.1-3.4 8.5c-2.4-2.4-3.4-5.3-3.4-8.5s1-6.1 3.4-8.5z"/>'),
    "arrow-up-right": icon('<path d="M7 17L17 7M9 7h8v8"/>'),
}

ROLE_SYMBOLS = ("design", "translation", "testing", "docs", "sparkles")

# The services supporters give through, with the marks and colors each asks
# for (Simple Icons, from their brand pages), in the order their buttons stand.
SOURCES = {
    source.id: source
    for source in (
        Source("ko-fi", "Ko-fi", "#FF6433", "#FFFFFF", "M11.351 2.715c-2.7 0-4.986.025-6.83.26C2.078 3.285 0 5.154 0 8.61c0 3.506.182 6.13 1.585 8.493 1.584 2.701 4.233 4.182 7.662 4.182h.83c4.209 0 6.494-2.234 7.637-4a9.5 9.5 0 0 0 1.091-2.338C21.792 14.688 24 12.22 24 9.208v-.415c0-3.247-2.13-5.507-5.792-5.87-1.558-.156-2.65-.208-6.857-.208m0 1.947c4.208 0 5.09.052 6.571.182 2.624.311 4.13 1.584 4.13 4v.39c0 2.156-1.792 3.844-3.87 3.844h-.935l-.156.649c-.208 1.013-.597 1.818-1.039 2.546-.909 1.428-2.545 3.064-5.922 3.064h-.805c-2.571 0-4.831-.883-6.078-3.195-1.09-2-1.298-4.155-1.298-7.506 0-2.181.857-3.402 3.012-3.714 1.533-.233 3.559-.26 6.39-.26m6.547 2.287c-.416 0-.65.234-.65.546v2.935c0 .311.234.545.65.545 1.324 0 2.051-.754 2.051-2s-.727-2.026-2.052-2.026m-10.39.182c-1.818 0-3.013 1.48-3.013 3.142 0 1.533.858 2.857 1.949 3.897.727.701 1.87 1.429 2.649 1.896a1.47 1.47 0 0 0 1.507 0c.78-.467 1.922-1.195 2.623-1.896 1.117-1.039 1.974-2.364 1.974-3.897 0-1.662-1.247-3.142-3.039-3.142-1.065 0-1.792.545-2.338 1.298-.493-.753-1.246-1.298-2.312-1.298", "https://ko-fi.com/pauljoda/tiers"),
        Source("patreon", "Patreon", "#000000", "#FFFFFF", "M22.957 7.21c-.004-3.064-2.391-5.576-5.191-6.482-3.478-1.125-8.064-.962-11.384.604C2.357 3.231 1.093 7.391 1.046 11.54c-.039 3.411.302 12.396 5.369 12.46 3.765.047 4.326-4.804 6.068-7.141 1.24-1.662 2.836-2.132 4.801-2.618 3.376-.836 5.678-3.501 5.673-7.031Z", "https://www.patreon.com/CrestBrowser"),
    )
}


# MARK: - Fetching


def fetch(url: str, *, token: Optional[str] = None, accept: str = "application/json") -> Optional[bytes]:
    """The body at `url`, or nil when it cannot be fetched."""
    request = urllib.request.Request(url, headers={"User-Agent": USER_AGENT, "Accept": accept})
    if token:
        request.add_header("Authorization", f"Bearer {token}")
    try:
        with urllib.request.urlopen(request, timeout=TIMEOUT) as response:
            return response.read()
    except (urllib.error.URLError, TimeoutError, OSError) as error:
        print(f"warning: could not fetch {url.split('?')[0]}: {error}", file=sys.stderr)
        return None


def fetch_json(url: str, *, token: Optional[str] = None) -> Optional[object]:
    body = fetch(url, token=token)
    if body is None:
        return None
    try:
        return json.loads(body)
    except json.JSONDecodeError:
        print(f"warning: {url.split('?')[0]} did not answer with JSON", file=sys.stderr)
        return None


def github_contributors(repository: str, exclude: set[str], token: Optional[str]) -> Optional[list[Contributor]]:
    """The people GitHub lists as the repository's contributors, most
    contributions first, without bots or the logins in `exclude`; nil when
    GitHub cannot be reached."""
    contributors: list[Contributor] = []
    for page in range(1, 11):
        listed = fetch_json(
            f"https://api.github.com/repos/{repository}/contributors?per_page=100&page={page}", token=token
        )
        if not isinstance(listed, list):
            return contributors or None
        for item in listed:
            login = str(item.get("login", ""))
            if not login or item.get("type") != "User" or login.casefold() in exclude:
                continue
            contributors.append(
                Contributor(login, str(item.get("html_url", "")), str(item.get("avatar_url", "")))
            )
        if len(listed) < 100:
            break
    return contributors


def patreon_patrons(token: str) -> Optional[list[Patron]]:
    """The campaign's active patrons, each with the monthly amount of the
    highest tier they are entitled to; nil when Patreon cannot be reached."""
    campaigns = fetch_json(f"{PATREON_API}/campaigns", token=token)
    if not isinstance(campaigns, dict) or not campaigns.get("data"):
        return None
    campaign = campaigns["data"][0]["id"]
    query = urllib.parse.urlencode({
        "include": "currently_entitled_tiers",
        "fields[member]": "full_name,patron_status",
        "fields[tier]": "title,amount_cents",
        "page[count]": "500",
    })
    url: Optional[str] = f"{PATREON_API}/campaigns/{campaign}/members?{query}"
    patrons: list[Patron] = []
    while url:
        page = fetch_json(url, token=token)
        if not isinstance(page, dict):
            return None
        patrons.extend(patrons_on_page(page))
        url = page.get("links", {}).get("next")
    return patrons


def patrons_on_page(page: dict) -> list[Patron]:
    """The active patrons one page of Patreon's member list holds."""
    amounts = {
        tier["id"]: int(tier.get("attributes", {}).get("amount_cents") or 0)
        for tier in page.get("included", [])
        if tier.get("type") == "tier"
    }
    patrons = []
    for member in page.get("data", []):
        attributes = member.get("attributes", {})
        name = str(attributes.get("full_name") or "").strip()
        if attributes.get("patron_status") != "active_patron" or not name:
            continue
        entitled = member.get("relationships", {}).get("currently_entitled_tiers", {}).get("data", [])
        amount = max((amounts.get(tier["id"], 0) for tier in entitled), default=0)
        patrons.append(Patron(str(member.get("id", "")), name, amount))
    return patrons


# MARK: - Supporters


def read_tiers(document: dict) -> list[Tier]:
    """The supporter tiers, from the top."""
    tiers = sorted(document.get("tiers", []), key=lambda tier: -int(tier["monthly"]))
    return [
        Tier(
            str(tier["id"]),
            str(tier["title"]),
            int(tier["monthly"]),
            bool(tier.get("showsLinks", False)),
            TIER_COLORS[min(index, len(TIER_COLORS) - 1)],
        )
        for index, tier in enumerate(tiers)
    ]


def tier_for(amount_cents: int, tiers: list[Tier]) -> Optional[Tier]:
    """The highest tier a monthly pledge of `amount_cents` reaches, or nil
    below the lowest."""
    return next((tier for tier in tiers if amount_cents >= tier.monthly * 100), None)


def short_name(full_name: str) -> str:
    """A patron's name as the page shows it: their first names and the initial
    of their last, as "Chris F"."""
    words = full_name.split()
    if len(words) < 2:
        return full_name
    return f"{' '.join(words[:-1])} {words[-1][0].upper()}"


def resolve_supporters(
    document: dict, tiers: list[Tier], patrons: Optional[list[Patron]]
) -> dict[str, list[Supporter]]:
    """Each tier's supporters, by name, without anyone `hidden` names by the
    name the page shows, their Patreon name or their member ID. With
    Patreon's active `patrons`, each is listed at the tier their pledge
    reaches, with the spelling and link of the file entry that stands for
    them, and file entries for patrons who are no longer active drop out; without them, nil when Patreon
    was not reached, the file is listed as it stands. Only a tier that shows
    links keeps a supporter's link."""
    tier_ids = {tier.id: tier for tier in tiers}
    hidden = {str(name).strip().casefold() for name in document.get("hidden", [])}
    # Each file entry, by the Patreon member ID it stands for, or its name.
    entries: dict[str, Supporter] = {}
    for entry in document.get("people", []):
        name = str(entry.get("name", "")).strip()
        member = str(entry.get("patreon", "")).strip()
        if name and entry.get("tier") in tier_ids:
            source = SOURCES["patreon"] if member else SOURCES.get(entry.get("source"))
            entries.setdefault(
                (member or name).casefold(),
                Supporter(name, str(entry["tier"]), Link.read(entry.get("link")), source),
            )
    supporters: list[Supporter] = []
    if patrons is None:
        supporters = [entry for key, entry in entries.items() if key not in hidden]
    else:
        # Each listed patron by member ID, so two patrons with one name stay
        # two, and each file entry a patron took or a hidden patron stands for.
        listed: dict[str, Supporter] = {}
        claimed: set[str] = set()
        for patron in patrons:
            member, key = patron.id.casefold(), patron.name.casefold()
            if member in hidden or key in hidden:
                claimed.update((member, key))
                continue
            tier = tier_for(patron.amount_cents, tiers)
            if not tier or member in listed:
                continue
            found = member if member in entries else key
            entry = entries.get(found) if found not in claimed else None
            claimed.add(found)
            listed[member] = Supporter(
                entry.name if entry else short_name(patron.name),
                tier.id,
                entry.link if entry else None,
                SOURCES["patreon"],
            )
        supporters = list(listed.values()) + [
            entry
            for key, entry in entries.items()
            if key not in claimed and key not in hidden and entry.source is not SOURCES["patreon"]
        ]
    by_tier: dict[str, list[Supporter]] = {tier.id: [] for tier in tiers}
    for supporter in supporters:
        if supporter.name.casefold() in hidden:
            continue
        link = supporter.link if tier_ids[supporter.tier].shows_links else None
        by_tier[supporter.tier].append(Supporter(supporter.name, supporter.tier, link, supporter.source))
    for people in by_tier.values():
        people.sort(key=lambda supporter: supporter.name.casefold())
    return by_tier


# MARK: - Images


class Images:
    """The images the page shows, saved beside it: avatars and site icons.
    Each is fetched once; one that cannot be fetched is left out."""

    def __init__(self, directory: pathlib.Path, fetcher: Callable[[str], Optional[bytes]]):
        self.directory = directory
        self.fetcher = fetcher
        self.saved: dict[str, Optional[str]] = {}

    def save(self, key: str, urls: list[str], name: str) -> Optional[str]:
        """Saves the first of `urls` that answers with an image, under `name`
        and the extension its format takes, once per `key`."""
        if key not in self.saved:
            body = next((found for found in map(self.fetcher, urls) if found and image_extension(found)), None)
            if body:
                filename = f"{name}.{image_extension(body)}"
                self.directory.mkdir(parents=True, exist_ok=True)
                (self.directory / filename).write_bytes(body)
                self.saved[key] = f"{PAGE_PATH}images/{filename}"
            else:
                self.saved[key] = None
        return self.saved[key]

    def avatar(self, login: str, url: str) -> Optional[str]:
        if not url:
            return None
        separator = "&" if "?" in url else "?"
        return self.save(f"avatar:{login}", [f"{url}{separator}s=160"], f"avatar-{safe_name(login)}")

    def site_icon(self, link: Link) -> Optional[str]:
        host = link.host
        if not host:
            return None
        return self.save(
            f"icon:{host}",
            [f"https://icons.duckduckgo.com/ip3/{host}.ico", f"https://{link.host_with_prefix}/favicon.ico"],
            f"icon-{safe_name(host)}",
        )


IMAGE_SIGNATURES = (
    (b"\x89PNG\r\n\x1a\n", "png"),
    (b"\xff\xd8\xff", "jpg"),
    (b"GIF8", "gif"),
    (b"\x00\x00\x01\x00", "ico"),
    (b"<svg", "svg"),
)


def image_extension(body: bytes) -> Optional[str]:
    """The extension of the image format `body` holds, or nil when it holds
    none the page shows, such as an error page."""
    if body[:4] == b"RIFF" and body[8:12] == b"WEBP":
        return "webp"
    return next((extension for signature, extension in IMAGE_SIGNATURES if body.startswith(signature)), None)


def safe_name(text: str) -> str:
    return "".join(character if character.isalnum() or character in "-." else "-" for character in text.lower())


# MARK: - Page


def attribute(text: str) -> str:
    return html.escape(text, quote=True)


def link_icon(link: Link, images: Images) -> str:
    source = images.site_icon(link)
    if source:
        return f'<img src="{attribute(source)}" alt="" width="20" height="20" loading="lazy">'
    return ICONS["globe"]


def links_html(links: tuple[Link, ...], images: Images, owner: str) -> str:
    if not links:
        return ""
    items = "".join(
        f'<a class="cr-link" href="{attribute(link.url)}" rel="noopener" title="{attribute(link.host)}">'
        f'{link_icon(link, images)}<span class="cr-hidden">{html.escape(owner)} on {html.escape(link.host)}</span></a>'
        for link in links
    )
    return f'<span class="cr-links">{items}</span>'


def section_header(title: str, symbol: str, color: str, extra: str = "") -> str:
    return (
        f'<header class="cr-section-head"><span class="cr-icon" style="--cr-color: {color}">{ICONS[symbol]}</span>'
        f"<h2>{html.escape(title)}</h2>{extra}</header>"
    )


def person_html(person: Person, images: Images) -> str:
    return (
        f'<li class="cr-person"><strong>{html.escape(person.name)}</strong>'
        f"{links_html(person.links, images, person.name)}</li>"
    )


def people_section(section_id: str, title: str, symbol: str, color: str, people: tuple[Person, ...], images: Images) -> str:
    """A section of people, or nothing while it has none."""
    if not people:
        return ""
    items = "".join(person_html(person, images) for person in people)
    return (
        f'<section class="cr-section" id="{section_id}">{section_header(title, symbol, color)}'
        f'<ul class="cr-people">{items}</ul></section>'
    )


def developer_html(developer: dict, images: Images) -> str:
    name = str(developer.get("name", ""))
    github = str(developer.get("github", ""))
    avatar = images.avatar(github, f"https://avatars.githubusercontent.com/{github}") if github else None
    picture = (
        f'<img class="cr-avatar" src="{attribute(avatar)}" alt="" width="112" height="112">'
        if avatar else f'<span class="cr-avatar cr-avatar-empty">{html.escape(name[:1])}</span>'
    )
    links = tuple(link for link in map(Link.read, developer.get("links", [])) if link)
    return (
        f'<article class="cr-developer" id="developer">{picture}<div class="cr-developer-text">'
        f"<h2>{html.escape(name)}</h2><p>{html.escape(str(developer.get('role', '')))}</p>"
        f"{links_html(links, images, name)}</div></article>"
    )


def contributors_html(contributors: Optional[list[Contributor]], repository: str, images: Images) -> str:
    graph = f"https://github.com/{repository}/graphs/contributors"
    more = (
        f'<a class="cr-more" href="{graph}" rel="noopener">GitHub<span class="cr-more-icon">'
        f'{ICONS["arrow-up-right"]}</span></a>'
    )
    if contributors:
        items = []
        for contributor in contributors:
            avatar = images.avatar(contributor.login, contributor.avatar_url)
            picture = (
                f'<img src="{attribute(avatar)}" alt="" width="56" height="56" loading="lazy">'
                if avatar else f'<span class="cr-avatar-empty">{html.escape(contributor.login[:1].upper())}</span>'
            )
            items.append(
                f'<li><a class="cr-contributor" href="{attribute(contributor.url)}" rel="noopener">'
                f"{picture}<span>{html.escape(contributor.login)}</span></a></li>"
            )
        body = f'<ul class="cr-contributors">{"".join(items)}</ul>'
    else:
        body = ""
    return (
        f'<section class="cr-section" id="contributors">'
        f'{section_header("Code contributors", "code", "var(--sky)", more)}{body}</section>'
    )


def supporters_html(tiers: list[Tier], by_tier: dict[str, list[Supporter]], images: Images) -> str:
    blocks = []
    for index, tier in enumerate(tiers):
        people = by_tier.get(tier.id, [])
        if not people:
            continue
        size = ("cr-tier-top", "cr-tier-middle", "cr-tier-base")[min(index, 2)]
        items = []
        for supporter in people:
            link = ""
            if supporter.link:
                link = (
                    f'<a class="cr-supporter-link" href="{attribute(supporter.link.url)}" rel="noopener">'
                    f'{link_icon(supporter.link, images)}<span>{html.escape(supporter.link.host)}</span></a>'
                )
            mark = ""
            if supporter.source:
                source = supporter.source
                mark = (
                    f'<span class="cr-source" style="--cr-brand: {source.color}" title="{source.title}">'
                    f'{source.logo("cr-source-mark")}<span class="cr-hidden">on {source.title}</span></span>'
                )
            items.append(f'<li class="cr-supporter">{mark}<strong>{html.escape(supporter.name)}</strong>{link}</li>')
        blocks.append(
            f'<div class="cr-tier {size}" style="--cr-color: {tier.color}">'
            f'<header class="cr-tier-head">{banner(tier.color, "cr-banner")}<h3>{html.escape(tier.title)}</h3>'
            f'<span>${tier.monthly}/month</span></header><ul>{"".join(items)}</ul></div>'
        )
    return f"""<section class="cr-supporters stack-butter" id="supporters">
      <div class="cr-supporters-inner">
        {section_header("Supporters", "heart", "var(--paper)")}
        {"".join(blocks)}
        <footer class="cr-support">
          {"".join(brand_button(source) for source in SOURCES.values())}
          <p>Listed by your Ko-fi or Patreon name. Ask there to add a link, change your listing or hide it.</p>
        </footer>
      </div>
    </section>"""


def brand_button(source: Source) -> str:
    return (
        f'<a class="cr-brand-button" style="--cr-brand: {source.color}; --cr-brand-ink: {source.ink}" '
        f'href="{source.url}" rel="noopener">{source.logo("cr-brand-mark")}{source.title}</a>'
    )


def page_html(document: dict, contributors: Optional[list[Contributor]], by_tier: dict[str, list[Supporter]], tiers: list[Tier], images: Images) -> str:
    community = tuple(person for person in map(Person.read, document.get("community", [])) if person)
    roles = read_roles(document)
    repository = str(document.get("contributors", {}).get("repository", "pauljoda/Crest"))
    role_sections = "".join(
        people_section(f"role-{index}", role.title, role.symbol, "var(--coral)", role.people, images)
        for index, role in enumerate(roles)
    )
    return (
        head_html(
            "Crest Credits",
            "The people who build Crest, help its community, contribute its code and support its work.",
            PAGE_PATH,
            stylesheet=STYLESHEET,
            json_path=f"{PAGE_PATH}credits.json",
        )
        + "\n"
        + header_html(body_class="cr-page", main_id="credits", skip_label="Skip to credits")
        + f"""
  <main id="credits" class="cr">
    <section class="cr-head stack-slate">
      <div class="cr-head-inner"><h1>Credits</h1></div>
    </section>
    <div class="cr-body">
      {developer_html(document.get("developer", {}), images)}
      {people_section("community", "Community support", "people", "var(--sage)", community, images)}
      {contributors_html(contributors, repository, images)}
      {role_sections}
    </div>
    {supporters_html(tiers, by_tier, images)}
  </main>
"""
        + FOOTER
    )


def read_roles(document: dict) -> list[Role]:
    roles = []
    for role in document.get("roles", []):
        title = str(role.get("title", "")).strip()
        if not title:
            continue
        symbol = str(role.get("icon", "sparkles"))
        people = tuple(person for person in map(Person.read, role.get("people", [])) if person)
        roles.append(Role(title, symbol if symbol in ROLE_SYMBOLS else "sparkles", people))
    return roles


def credits_document(document: dict, contributors: Optional[list[Contributor]], by_tier: dict[str, list[Supporter]], tiers: list[Tier]) -> dict:
    def person(value: Person) -> dict:
        return {"name": value.name, "links": [link.url for link in value.links]}

    developer = document.get("developer", {})
    return {
        "developer": {
            "name": developer.get("name"),
            "role": developer.get("role"),
            "links": [link.url for link in map(Link.read, developer.get("links", [])) if link],
        },
        "community": [person(value) for value in map(Person.read, document.get("community", [])) if value],
        "contributors": [{"login": value.login, "url": value.url} for value in contributors or []],
        "roles": [
            {"title": role.title, "people": [person(value) for value in role.people]}
            for role in read_roles(document)
            if role.people
        ],
        "supporters": [
            {
                "tier": tier.id,
                "title": tier.title,
                "monthly": tier.monthly,
                "people": [
                    {
                        "name": supporter.name,
                        **({"link": supporter.link.url} if supporter.link else {}),
                        **({"source": supporter.source.id} if supporter.source else {}),
                    }
                    for supporter in by_tier.get(tier.id, [])
                ],
            }
            for tier in tiers
        ],
    }


# MARK: - Writing


def build(
    repository_root: pathlib.Path,
    output: pathlib.Path,
    *,
    contributors: Optional[list[Contributor]],
    patrons: Optional[list[Patron]],
    fetcher: Callable[[str], Optional[bytes]],
) -> dict[str, list[Supporter]]:
    document = json.loads((repository_root / CREDITS_PATH).read_text(encoding="utf-8"))
    supporters = document.get("supporters", {})
    tiers = read_tiers(supporters)
    by_tier = resolve_supporters(supporters, tiers, patrons)
    if output.exists():
        shutil.rmtree(output)
    output.mkdir(parents=True)
    images = Images(output / "images", fetcher)
    (output / "index.html").write_text(page_html(document, contributors, by_tier, tiers, images), encoding="utf-8")
    (output / "credits.json").write_text(
        json.dumps(credits_document(document, contributors, by_tier, tiers), indent=2) + "\n", encoding="utf-8"
    )
    return by_tier


def parse_arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--repository-root", type=pathlib.Path, default=pathlib.Path(__file__).resolve().parent.parent)
    parser.add_argument("--output", type=pathlib.Path)
    return parser.parse_args()


def main() -> int:
    arguments = parse_arguments()
    root = arguments.repository_root.resolve()
    output = (arguments.output or root / "Website" / "credits").resolve()
    document = json.loads((root / CREDITS_PATH).read_text(encoding="utf-8"))
    settings = document.get("contributors", {})
    repository = str(settings.get("repository", "pauljoda/Crest"))
    exclude = {str(login).casefold() for login in settings.get("exclude", [])}
    contributors = github_contributors(repository, exclude, os.environ.get("GITHUB_TOKEN"))
    patreon_token = os.environ.get("PATREON_ACCESS_TOKEN")
    patrons = patreon_patrons(patreon_token) if patreon_token else None
    by_tier = build(root, output, contributors=contributors, patrons=patrons, fetcher=lambda url: fetch(url, accept="image/*"))
    listed = sum(len(people) for people in by_tier.values())
    print(
        f"Wrote the credits page to {output} ({len(contributors or [])} contributors, {listed} supporters"
        f"{f', {len(patrons)} active patrons on Patreon' if patrons is not None else ''})."
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
