# Git tab

The bottom panel's **Git** tab works with the project's git repository: what
changed (a scene shown by node), staging and committing, branches, syncing
with the remote, and history. It runs the `git` installed on your computer,
so what it does is ordinary git: anything else you do in a terminal or
another git app shows here too.

## When to use it

- See what you changed in a scene before you commit: which nodes, which
  fields, from what to what.
- Commit, switch branches, pull and push without leaving the editor.
- See who changed a scene and when.

## What's in it

A project that isn't in a repository shows **Create Repository** (`git init`
in the project's folder). If git isn't installed, the tab says so.

### The header

| | |
|---|---|
| Branch | The current branch. Pick another to switch to it, or type a name under it and **Create** to start a new one. Save (or revert) your scenes first: switching changes the files on disk. |
| Upstream | The branch it tracks and how many commits you're **ahead** (yours, not pushed) and **behind** (theirs, not pulled). |
| **Fetch** | Get the remote's commits without changing anything here. |
| **Pull** | Fetch and merge them. Save your scenes first. Scenes merge by node once **Tools > Set Up Scene Merging** ran ([Working in a team](team.md#merging-scenes)). |
| **Push** | Send your commits to the remote. A branch without an upstream is pushed to `origin` and set to track it. |
| Refresh | Read the status again (the tab also does every few seconds). |

Fetch, pull and push run in the background, and the editor keeps running.
Git never asks for a password here: set up a credential helper or an SSH key,
or push once from a terminal.

After a pull or a branch switch the scene open in the viewport is read again.
Other open tabs show the files as they were until you close and reopen them.

### Changes

The project's changed files: **new**, **changed**, **deleted**, **renamed**,
or **conflict** (a merge to finish: see [Merge
conflicts](team.md#merge-conflicts)).

- Tick a file to stage it (it goes into the next commit), untick to unstage.
  **Stage All** stages every change in the project's folder.
- Write a message and **Commit**. Only staged files are committed, as they
  are on disk, so save your scenes first.
- Select a file to see its changes on the right. A scene or component shows
  **by node**: each node added, removed, moved (from which parent to which)
  or changed, with every changed field and its old and new value. Other files
  show git's text diff. A scene saved before nodes had uids also shows as
  text: save it once in the editor.

### History

The last 100 commits of the selected file (**Whole Project** for all of the
project's), with each commit's message, author and age.

## Tips

- Commit often, with scenes saved: a commit is what's on disk.
- Before a pull, commit or save your work: a pull that merges needs clean
  files.
- The `.merge.json` files the scene merge writes during a conflict aren't
  listed; the Merge Conflicts window handles them.

## Related

- [Working in a team](team.md): small diffs, merging scenes, conflicts
- [Toolbar and menus](toolbar-menus.md)
