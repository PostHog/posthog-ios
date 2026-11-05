"""Generate the SDK reference Markdown from the Swift doc comments with DocC, build time only.

`xcodebuild docbuild` builds the iOS DocC archive with the DocC that ships in Xcode. Its render JSON
holds each symbol's declaration, parameters and discussion. Our code walks that JSON, groups symbols
by the `posthog-capability: <slug>` line in their doc comment, in the PostHog/sdk-specs README's
order, and writes front matter. PostHogSDK members listed in UTILS go to SDK utils, and any other
untagged member fails the run. Symbols obsoleted or unavailable in Swift are left out.

    python3 scripts/generate-markdown.py --sdk-specs DIR [--major 4]
"""

import argparse
import json
import subprocess
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
FIRST = ["setup", "capture", "identify"]
TAG = "posthog-capability:"
# Public helpers with no place in the reference, and members the compiler synthesizes.
SKIP = {"Gzip", "GzipError", "CompressionLevel", "ReachabilityError", "BoxedBeforeSendBlock", "BoxedBeforeSendLogBlock"}
# Untagged PostHogSDK members that belong to no sdk-specs capability, across 3.x and 4.x.
UTILS = {
    "shared", "didStartNotification", "setAppLanguage(_:)",
    "captureDeepLink(openURLContexts:)", "captureDeepLink(url:)", "captureDeepLink(url:options:)",
    "captureDeepLink(urls:)", "captureDeepLink(userActivity:)",
    "captureFeatureInteraction(flag:flagVariant:)", "captureFeatureView(flag:flagVariant:)",
    "capturePushNotificationOpened(response:)", "capturePushNotificationOpened(title:subtitle:body:payload:action:)",
    "prewarmPushNotificationOpenCapture()", "registerPushNotificationToken(_:)",
    "registerPushNotificationToken(_:appId:)", "unregisterPushNotificationToken()",
}
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
            text = inline(n["inlineContent"], refs)
            if not text.lower().startswith(TAG):
                out.append(text)
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


def tag(page: dict) -> str | None:
    for section in page.get("primaryContentSections", []):
        for n in section.get("content", []):
            text = inline(n.get("inlineContent", []), {}).lower()
            if n["type"] == "paragraph" and text.startswith(TAG):
                return text[len(TAG) :].strip()
    return None


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


def reference(archive: Archive, caps: dict[str, str]) -> list[str]:
    module = archive.page("documentation/posthog")
    symbols = archive.members(module)
    by_title = {s["metadata"]["title"]: s for s in symbols}
    sdk = archive.members(by_title["PostHogSDK"])
    if untagged := [m["metadata"]["title"] for m in sdk if not tag(m) and m["metadata"]["title"] not in UTILS]:
        raise SystemExit(f"PostHogSDK members with no capability tag, tag them or add them to UTILS: {untagged}")
    out = []
    for slug, title in caps.items():
        if tagged := [m for m in sdk if tag(m) == slug]:
            out += [f"## {title}", *entries(tagged, "PostHogSDK.", 3)]
    found = {tag(m) for m in sdk} - {None} - set(caps)
    if found:
        raise SystemExit(f"unknown capability tags: {sorted(found)}")
    out += ["## SDK utils", *entries([m for m in sdk if not tag(m)], "PostHogSDK.", 3)]
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
        body += reference(archive, capabilities(opts.sdk_specs))
    (ROOT / "references").mkdir(exist_ok=True)
    title = f"PostHog iOS SDK {major}.x" + ("" if declared >= major else " (experimental)")
    write(f"posthog-ios-{major}.md", [front_matter(title, body), *body])
    if declared >= major:
        write("posthog-ios-reference.md", [front_matter("PostHog iOS SDK", body), *body])
    if (ROOT / "MIGRATION.md").exists():
        head = "---\ntitle: PostHog iOS SDK migration guides\nsidebar: Docs\nshowTitle: true\n---"
        write("posthog-ios-migration.md", [head, (ROOT / "MIGRATION.md").read_text().strip().replace("<br>", "<br />")])


if __name__ == "__main__":
    main()
