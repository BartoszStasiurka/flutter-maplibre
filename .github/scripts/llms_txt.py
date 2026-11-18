#!/usr/bin/env python3
"""Writes llms.txt, llms-full.txt and a Markdown copy of every page.

Run after `zensical build` from the repository root. It reads the nav of
`mkdocs.yml` and writes into the built site (`site/` by default):

- `<page>.md`: the Markdown source of each page, with relative links made
  absolute, at the URL of its HTML page with `.md` for the trailing `/`.
- `llms.txt`: the "Writing code for 0.4" section of the AI tools page and an
  index of the docs with a link to each Markdown copy, as proposed on
  https://llmstxt.org.
- `skills/<name>/SKILL.md`: the agent skills of the repository's `skills/`.
- `llms-full.txt`: the getting started pages, guides, the current migration
  guides and the contributor docs in one file.
"""

from __future__ import annotations

import posixpath
import re
import sys
from dataclasses import dataclass
from pathlib import Path

import yaml

ROOT = Path(__file__).resolve().parents[2]

# Nav sections and pages listed under "Optional" in llms.txt and left out of
# llms-full.txt: guides for old versions and the comparison with other
# packages. The landing page is left out of both.
OPTIONAL_SECTIONS = {"Older versions"}
OPTIONAL_PAGES = {"compare/index.md"}
EXCLUDED_PAGES = {"index.md"}

# The page and section that llms.txt starts with: what to know before writing
# code with the current API. It is kept on the docs site, not here.
INTRO_PAGE = "docs/getting-started/ai-tools.md"
INTRO_HEADING = "## Writing code for 0.4"


@dataclass
class Page:
    title: str
    path: str  # relative to docs_dir, e.g. "docs/map.md"
    section: str


class _Loader(yaml.SafeLoader):
    """Reads mkdocs.yml, ignoring its `!!python/…` tags."""


_Loader.add_multi_constructor("tag:yaml.org,2002:python/", lambda *_: None)


def _walk(nav: list, section: str, pages: list[Page]) -> None:
    """Lists the pages of the nav with the title of their innermost section.

    The pages of a section that also has subsections, such as the overview of
    "Docs", join its first subsection.
    """
    waiting: list[Page] = []
    for item in nav:
        if isinstance(item, str):
            item = {item: item}
        for title, value in item.items():
            if isinstance(value, list):
                start = len(pages)
                _walk(value, title, pages)
                for page in waiting:
                    page.section = pages[start].section
                pages[start:start] = waiting
                waiting = []
            elif isinstance(value, str) and value.endswith(".md"):
                pages.append(Page(title, value, section))
                if any(isinstance(v, list) for i in nav if isinstance(i, dict) for v in i.values()):
                    waiting.append(pages.pop())
    pages.extend(waiting)


def _split_front_matter(text: str) -> tuple[dict, str]:
    if text.startswith("---\n"):
        end = text.find("\n---\n", 4)
        if end != -1:
            meta = yaml.safe_load(text[4:end]) or {}
            return meta, text[end + 5 :].lstrip("\n")
    return {}, text


def _md_path(page_path: str) -> str:
    """The path of a page's Markdown copy: its URL with `.md` for the `/`.

    `docs/map.md` stays `docs/map.md`, and the section page
    `docs/annotations/index.md` becomes `docs/annotations.md`.
    """
    if page_path.endswith("/index.md"):
        return page_path[: -len("/index.md")] + ".md"
    return page_path


def _html_dir(page_path: str) -> str:
    """The directory of a page's URL, which raw HTML links resolve against."""
    if page_path == "index.md":
        return ""
    if page_path.endswith("/index.md"):
        return posixpath.dirname(page_path)
    return page_path[: -len(".md")]


_FENCE = re.compile(r"^(```|~~~).*?^\1", re.M | re.S)
_MD_LINK = re.compile(r"(\]\()([^)\s]+)(\))")
_HTML_LINK = re.compile(r"""((?:href|src)=")([^"]+)(")""")


def _absolute_links(body: str, page_path: str, site_url: str) -> str:
    """Makes the relative links of a page absolute, outside of code fences.

    Markdown links resolve against the Markdown file and point to the
    Markdown copy of a page, raw HTML links resolve against the page's URL.
    """

    def resolver(base: str, markdown: bool):
        def replace(match: re.Match) -> str:
            target = match.group(2)
            if re.match(r"^[a-z][a-z0-9+.-]*:|^#|^/", target):
                return match.group(0)
            path, _, anchor = target.partition("#")
            resolved = posixpath.normpath(posixpath.join(base, path))
            if resolved == ".":
                resolved = ""
            if markdown and resolved.endswith(".md"):
                resolved = _md_path(resolved)
            elif path.endswith("/") and resolved:
                resolved += "/"
            url = site_url + resolved + (f"#{anchor}" if anchor else "")
            return match.group(1) + url + match.group(3)

        return replace

    md = resolver(posixpath.dirname(page_path), markdown=True)
    html = resolver(_html_dir(page_path), markdown=False)
    parts, last = [], 0
    for fence in _FENCE.finditer(body):
        text = body[last : fence.start()]
        parts += [_HTML_LINK.sub(html, _MD_LINK.sub(md, text)), fence.group(0)]
        last = fence.end()
    text = body[last:]
    parts.append(_HTML_LINK.sub(html, _MD_LINK.sub(md, text)))
    return "".join(parts)


def _section(body: str, heading: str) -> str:
    """The text below a `## ` heading, up to the next one."""
    start = body.index(heading + "\n") + len(heading) + 1
    end = body.find("\n## ", start)
    return body[start : end if end != -1 else None].strip()


def _description(meta: dict) -> str:
    return str(meta.get("description", ""))


def main() -> None:
    site_dir = Path(sys.argv[1]) if len(sys.argv) > 1 else ROOT / "site"
    config = yaml.load((ROOT / "mkdocs.yml").read_text(), Loader=_Loader)
    docs_dir = ROOT / config.get("docs_dir", "docs")
    site_url = config["site_url"].rstrip("/") + "/"

    pages: list[Page] = []
    _walk(config["nav"], "", pages)

    _, intro_body = _split_front_matter((docs_dir / INTRO_PAGE).read_text())
    intro = _absolute_links(_section(intro_body, INTRO_HEADING), INTRO_PAGE, site_url)
    header = [f"# {config['site_name']}", "", f"> {config['site_description']}", ""]
    index = [*header, INTRO_HEADING, "", intro, ""]
    full = list(header)
    sections: dict[str, list[str]] = {}
    optional: list[str] = []
    written = 0

    for page in pages:
        if page.path in EXCLUDED_PAGES:
            continue
        meta, body = _split_front_matter((docs_dir / page.path).read_text())
        body = _absolute_links(body, page.path, site_url)
        md_path = _md_path(page.path)
        out = site_dir / md_path
        out.parent.mkdir(parents=True, exist_ok=True)
        out.write_text(body)
        written += 1

        url = site_url + md_path
        description = _description(meta)
        entry = f"- [{page.title}]({url})" + (f": {description}" if description else "")
        if page.section in OPTIONAL_SECTIONS or page.path in OPTIONAL_PAGES:
            optional.append(entry)
            continue
        sections.setdefault(page.section or "More", []).append(entry)
        full += ["", "---", "", f"Source: {url}", "", body.rstrip()]

    # Agent skills of the repository, served next to the docs.
    skills = []
    for skill in sorted((ROOT / "skills").glob("*/SKILL.md")):
        meta, _ = _split_front_matter(skill.read_text())
        out = site_dir / "skills" / skill.parent.name / "SKILL.md"
        out.parent.mkdir(parents=True, exist_ok=True)
        out.write_text(skill.read_text())
        url = f"{site_url}skills/{skill.parent.name}/SKILL.md"
        skills.append(f"- [{meta['name']}]({url}): {meta['description']}")

    for section, entries in sections.items():
        index += [f"## {section}", "", *entries, ""]
    index += [
        "## API reference",
        "",
        "- [maplibre on pub.dev](https://pub.dev/documentation/maplibre/latest/maplibre/):"
        " the dartdoc of every public class and member.",
        f"- [llms-full.txt]({site_url}llms-full.txt): every page above in one file.",
        "",
        "## Skills",
        "",
        *skills,
        "",
        "## Optional",
        "",
        *optional,
        "",
    ]

    (site_dir / "llms.txt").write_text("\n".join(index))
    (site_dir / "llms-full.txt").write_text("\n".join(full) + "\n")
    print(f"Wrote llms.txt and llms-full.txt for {written} pages to {site_dir}")


if __name__ == "__main__":
    main()
