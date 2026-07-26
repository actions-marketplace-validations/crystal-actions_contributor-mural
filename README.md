# hall-of-fame

Generate avatar-wall art for your repository — a "hall of fame" of the people who make your project happen. Ships as a GitHub Action (written in [Crystal](https://crystal-lang.org)) that renders your list of users, your contributors, or both into embeddable SVG art and commits it to your repository.

| Grid | Honeycomb | Mosaic |
| :--: | :-------: | :----: |
| ![grid](examples/grid.svg) | ![honeycomb](examples/honeycomb.svg) | ![mosaic](examples/mosaic.svg) |

*(Curated samples from [`examples/showcase.yml`](examples/showcase.yml). This repository also runs the action on itself every week — the live result lands in [`docs/`](docs/).)*

- **Three styles** — classic grid (circle/rounded/square), honeycomb hexagons, and a weight-tiered mosaic where your top contributors literally loom larger.
- **Many sources, one wall** — your curated `users` list, repository contributors, org members, stargazers, and GitHub Sponsors (tier amounts become weights). Mix freely; your YAML entries always win.
- **Sections & roles** — split the wall into titled groups (say, *Contributors* and *Special Thanks*) and tag people with a role line (*Creator*, *Design*, *Docs*) — made for honoring the folks the contributors API can't see.
- **Adapts to GitHub dark mode** — by default the SVG carries both palettes and follows the viewer's theme. Pick a `preset` (`github`, `midnight`, `paper`, `mono`) or tune every color for light and dark separately.
- **SVG and PNG** — self-contained SVGs (avatars embedded as base64, so they render inside READMEs) plus rasterized PNGs for places SVG can't go, including light/dark pairs.
- **Local avatars** — point `avatar_url` at a file in your repository for logos or people without a GitHub account.

## Quick start

Create `.github/hall-of-fame.yml`:

```yaml
source: both              # my list + repository contributors
style: grid
output: HALL_OF_FAME.svg  # or drop this and use `outputs:` for several files

users:
  - login: hahwul
    name: HAHWUL
    weight: 10

exclude:
  - dependabot[bot]
```

Add a workflow, e.g. `.github/workflows/hall-of-fame.yml`:

```yaml
name: Hall of Fame
on:
  workflow_dispatch:
  schedule:
    - cron: "0 3 * * 0"

permissions:
  contents: write

concurrency:
  group: hall-of-fame

jobs:
  generate:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v5
      - uses: crystal-actions/hall-of-fame@v0
```

Then embed the result in your README:

```markdown
![Hall of Fame](HALL_OF_FAME.svg)
```

## Action inputs

| Input | Default | Description |
| ----- | ------- | ----------- |
| `config` | `.github/hall-of-fame.yml` | Path to the config YAML, relative to the repository root |
| `token` | `${{ github.token }}` | GitHub API token. Required for `sponsors`; also lifts rate limits and reaches private repos for the other API sources |
| `no_commit` | `false` | Generate files but skip commit/push (must be `true` or `false`) |
| `commit_message` | `chore: update hall of fame` | Commit message |

Outputs: `paths` (comma-separated generated files, SVG and PNG), `user_count`, and `changed` (whether a commit was pushed; `false` when `no_commit` is set). `svg_path` still works as an alias for `paths`.

## Configuration

Everything about the art lives in the config YAML:

```yaml
source: list                # list | contributors | both (default: list)
style: grid                 # grid | honeycomb | mosaic (default: grid)
output: HALL_OF_FAME.svg    # path relative to the repository root

users:                      # your curated list (source: list/both)
  - login: hahwul           # required — GitHub login
    name: HAHWUL            # optional display name (default: login)
    weight: 10              # optional, drives mosaic sizing + weight sort
    role: Creator           # optional label under the name (grid) / in tooltips
    group: Contributors     # optional section this user renders in
    link: https://hahwul.com          # optional (default: the GitHub profile)
    avatar_url: https://…/custom.png  # optional override; also accepts a
                                      # repo-relative file (assets/logo.png)

groups: [Contributors, Special Thanks]  # optional: section order (and typo guard)

contributors:               # used when source is contributors/both
  repo: owner/name          # default: the current repository
  include_bots: false       # keep type=Bot / *[bot] accounts
  include_anonymous: false  # include anonymous (email-only) contributors
  max: 100                  # cap fetched contributors; contributions become weight
  group: Contributors       # optional section for API-fetched users

members:                    # optional: organization members (presence enables)
  org: crystal-actions
  max: 100
  group: Team

stargazers:                 # optional: the repo's stargazers
  repo: owner/name          # default: the current repository
  max: 100
  group: Stargazers

sponsors:                   # optional: GitHub Sponsors (needs a token; GraphQL)
  login: hahwul             # default: the repository owner
  max: 100                  # tier $/month becomes each sponsor's weight
  group: Sponsors

exclude:                    # drop logins from any source
  - dependabot[bot]

sort: weight                # weight | login | none (none keeps list order)
limit: 60                   # cap rendered users after merge/sort
fail_on_missing: false      # true: fail the run when an avatar can't be fetched

outputs:                    # optional: render several files in one run
  - path: docs/wall-grid.svg
  - path: docs/wall-hex.svg
    style: honeycomb
  - path: docs/wall.png     # .png outputs are rasterized (see `png` below)
    mode: dark              # optional per-output light/dark override

grid:
  columns: 8
  avatar_size: 64
  shape: circle             # circle | rounded | square
  margin: 8
  show_names: true
  truncate: 12              # max name length (0 = no truncation)

honeycomb:
  columns: 9
  cell_size: 72
  gap: 4

mosaic:
  width: 800
  base_cell: 48
  tiers: [3, 2, 1]          # cell spans per weight tier (top tier first)
  gap: 2

theme:
  preset: github            # github | midnight | paper | mono
  mode: auto                # auto (follows the viewer's dark mode) | light | dark
  background: transparent   # light-palette overrides on top of the preset
  label_color: "#57606a"
  role_color: "#6e7781"     # the role line under names
  title_color: "#24292f"    # section titles
  dark:                     # dark-palette overrides
    label_color: "#8b949e"
  font_family: "-apple-system, 'Segoe UI', Helvetica, Arial, sans-serif"

png:
  scale: 2                  # rasterization zoom for .png outputs
```

When `source: both`, your `users` entries win over API data field by field — set a custom `name` or `weight` while the contribution count fills everyone else's. Placement is always yours: an entry without `group` renders in the untitled leading section even if the API put that person in one, so add `group:` when you want them filed under a heading. Someone returned by more than one API source (a contributor who also sponsors) appears once, keeping the highest weight and the first source's group.

This is the recipe for honoring people the API misses — unlinked commit emails, design or docs work: add them to `users` with a `role` and their own section.

## Notes

- A config file is required; the action fails if `.github/hall-of-fame.yml` (or the path you pass as `config`) does not exist.
- The workflow needs `permissions: contents: write` to push the generated file, and a `concurrency` group avoids racing pushes on busy repositories.
- Avatars link to profiles and carry name/role tooltips, but a README embed (`![](wall.svg)`) renders as an `<img>`, where neither is active. Open the SVG directly — or inline it — to get links.
- `members` returns public organization members only; a token with `read:org` is needed for the rest. Stargazers arrive oldest-first with no weight, so under the default `sort: weight` they trail contributors — use `sort: none` to keep the API order.
- On `pull_request` events the checkout is a detached HEAD, so pushes fail — use push/schedule/dispatch triggers, or set `no_commit: true` and handle the file yourself.
- SVG size grows with user count (roughly 5–15 KB per avatar). Use `limit` and moderate avatar sizes for large walls.
- With `mode: auto` (the default) the SVG contains both palettes and a `prefers-color-scheme` media query, so it follows GitHub's light/dark theme. PNGs can't adapt, so `.png` outputs pin `auto` to the light palette — add a second output with `mode: dark` for a pair.
- PNG output uses `rsvg-convert`, bundled in the action image. For local runs install librsvg (`brew install librsvg` / `apt install librsvg2-bin` / `apk add rsvg-convert`).
- `sponsors` always needs a `token` (GraphQL API); the default `github.token` works for public sponsor lists.

## CLI

The action binary is also a local CLI:

```bash
shards build --release
bin/hall-of-fame --config examples/showcase.yml   # regenerates the committed examples/*.svg
bin/hall-of-fame -c my.yml --commit               # opt in to commit/push locally
```

`--config` is resolved against the current directory, while output paths and local `avatar_url` files are resolved against `--workspace` (the current directory by default; `GITHUB_WORKSPACE` inside the action). Committing happens automatically when `GITHUB_ACTIONS=true` — including on runners that emulate it, such as act or Forgejo — and otherwise only with `--commit`.

## Development

```bash
shards install
crystal spec                    # unit + golden-file specs (no network)
UPDATE_GOLDEN=1 crystal spec    # regenerate golden SVGs after renderer changes
crystal tool format
bin/ameba src spec
```

Release flow: pushing a `vX.Y.Z` tag builds a multi-arch image to `ghcr.io/crystal-actions/hall-of-fame` and force-moves the major tag (`v0`, `v1`, …). The image is pushed before the git tag moves, so the moving tag always references an existing image.

While the repository is private, `action.yml` still uses `image: Dockerfile`, so consumers build the image on their runner (roughly a minute on a cold cache) and the published GHCR image is not used yet. Switching `action.yml` to `docker://ghcr.io/crystal-actions/hall-of-fame:v0` is part of going public — runners pull GHCR anonymously, which only works once the package is public.

## License

MIT — see [LICENSE](LICENSE).
