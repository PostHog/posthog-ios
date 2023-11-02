async function checkChangelog() {
  const changelogFile = "CHANGELOG.md";

  // Check if skipped
  const skipChangelog =
    danger.github && (danger.github.pr.body + "").includes("#skip-changelog");

  if (skipChangelog) {
    return;
  }

  // Check if current PR has an entry in changelog
  const changelogContents = await danger.github.utils.fileContents(
    changelogFile
  );

  const hasChangelogEntry = RegExp(`#${danger.github.pr.number}\\b`).test(
    changelogContents
  );

  if (hasChangelogEntry) {
    return;
  }

  // Report missing changelog entry
  fail(
    "Please consider adding a changelog entry for the next release.",
    changelogFile
  );

  const prTitleFormatted = danger.github.pr.title
    .split(": ")
    .slice(-1)[0]
    .trim()
    .replace(/\.+$/, "");

  markdown(
    `
### Instructions and example for changelog
Please add an entry to \`CHANGELOG.md\` to the "Next" section. Make sure the entry includes this PR's number.
Example:
\`\`\`markdown
## Next
- ${prTitleFormatted} ([#${danger.github.pr.number}](${danger.github.pr.html_url}))
\`\`\`
If none of the above apply, you can opt out of this check by adding \`#skip-changelog\` to the PR description.`.trim()
  );
}

async function checkAll() {
  const isDraft = danger.github.pr.mergeable_state === "draft";

  if (isDraft) {
    return;
  }

  await checkChangelog();
}

schedule(checkAll);
