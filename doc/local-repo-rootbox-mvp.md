# Local Repo Rootbox MVP

## Product Shape

Rootbox is not a task list or a permanent archive.

For this MVP, a Root is a container for something worth sustained attention.

Rootbox's default view is the user's current attention model. It should not show every old project by default.

Root identity is the stable `root.id`.

```text
title     -> short display name, defaults to the local repo name
intention -> why this root deserves attention
```

The title can be practical and short. The intention carries the attention meaning.

Local Repo Roots can be edited after creation:

```text
Edit   -> update title and intention
Remove -> remove the root from Rootbox only
```

Remove does not delete the local repository.

There are two visible forms:

```text
Local Repo Root
Seed
```

## Local Repo Root

A Local Repo Root is a project that already has external traces.

The first supported trace source is a local git repository.

Darktime does not connect to GitHub in this MVP. It reads local git history only:

```text
last commit time
latest commit message
commits in last 7 days
commits in last 30 days
```

This keeps the first Rootbox version local-first and avoids OAuth, tokens, and cloud permissions.

## Seed

A Seed is a matter kept from Inbox into Rootbox.

It is not a full project yet. It is an idea or concern that felt worth returning to.

Seed behavior:

```text
recently kept -> seed
untouched for a while -> fading
```

The point is not to punish inactivity. The point is to make attention visible:

```text
This thing entered Rootbox. Has it grown any real trace?
```

When a Seed is linked to a local repo:

```text
title     -> defaults to the repo name
intention -> defaults to the seed text
```

The seed matter is then marked done, because its meaning has moved into the Root.

## States

Local repo roots use simple state rules:

```text
alive    -> commit in last 2 days
quiet    -> last commit within 7 days
fading   -> last commit within 30 days
withered -> last commit older than 30 days
seed     -> repo has no commits yet
```

Each repo row shows only one commit-count window:

```text
alive    -> commits in 2d
quiet    -> commits in 7d
fading   -> commits in 30d
withered -> commits in 30d
```

Seeds use simple age rules:

```text
seed   -> touched within 7 days
fading -> untouched for more than 7 days
```

## Visibility

Rootbox uses a quiet lens menu:

```text
Current  -> alive, quiet, fresh seeds
Fading   -> fading projects
Withered -> withered projects
All      -> every root and seed
```

The default lens is `Current`.

Fading and withered roots are not counted or pushed into the main view. They stay available for review only when the user chooses to look.

Local uncommitted changes are intentionally not shown in the main Rootbox view yet. Rootbox should reflect attention traces, not become a git status panel.

Maintenance actions are hover-only. The row should stay quiet unless the user is intentionally managing it.

## Why This MVP

The first question Rootbox should answer is:

```text
What is actually alive in my attention?
```

For the initial user, local repos are already real life containers:

```text
darktime
selfzen
xrobotd
```

Git commits are not the whole truth, but they are a useful action signal.

Darktime should not copy GitHub's green-dot anxiety. It should show which roots are alive, quiet, fading, withered, or still just seeds.

## Out Of Scope

- GitHub OAuth.
- GitHub issues / PRs / stars.
- AI review.
- Habit design.
- Project planning.
- Automatic seed-to-root conversion.
- Cloud sync.

## Acceptance Criteria

- The user can add a local git repository from Rootbox.
- Rootbox shows local repo roots and seed matters separately.
- Repo roots show recent action signals.
- Existing Rootbox matters remain visible as seeds.
- Current view only shows alive/quiet roots and fresh seeds.
- Fading and withered roots are hidden behind the lens filter.
- Repo roots can be edited without changing the local repository.
- Repo roots can be removed from Rootbox without deleting local files.
- No GitHub account or network access is required.
