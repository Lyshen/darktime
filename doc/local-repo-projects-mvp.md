# Local Repo Projects MVP

## Product Shape

A Project is a sustained attention container.

For the current MVP, the first concrete Project type is a local git repository.

Darktime does not try to replace GitHub Projects. It uses local repo activity as one useful signal:

```text
I say this project matters.
Did I actually produce output here recently?
```

## Project Identity

Project identity is the stable `project.id`.

```text
title     -> short display name, defaults to the local repo name
intention -> why this project deserves attention
```

The title can stay practical. The intention carries the attention meaning.

Local repo projects can be edited:

```text
Edit   -> update title and intention
Remove -> remove the project from Attention only
```

Remove does not delete the local repository.

## Issue To Project

An Issue can become a Project by linking a local repo:

```text
Issue text -> project intention
Repo name  -> project title
Issue      -> done
```

The Issue is marked done because its meaning has moved into the Project.

## Output Trace

The first supported trace source is local git:

```text
last commit time
latest commit message
commits in last 2 days
commits in last 7 days
commits in last 30 days
cached commit output traces
```

Swift code uses `projectId`. SQLite still stores this in the historical `output_traces.root_id` column for compatibility.

## Project Activity States

```text
alive    -> output in last 2 days
quiet    -> output within 7 days
fading   -> output within 30 days
inactive -> output older than 30 days
empty    -> no output trace yet
```

Each project row shows one output-count window:

```text
alive    -> commits in 2d
quiet    -> commits in 7d
fading   -> commits in 30d
inactive -> commits in 30d
empty    -> 0 in 30d
```

These states are not a score. They are a quiet way to see what has actually received attention.

## Attention View

Attention has two modes:

```text
Items    -> Projects + Issues
Timeline -> Project output distribution
```

The Items lens:

```text
Current  -> alive, quiet, empty projects and fresh issues
Fading   -> fading projects and stale issues
Inactive -> inactive projects
All      -> every issue and project
```

## Timeline

Timeline uses cached `output_traces`. It does not run git commands from the SwiftUI view.

Timeline ranges:

```text
48H -> hourly buckets
7D  -> daily buckets
30D -> daily buckets
90D -> weekly buckets
1Y  -> ten-day buckets
```

The goal is not precise accounting. The goal is to make output distribution visible.

## Out Of Scope

- GitHub OAuth.
- GitHub issues / PRs / stars.
- Project detail.
- Issue decomposition.
- Manual output logs.
- AI review.
- Automatic issue-to-project conversion.
- Cloud sync.
