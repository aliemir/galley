---
name: galley
description: Read the user's feedback on Markdown files you wrote — passages they highlighted and notes they left in Galley, their Markdown reader — and wait for more. Use when the user says they left feedback, comments, notes or highlights in Galley, asks you to address their feedback on a plan, spec or other Markdown file, or asks you to watch for or wait on their feedback.
---

# Galley feedback

The user reads the Markdown you write in **Galley**, a read-only reader.
While reading they mark it up: they highlight passages and often add a
note saying what they want. Galley never changes the files — the feedback
lives in Galley, and you read it with the `galley` command.

Marks start as drafts. The user **saves** them (Save Feedback, ⌘S) when
a round is ready, and only then are they yours: `galley feedback` shows
saved feedback. Drafts are their work in progress — leave them alone
unless the user asks you to look at them (`--drafts`).

## Read it

```sh
galley feedback path/to/file.md   # one file
galley feedback path/to/folder    # every file under a folder
galley feedback                   # the current folder
galley feedback --json            # the same, as JSON
```

The output is Markdown: for each file, its absolute path as a heading,
then numbered items — where the passage is (`Marked in Rollout › Token
shape`, the headings it sits under), the passage quoted, and under it
the user's note when they wrote one. No output (and "No feedback on …" on
stderr) means there is none; the message says when drafts are waiting
to be saved.

With `--json`, the same as data — one entry per file, `note` empty when
the user wrote none, `section` empty for a passage above the first
heading, `saved` when the user saved it:

```json
[
  {
    "path": "/Users/you/project/plans/auth.md",
    "items": [
      {
        "text": "Tokens live for 15 minutes.",
        "note": "Make it 10 for admin sessions.",
        "section": ["Rollout", "Token shape"],
        "draft": false,
        "saved": "2026-11-02T14:03:11Z"
      }
    ]
  }
]
```

Handy for picking out parts, e.g. every note with where it is:

```sh
galley feedback plans --json | jq -r '.[] | .path as $file | .items[] | $file + " — " + (.section | join(" › ")) + ": " + .note'
```

## Act on it

- Each item points at a passage in that file. Find it, and change the
  file to do what the note asks. A highlight without a note means "look
  at this again": reconsider the passage, and say what you did.
- Work through every item, then tell the user briefly what you changed for
  each, by its number.
- Passages you rewrite drop out of `galley feedback` by themselves (Galley
  shows them to the user as likely addressed), so running it again shows
  what is left.

## Wait for it

When the user asks you to wait for their feedback, or to keep watching
for it, let `galley` wait — never poll in a loop of your own:

```sh
galley feedback path --wait                 # blocks until the next save, prints it, exits
galley feedback path --wait --timeout 1800  # gives up after 30 minutes (exit status 2)
galley feedback path --watch                # prints every save as it happens, until stopped
```

Both print only what that save added, in the same form as above (one
JSON array per line with `--json`). Point them at the folder you are
working in, or the one the user named.

- **Once** ("tell me when I've left feedback"): run `--wait` in the
  background, and act on its output when it exits.
- **Every round** ("keep watching for my feedback"): stream `--watch`
  with a monitor if your tool has one (each save arrives as one event),
  or re-run `--wait` after acting on each round. When a monitor expires
  and you start it again, run `galley feedback path` once first: a save
  made while nothing was watching is not printed later.

Act on each round as below, clear what you finished, and say briefly
what you did — the user is reading along in Galley.

## Clear it when you are done

```sh
galley feedback clear path/to/file.md            # all feedback on a file
galley feedback clear path/to/folder             # on every file under a folder
galley feedback clear path/to/file.md --addressed  # only passages you rewrote
```

Clear a file's feedback once you have dealt with every item on it, and
only the files you worked on — clearing is not undoable. Clearing takes
only saved feedback; the user's drafts stay. If you left an
item open (a question back to the user, a change you disagreed with), use
`--addressed`, or leave that file alone and say so. Never edit Galley's
own data any other way.

## If `galley` is not found

Ask the user to choose **Galley → Install Command Line Tool…**, or to run
`/Applications/Galley.app/Contents/MacOS/Galley --cli install`.
