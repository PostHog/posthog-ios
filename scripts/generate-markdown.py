"""Generate the SDK reference Markdown from the Swift doc comments with DocC, build time only.

xcodebuild's docbuild writes the iOS symbol graph, then `docc convert --enable-experimental-markdown-output`
(Swift 6.3 or later, or a newer docc through $DOCC) renders one Markdown page per symbol. Our code only
groups and orders those pages and writes front matter. A `posthog-capability: <slug>` line in a doc comment
puts a symbol under that PostHog/sdk-specs capability. Untagged PostHogSDK members go to SDK utils.

    python3 scripts/generate-markdown.py --sdk-specs DIR [--major 4]
"""

import argparse
import json
import os
import re
import subprocess
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
FIRST = ["setup", "capture", "identify"]
KINDS = {"Class", "Structure", "Enumeration", "Protocol", "Type Alias"}
# Public helpers with no place in the reference, and members the compiler synthesizes.
SKIP = re.compile(r"^(gzip|gziperror|compressionlevel|reachabilityerror|boxedbeforesend\w*)$")
SYNTHESIZED = re.compile(r"(-implementations$|^(==|!=|hash|hashvalue|rawvalue)(?![a-z])|^init\(rawvalue:\)$)")
TAG = re.compile(r"^[ \t]*posthog-capability:[ \t]*([a-z0-9-]+)[ \t]*\n?", re.M)
HEAD = re.compile(r"^## (Overview|Discussion|Parameters|Return Value)(?=\S)", re.M)


class Page:
    """One DocC symbol page, with its capability tag stripped from the body."""

    def __init__(self, path: Path):
        text = path.read_text()
        meta, _, body = text.partition("\n-->\n")
        self.meta = json.loads(meta.removeprefix("<!--\n"))
        self.role = self.meta.get("role", "")
        self.title = self.meta["title"]
        self.file = path.stem
        found = TAG.search(body)
        self.tag = found.group(1) if found else None
        body = HEAD.sub(r"## \1\n\n", TAG.sub("", body))
        self.body = re.sub(r"\n## Discussion\s*(?=\n## |\Z)", "", body).strip()

    def render(self, name: str, level: int) -> str:
        """The page under a `name` heading at `level`, inner headings one level down."""
        out, fence = [], False
        for line in self.body.split("\n")[1:]:
            if re.match(r"\s*```", line):
                fence = not fence
                line = "```swift" if fence and line.strip() == "```" else line
            elif not fence and line.startswith("## "):
                line = "#" * (level + 1) + line[2:]
            out.append(line)
        return mdx_safe(f"{'#' * level} `{name}`\n" + "\n".join(out))


def mdx_safe(markdown: str) -> str:
    """The site reads Markdown as MDX 1: braces and angle brackets outside code are JSX."""
    out, fence = [], False
    for line in markdown.split("\n"):
        fence ^= bool(re.match(r"\s*```", line))
        if not fence and not line.startswith("```"):
            parts = re.split(r"(`[^`]*`)", line)
            line = "".join(
                p if i % 2 else re.sub(r"[{}<]", lambda m: "&#" + str(ord(m.group())) + ";", p)
                for i, p in enumerate(parts)
            )
        out.append(line)
    return "\n".join(out)


def pages(folder: Path) -> list[Page]:
    return [Page(p) for p in sorted(folder.glob("*.md"))]


def capabilities(checkout: str) -> dict[str, str]:
    """Each sdk-specs capability's slug and title in sentence case, in the README's order."""
    readme = (Path(checkout) / "README.md").read_text()
    rows = re.findall(r"^\| ([^|]+?) \| \[`openspec/specs/([a-z0-9-]+)/spec\.md`\]", readme, re.M)
    acronyms = {"id": "ID", "ai": "AI", "http": "HTTP", "mcp": "MCP"}
    titles = {s: " ".join(acronyms.get(w.lower(), w.lower()) for w in n.split()) for n, s in rows}
    order = [*FIRST, *(s for s in titles if s not in FIRST)]
    return {s: titles[s][0].upper() + titles[s][1:] for s in order if s in titles}


def convert(work: Path) -> Path:
    """docbuild for the iOS symbol graph, then docc to Markdown. Returns the Markdown folder."""
    subprocess.run(
        ["xcodebuild", "docbuild", "-scheme", "PostHog", "-destination", "generic/platform=iOS",
         "-derivedDataPath", str(work / "build")],
        cwd=ROOT, check=True, stdout=subprocess.DEVNULL,
    )
    graphs = next((work / "build").rglob("symbol-graph/swift/*")).parent
    docc = os.environ.get("DOCC") or subprocess.check_output(["xcrun", "--find", "docc"], text=True).strip()
    subprocess.run(
        [docc, "convert", "--additional-symbol-graph-dir", str(graphs), "--fallback-display-name", "PostHog",
         "--fallback-bundle-identifier", "com.posthog.PostHog", "--enable-experimental-markdown-output",
         "--no-transform-for-static-hosting", "--output-dir", str(work / "docs")],
        check=True, stdout=subprocess.DEVNULL,
    )
    return work / "docs/data/documentation/posthog"


def reference(docs: Path, caps: dict[str, str]) -> list[str]:
    sdk = pages(docs / "posthogsdk")
    # Methods keep their DocC order, so overloads stay together under a capability.
    out = []
    for slug, title in caps.items():
        if tagged := [p for p in sdk if p.tag == slug]:
            out += [f"## {title}", *(p.render(f"PostHogSDK.{p.title}", 3) for p in tagged)]
    extensions = [p for d in ("swiftuicore/view", "uikit/uiview", "foundation/urlsession") for p in pages(docs / d)]
    out += ["## SDK utils", *(p.render(f"PostHogSDK.{p.title}", 3) for p in sdk if not p.tag)]
    out += [p.render(p.title, 3) for p in extensions if p.role != "Extension"]
    types = [p for p in pages(docs) if p.role in KINDS and p.file != "posthogsdk" and not SKIP.match(p.file)]
    out.append("## Types")
    for t in types:
        out.append(t.render(t.title, 3))
        members = [m for m in pages(docs / t.file) if not SYNTHESIZED.search(m.file)]
        out += [m.render(f"{t.title}.{m.title.removeprefix(t.title + '.')}", 4) for m in members]
    return out


def front_matter(title: str, sections: list[str]) -> str:
    """The docs site's front matter. Its ToC lists the page's H2 sections only."""
    toc = []
    for heading in [s[3:] for s in sections if s.startswith("## ")]:
        anchor = re.sub(r"[^\w\- ]", "", heading.lower()).replace(" ", "-")
        toc.append(f'  - value: "{heading}"\n    url: {anchor}\n    depth: 0')
    head = [f'title: "{title}"', "sidebar: Docs", "showTitle: true", "contentMaxWidthClass: max-w-full"]
    return "\n".join(["---", *head, "platformLogo: ios", "tableOfContents:", *toc, "---"])


def nest(markdown: str) -> str:
    """Moves each heading down one level and drops the H1. Code stays as written."""
    out, fence = [], False
    for line in markdown.strip().split("\n"):
        fence ^= bool(re.match(r"\s*```", line))
        if fence or not re.match(r"#{1,5} ", line):
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
    version = re.search(r'postHogVersion = "(\d+)', (ROOT / "PostHog/PostHogVersion.swift").read_text())
    declared = int(version.group(1))
    major = opts.major or declared
    with tempfile.TemporaryDirectory() as tmp:
        docs = convert(Path(tmp))
        body = ["## Getting started", nest((ROOT / "docs/getting-started.md").read_text()),
                *reference(docs, capabilities(opts.sdk_specs))]
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
