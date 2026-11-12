"""Generate the SDK reference Markdown from the Swift doc comments with DocC, build time only.

`xcodebuild docbuild` builds the iOS DocC archive with the DocC that ships in Xcode. Its render JSON
holds each symbol's declaration, parameters and discussion. Our code walks that JSON, groups
PostHogSDK members by the sdk-specs capability `docs/capabilities.json` maps their base name to, in
the PostHog/sdk-specs README's order, and writes front matter. Members the map lists under "utils" go
to SDK utils, and "next" maps members only the next major has. A member in neither, an unknown slug,
or, for the declared major, a map key with no member fails the run.
Symbols obsoleted or unavailable in Swift are left out.

    python3 scripts/generate-markdown.py --sdk-specs DIR [--major 4]
"""

import argparse
import json
import subprocess
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
FIRST = ["setup", "capture", "identify"]
# Public helpers with no place in the reference, and members the compiler synthesizes.
SKIP = {"Gzip", "GzipError", "CompressionLevel", "ReachabilityError", "BoxedBeforeSendBlock", "BoxedBeforeSendLogBlock"}
SYNTHESIZED = {"==(_:_:)", "!=(_:_:)", "hash(into:)", "hashValue", "rawValue", "init(rawValue:)"}
EXTENDED = ["View", "UIView", "URLSession"]  # extensions of system types, listed under SDK utils
MDX = str.maketrans({"<": "&lt;", "{": "&#123;", "}": "&#125;"})  # MDX 1 reads these as JSX


class Archive:
    def __init__(self, derived: Path):
        self.data = next(derived.rglob("PostHog.doccarchive")) / "data"
        # The render JSON drops Swift-only availability, so read it from the Swift symbol graph.
        graph = next(p for p in derived.rglob("PostHog.symbols.json") if "swift" in p.parts)
        self.no_swift = set()
        for symbol in json.loads(graph.read_text())["symbols"]:
            for a in symbol.get("availability", []):
                if a.get("domain") in ("Swift", "*") and ("obsoleted" in a or a.get("isUnconditionallyUnavailable")):
                    self.no_swift.add(symbol["identifier"]["precise"])

    def page(self, url: str) -> dict:
        return json.loads((self.data / f"{url.strip('/')}.json").read_text())

    def members(self, page: dict) -> list[dict]:
        """The symbols a page lists in its topic sections, in DocC's order."""
        out = []
        for section in page.get("topicSections", []):
            if section["title"] != "Default Implementations":
                out += [self.page(page["references"][i]["url"]) for i in section["identifiers"]]
        return [m for m in out if m["metadata"]["title"] not in SYNTHESIZED and self.callable(m["metadata"])]

    def callable(self, meta: dict) -> bool:
        """False for symbols Swift code can't call: obsoleted or unavailable in Swift or on iOS."""
        unavailable = any(p.get("unavailable") for p in meta.get("platforms", []))
        return not unavailable and meta.get("externalID") not in self.no_swift


def inline(nodes: list, refs: dict) -> str:
    out = []
    for n in nodes:
        kind = n["type"]
        if kind == "text":
            out.append(n["text"].translate(MDX))
        elif kind == "codeVoice":
            out.append(f"`{n['code']}`")
        elif kind == "reference":
            out.append(f"`{refs.get(n['identifier'], {}).get('title', n['identifier'].split('/')[-1])}`")
        elif kind in ("emphasis", "strong"):
            mark = "*" if kind == "emphasis" else "**"
            out.append(mark + inline(n["inlineContent"], refs) + mark)
        elif kind == "link":
            out.append(f"[{n['title']}]({n['destination']})")
    return "".join(out)


def blocks(nodes: list, refs: dict, level: int) -> list[str]:
    out = []
    for n in nodes:
        kind = n["type"]
        if kind == "paragraph":
            out.append(inline(n["inlineContent"], refs))
        elif kind == "heading":
            out.append("#" * (level + n["level"] - 2) + " " + n["text"])
        elif kind == "codeListing":
            out.append(f"```{n.get('syntax') or 'swift'}\n" + "\n".join(n["code"]) + "\n```")
        elif kind in ("unorderedList", "orderedList"):
            mark = "-" if kind == "unorderedList" else "1."
            for item in n["items"]:
                out.append(f"{mark} " + "\n  ".join(blocks(item["content"], refs, level)))
        elif kind == "aside":
            body = "\n> ".join(blocks(n["content"], refs, level))
            out.append(f"> **{n.get('name') or n['style'].title()}:** {body}")
    return out


def base(page: dict) -> str:
    """A member's name without its argument labels, which the capability map is keyed by."""
    return page["metadata"]["title"].split("(")[0]


def entries(pages: list[dict], prefix: str, level: int) -> list[str]:
    """Overloads DocC titles alike, such as `captureException(_:)` for Error and NSException, share a heading."""
    titles = [p["metadata"]["title"] for p in pages]
    return [entry(p, prefix + t, level, t not in titles[:i]) for i, (p, t) in enumerate(zip(pages, titles))]


def entry(page: dict, label: str, level: int, heading: bool = True) -> str:
    refs = page.get("references", {})
    parts = [f"{'#' * level} `{label}`" if heading else ""]
    for section in page.get("primaryContentSections", []):
        if section["kind"] == "declarations":
            tokens = section["declarations"][0]["tokens"]
            parts.append("```swift\n" + "".join(t["text"] for t in tokens) + "\n```")
    deprecated = " ".join(blocks(page.get("deprecationSummary", []), refs, level))
    if deprecated or any(p.get("deprecated") for p in page["metadata"].get("platforms", [])):
        parts.append(f"> **Deprecated:** {deprecated}" if deprecated else "> **Deprecated.**")
    parts.append(inline(page.get("abstract", []), refs))
    for section in page.get("primaryContentSections", []):
        if section["kind"] == "parameters":
            rows = [f"- `{p['name']}`: " + " ".join(blocks(p["content"], refs, level + 1)) for p in section["parameters"]]
            parts.append(f"{'#' * (level + 1)} Parameters\n\n" + "\n".join(rows))
        elif section["kind"] == "content":
            body = blocks(section["content"], refs, level + 1)
            if body and not (len(body) == 1 and body[0].endswith(" Discussion")):
                parts += body
    return "\n\n".join(p for p in parts if p)


def capabilities(checkout: str) -> dict[str, str]:
    """Each sdk-specs capability's slug and title in sentence case, in the README's order."""
    acronyms = {"id": "ID", "ai": "AI", "http": "HTTP", "mcp": "MCP"}
    titles = {}
    for line in (Path(checkout) / "README.md").read_text().split("\n"):
        cells = line.split("|")
        if len(cells) > 2 and "openspec/specs/" in cells[2]:
            slug = cells[2].split("openspec/specs/")[1].split("/")[0]
            titles[slug] = " ".join(acronyms.get(w.lower(), w.lower()) for w in cells[1].split())
    order = [*FIRST, *(s for s in titles if s not in FIRST)]
    return {s: titles[s][0].upper() + titles[s][1:] for s in order if s in titles}


def reference(archive: Archive, caps: dict[str, str], current: bool) -> list[str]:
    module = archive.page("documentation/posthog")
    symbols = archive.members(module)
    by_title = {s["metadata"]["title"]: s for s in symbols}
    sdk = archive.members(by_title["PostHogSDK"])
    mapped = json.loads((ROOT / "docs/capabilities.json").read_text())
    utils, upcoming, names = set(mapped.pop("utils")), mapped.pop("next"), {base(m) for m in sdk}
    if missing := sorted(names - set(mapped) - set(upcoming) - utils):
        raise SystemExit(f"PostHogSDK members not in docs/capabilities.json: {missing}")
    if current and (stale := sorted(set(mapped) - names)):
        raise SystemExit(f"docs/capabilities.json names no PostHogSDK member: {stale}")
    mapped |= upcoming
    if unknown := sorted(set(mapped.values()) - set(caps)):
        raise SystemExit(f"docs/capabilities.json slugs not in sdk-specs: {unknown}")
    out = []
    for slug, title in caps.items():
        if members := [m for m in sdk if mapped.get(base(m)) == slug]:
            out += [f"## {title}", *entries(members, "PostHogSDK.", 3)]
    out += ["## SDK utils", *entries([m for m in sdk if base(m) in utils], "PostHogSDK.", 3)]
    for extended in (s for s in symbols if s["metadata"].get("role") == "collection"):
        for t in archive.members(extended):
            if t["metadata"]["title"] in EXTENDED:
                out += entries(archive.members(t), f"{t['metadata']['title']}.", 3)
    out.append("## Types")
    for t in symbols:
        name, kind = t["metadata"]["title"], t["metadata"].get("symbolKind")
        if name in SKIP or name == "PostHogSDK" or kind not in ("class", "struct", "enum", "protocol", "typealias"):
            continue
        out.append(entry(t, name, 3))
        out += entries(archive.members(t), f"{name}.", 4)
    return out


def anchor(heading: str) -> str:
    """The github-slugger slug the docs site gives a heading."""
    return "".join(c for c in heading.lower() if c.isalnum() or c in "-_ ").replace(" ", "-")


def front_matter(title: str, sections: list[str]) -> str:
    """The docs site's front matter. Its ToC lists the page's H2 sections only."""
    toc = []
    for heading in [s[3:] for s in sections if s.startswith("## ")]:
        toc.append(f'  - value: "{heading}"\n    url: {anchor(heading)}\n    depth: 0')
    head = [f'title: "{title}"', "sidebar: Docs", "showTitle: true", "contentMaxWidthClass: max-w-full"]
    return "\n".join(["---", *head, "platformLogo: ios", "tableOfContents:", *toc, "---"])


def nest(markdown: str) -> str:
    """Moves each heading down one level and drops the H1. Code stays as written."""
    out, fence = [], False
    for line in markdown.strip().split("\n"):
        fence ^= line.strip().startswith("```")
        if fence or not line.startswith("#"):
            out.append(line)
        elif not line.startswith("# "):
            out.append("#" + line)
    return "\n".join(out)


def migration_page(guides: list[str]) -> list[str]:
    """The migration page. One guide's H1 becomes the page title, so the page shows one title."""
    title = "PostHog iOS SDK migration guides"
    if len(guides) == 1 and guides[0].startswith("# "):
        heading, _, rest = guides[0].partition("\n")
        title, guides = heading[2:].strip(), [rest.strip()]
    return [f"---\ntitle: {json.dumps(title)}\nsidebar: Docs\nshowTitle: true\n---", *guides]


def write(name: str, sections: list[str]) -> None:
    (ROOT / "references" / name).write_text("\n\n".join(sections) + "\n")
    print(f"wrote references/{name}")


def main() -> None:
    args = argparse.ArgumentParser(description="Generate the SDK reference Markdown.")
    args.add_argument("--sdk-specs", required=True, help="PostHog/sdk-specs checkout")
    args.add_argument("--major", type=int, help="target major, defaults to the declared one")
    opts = args.parse_args()
    version = next(l for l in (ROOT / "PostHog/PostHogVersion.swift").read_text().split("\n") if "postHogVersion = " in l)
    declared = int(version.split('"')[1].split(".")[0])
    major = opts.major or declared
    with tempfile.TemporaryDirectory() as tmp:
        subprocess.run(
            ["xcodebuild", "docbuild", "-scheme", "PostHog", "-destination", "generic/platform=iOS",
             "-derivedDataPath", tmp, "-quiet"],
            cwd=ROOT, check=True,
        )
        archive = Archive(Path(tmp))
        body = ["## Getting started", nest((ROOT / "docs/getting-started.md").read_text())]
        body += reference(archive, capabilities(opts.sdk_specs), declared >= major)
    (ROOT / "references").mkdir(exist_ok=True)
    title = f"PostHog iOS SDK {major}.x" + ("" if declared >= major else " (experimental)")
    write(f"posthog-ios-{major}.md", [front_matter(title, body), *body])
    if declared >= major:
        write("posthog-ios-reference.md", [front_matter("PostHog iOS SDK", body), *body])
    if (ROOT / "MIGRATION.md").exists():
        write("posthog-ios-migration.md", migration_page([(ROOT / "MIGRATION.md").read_text().strip().replace("<br>", "<br />")]))


if __name__ == "__main__":
    main()
