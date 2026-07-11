# Local Repo Rootbox MVP

## Product Shape

Rootbox is not a task list or a permanent archive.

For this MVP, a Root is a container for something worth sustained attention.

Root identity is the stable `root.id`.

```text
title     -> short display name, defaults to the local repo name
intention -> why this root deserves attention
```

The title can be practical and short. The intention carries the attention meaning.

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
local uncommitted changes
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
working  -> local uncommitted changes, shown as a separate signal
alive    -> commit in last 2 days
quiet    -> last commit within 7 days
fading   -> last commit within 30 days
withered -> last commit older than 30 days
seed     -> repo has no commits yet
```

Seeds use simple age rules:

```text
seed   -> touched within 7 days
fading -> untouched for more than 7 days
```

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
- No GitHub account or network access is required.
