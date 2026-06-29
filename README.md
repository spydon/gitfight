<div align="center">

# 🚀 Git Fight

**Replay any public git repository as a top-down space battle.**

Each committer gets a spaceship that flies in when they first appear in the
history. Commit near someone else in time and your ships fire at each other,
commit alone and you fire at the planet, score on every hit.

<p>
  <a href="https://flutter.dev"><img alt="Flutter" src="https://img.shields.io/badge/Flutter-02569B?style=for-the-badge&logo=flutter&logoColor=white"></a>
  <a href="https://flame-engine.org"><img alt="Flame" src="https://img.shields.io/badge/Flame-FF5722?style=for-the-badge&logo=flame&logoColor=white"></a>
  <a href="https://supabase.com"><img alt="Supabase" src="https://img.shields.io/badge/Supabase-3FCF8E?style=for-the-badge&logo=supabase&logoColor=white"></a>
  <a href="https://flutterfriends.dev"><img alt="Flutter & Friends" src="https://img.shields.io/badge/Flutter%20%26%20Friends-6FB1E0?style=for-the-badge&logo=flutter&logoColor=white"></a>
</p>

Built with [Flutter](https://flutter.dev), [Flame](https://flame-engine.org)
and [Supabase](https://supabase.com).

</div>

---

> ### 🎟️ Going to [Flutter & Friends](https://flutterfriends.dev)?
> Git Fight was built for the friendliest Flutter conference in Stockholm.
> Use discount code **`COMMUNITY10`** at [flutterfriends.dev](https://flutterfriends.dev).

---

## How it works

- Paste a public repository URL and the history replays from the very first
  commit forwards in time.
- Every committer gets their own spaceship, which flies in the moment they
  first appear in the history and meanders around its own patch of space.
- When two committers commit close to each other in time, their ships turn and
  fire at one another, and both score a point.
- When a committer commits alone, they fire at the big planet in the centre and
  score a point.
- Each ship shows the committer's git nickname and running score, and a
  leaderboard tracks the top committers (click a name to open their profile).
- A committer who goes quiet for three months drives out of the scene, and
  flies back in if they commit again.
- When the history finishes it switches to **live mode** and watches for new
  commits as they land. You can jump to live mode at any time.

It is a single-player visualization, not a multiplayer game. The structure is
inspired by [supaspace](https://github.com/spydon/supaspace).

## Supported hosts

History is read through each host's public, CORS enabled REST API (browsers
cannot clone a repository), so the repository must be public:

- GitHub (`github.com`)
- GitLab (`gitlab.com`, including nested groups)
- Bitbucket (`bitbucket.org`)

The full commit history is fetched per repository (only the committer name,
date and profile link are kept). It streams in oldest first, so the replay
starts almost immediately instead of waiting for the whole history to load.

## Caching

Fetched history is cached in Supabase and shared between visitors: the first
person to request a repository populates the cache, and everyone after them
gets the cached data instead of hitting the host again (refreshed every 6
hours).

Caching runs through the `fetch-repo` Supabase edge function, which is the only
writer to the `repo_cache` table. It fetches commits straight from the canonical
host with the service role key, so clients can read the cache but can never
write to it. This is what stops the cache from being poisoned: a client cannot
inject fake commits or overwrite another repository's entry, because the data
always originates server-side from the real host, keyed by a normalized
repository identifier. Row level security enforces read-only access for clients.

Live mode polling still goes straight to the host, since per-session "what is
new right now" is not worth caching.

The schema lives in `supabase/migrations/` and the function in
`supabase/functions/fetch-repo/`. Set an optional `GITHUB_TOKEN` secret on the
function to raise GitHub's unauthenticated rate limit. If the function is not
deployed, the client falls back to fetching from the host directly.

## Running

```bash
flutter run -d chrome --wasm
```

## Building

The app is compiled to WebAssembly, which runs on the skwasm renderer (with a
CanvasKit fallback):

```bash
flutter build web --wasm
```

## Deployment

Every push to `main` triggers two GitHub Actions:

- [`Deploy web`](.github/workflows/deploy-web.yml) builds the WebAssembly bundle
  and publishes it to the `web` branch.
- [`Deploy Supabase functions`](.github/workflows/deploy-supabase.yml) deploys
  the `fetch-repo` edge function. It needs a `SUPABASE_ACCESS_TOKEN` repository
  secret (create one at https://supabase.com/dashboard/account/tokens).

Database migrations under `supabase/migrations/` are applied by the Supabase
GitHub integration. Edge functions are not covered by that integration, which
is why they are deployed by the action above (or manually with
`supabase functions deploy fetch-repo --no-verify-jwt`).

## Project layout

- `lib/git/` - repository URL parsing, the host REST clients and the Supabase
  cache client.
- `lib/game/` - the Flame game that replays the timeline and tracks scores.
- `lib/components/` - the ships, bullets, planet, explosions and starfield.
- `lib/ui/` - the URL entry screen and the in-game heads-up display.
- `supabase/` - the `repo_cache` migration and the `fetch-repo` edge function.
