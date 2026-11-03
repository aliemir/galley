# Contributing to Galley

Bug fixes, accessibility improvements, documentation, and small features are
welcome. Check the [issues](https://github.com/aliemir/galley/issues) and
[pull requests](https://github.com/aliemir/galley/pulls) before starting. Comment
on an issue if you would like to work on it; for a larger change, open an issue
first to agree on the behavior and scope.

## Get started

Fork the repository, clone your fork, and create a branch for one change.
The [README](README.md#repository) maps the repository;
[notes/decisions.md](notes/decisions.md) records settled product choices.

### Mac app

Galley is a native macOS app. You need a Mac with Xcode, and macOS 15 or later
to run it. Follow [Build it yourself](README.md#build-it-yourself) for project
setup and local signing. Release credentials are not needed to contribute.

A normal development build uses the same library as the released app at
`~/Library/Application Support/Galley`. Quit the released app before running
your build: concurrent copies can overwrite each other's highlights and notes.
Use the [Showcase workspace](app/Fixtures/Showcase) for manual checks.

Galley never writes to Markdown files. Highlights and notes belong in its
library; preserve that boundary when changing app behavior.

### Website

Website work needs Node.js and npm. From the repository root:

```sh
cd website
npm ci
npm run dev
```

See [website/AGENTS.md](website/AGENTS.md) for the page layout and commands.
Edit `website/input.css`; `website/public/style.css` is generated and must not
be committed. `npm run dev` builds the CSS before starting the local server.

## Check your change

For app behavior changes, add or update focused tests and run the unit suite
from the repository root with a throwaway library and home:

```sh
TEST_RUNNER_GALLEY_LIBRARY=/private/tmp/galley-contributor-tests/library \
TEST_RUNNER_GALLEY_HOME=/private/tmp/galley-contributor-tests/home \
xcodebuild -project app/Galley.xcodeproj -scheme Galley \
  -destination 'platform=macOS' test -only-testing:GalleyTests
```

These variables keep the test host's library and agent-tool installations
separate from yours. Without them, tests can use your real library. The test
host may stay open afterward; quit it before launching another development
copy. UI tests control the real desktop's mouse and keyboard, so run them
only when needed and when the desktop is free.

For website changes, run `npm run build:css` in `website/` and check the affected
pages locally at desktop and mobile widths. Check documentation changes for
working links and accurate commands.

If a UI change affects the guide or website pictures, regenerate them with
`tools/capture-guide.sh` and include only captures that changed. See
[AGENTS.md](AGENTS.md) for further development details.

## Submit a pull request

- Keep the PR focused on one problem and link its issue, using `Closes #123`
  when the PR resolves it.
- Describe the problem, resulting behavior, and how you checked the change.
  Include screenshots for visible UI changes and mention checks you could
  not run.
- Update the relevant guide, website, or README when behavior changes. Add a
  dated entry to [notes/changelog.md](notes/changelog.md) for a meaningful
  change; typo and formatting fixes do not need one.
- Use Conventional Commit subjects, such as
  `fix(reader): keep the selected section in view`.
- Keep secrets, signing keys, personal libraries, and temporary files out of
  the PR.

Push the branch to your fork and open a PR against `aliemir/galley`'s `main`.
Respond to review feedback with updates on the same branch.
