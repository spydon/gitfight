// Fetches a public repository's commit history straight from the canonical git
// host, caches the result in `repo_cache`, and serves the cache to everyone who
// later asks for the same repository.
//
// This runs server-side with the service role key, which is the whole point:
// clients never write to the cache themselves, so they cannot poison it. The
// commit data always originates from the real host here, keyed by a normalized
// repository identifier, so a client cannot inject fake commits or overwrite
// another repository's data.

import { createClient } from "jsr:@supabase/supabase-js@2";

const PER_PAGE = 100;
const TTL_MS = 6 * 60 * 60 * 1000; // Re-fetch a repository at most every 6h.
// Small gap between pages so large repos don't trip GitHub's secondary
// (abuse) rate limit, which rejects rapid bursts even with quota left.
const PAGE_DELAY_MS = 250;
const sleep = (ms: number) => new Promise<void>((r) => setTimeout(r, ms));

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

type Host = "github" | "gitlab" | "bitbucket";
interface Repo {
  host: Host;
  owner: string;
  name: string;
  key: string;
}
interface Commit {
  name: string;
  key: string;
  date: string;
  profileUrl: string | null;
}

// `complete` is false when the host rate-limited us before we read every page.
interface FetchResult {
  commits: Commit[];
  complete: boolean;
}

class FetchError extends Error {
  constructor(message: string, readonly status = 400) {
    super(message);
  }
}

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

function parseRepo(rawUrl: unknown): Repo {
  if (typeof rawUrl !== "string" || rawUrl.trim() === "") {
    throw new FetchError("Please provide a repository URL.");
  }
  let url = rawUrl.trim();
  if (!url.includes("://")) url = `https://${url}`;
  let parsed: URL;
  try {
    parsed = new URL(url);
  } catch {
    throw new FetchError("That does not look like a valid URL.");
  }
  const segments = parsed.pathname
    .split("/")
    .filter((s) => s.length > 0)
    .map((s) => (s.endsWith(".git") ? s.slice(0, -4) : s));
  if (segments.length < 2) {
    throw new FetchError("The URL must point to a repository.");
  }
  const host = parsed.host.toLowerCase();
  if (host.includes("github")) {
    return {
      host: "github",
      owner: segments[0],
      name: segments[1],
      key: `github:${segments[0]}/${segments[1]}`.toLowerCase(),
    };
  }
  if (host.includes("gitlab")) {
    const path = segments.join("/");
    return { host: "gitlab", owner: path, name: "", key: `gitlab:${path}`.toLowerCase() };
  }
  if (host.includes("bitbucket")) {
    return {
      host: "bitbucket",
      owner: segments[0],
      name: segments[1],
      key: `bitbucket:${segments[0]}/${segments[1]}`.toLowerCase(),
    };
  }
  throw new FetchError("Unsupported host. Try GitHub, GitLab or Bitbucket.");
}

async function getJson(url: string, headers: Record<string, string> = {}) {
  for (let attempt = 0; ; attempt++) {
    const res = await fetch(url, {
      headers: { Accept: "application/json", ...headers },
    });
    if (res.status === 200) return res.json();
    await res.body?.cancel();
    if (res.status === 404) {
      throw new FetchError("Repository not found (is it public?).", 404);
    }
    if (res.status === 403 || res.status === 429) {
      const remaining = res.headers.get("x-ratelimit-remaining");
      const retryAfter = Number(res.headers.get("retry-after") ?? 0);
      // Primary quota exhausted with no Retry-After: the reset is too far off
      // to wait for. A 403/429 with quota left is a secondary (burst) limit, so
      // back off and retry the same page.
      if ((remaining === "0" && retryAfter === 0) || attempt >= 4) {
        throw new FetchError("Rate limited by the host, try again later.", 429);
      }
      await sleep(Math.min((retryAfter || 2 ** attempt) * 1000, 15000));
      continue;
    }
    throw new FetchError(`Host returned status ${res.status}.`, 502);
  }
}

function githubHeaders(): Record<string, string> {
  const token = Deno.env.get("GITHUB_TOKEN");
  return token ? { Authorization: `Bearer ${token}` } : {};
}

async function fetchGitHub(repo: Repo, since?: string): Promise<FetchResult> {
  const commits: Commit[] = [];
  const sinceParam = since ? `&since=${encodeURIComponent(since)}` : "";
  for (let page = 1; ; page++) {
    if (page > 1) await sleep(PAGE_DELAY_MS);
    const url =
      `https://api.github.com/repos/${repo.owner}/${repo.name}/commits` +
      `?per_page=${PER_PAGE}&page=${page}${sinceParam}`;
    let list: any[];
    try {
      list = await getJson(url, githubHeaders());
    } catch (e) {
      if (e instanceof FetchError && e.status === 429 && commits.length > 0) {
        return { commits, complete: false };
      }
      throw e;
    }
    if (list.length === 0) break;
    for (const item of list) {
      const author = item.commit?.author ?? {};
      const ghUser = item.author ?? null;
      const login: string | null = ghUser?.login ?? null;
      const name: string = login ?? author.name ?? "unknown";
      const email: string = author.email ?? name;
      // Group by the GitHub account so one person committing under several
      // emails is a single committer.
      commits.push({
        name,
        key: (login ?? email).toLowerCase(),
        date: author.date,
        profileUrl: ghUser?.html_url ?? null,
      });
    }
    if (list.length < PER_PAGE) break;
  }
  return { commits, complete: true };
}

async function fetchGitLab(repo: Repo, since?: string): Promise<FetchResult> {
  const encoded = encodeURIComponent(repo.owner);
  const commits: Commit[] = [];
  const sinceParam = since ? `&since=${encodeURIComponent(since)}` : "";
  for (let page = 1; ; page++) {
    if (page > 1) await sleep(PAGE_DELAY_MS);
    const url =
      `https://gitlab.com/api/v4/projects/${encoded}/repository/commits` +
      `?per_page=${PER_PAGE}&page=${page}${sinceParam}`;
    let list: any[];
    try {
      list = await getJson(url);
    } catch (e) {
      if (e instanceof FetchError && e.status === 429 && commits.length > 0) {
        return { commits, complete: false };
      }
      throw e;
    }
    if (list.length === 0) break;
    for (const item of list) {
      const name: string = item.author_name ?? "unknown";
      const email: string = item.author_email ?? name;
      commits.push({
        name,
        key: email.toLowerCase(),
        date: item.committed_date,
        profileUrl: null,
      });
    }
    if (list.length < PER_PAGE) break;
  }
  return { commits, complete: true };
}

async function fetchBitbucket(repo: Repo, since?: string): Promise<FetchResult> {
  const commits: Commit[] = [];
  let complete = true;
  let url: string | null =
    `https://api.bitbucket.org/2.0/repositories/${repo.owner}/${repo.name}/commits?pagelen=${PER_PAGE}`;
  // Bitbucket has no "since" param and returns newest first, so stop paging
  // once we reach commits at or before the cutoff.
  let firstPage = true;
  outer: while (url) {
    if (!firstPage) await sleep(PAGE_DELAY_MS);
    firstPage = false;
    let body: any;
    try {
      body = await getJson(url);
    } catch (e) {
      if (e instanceof FetchError && e.status === 429 && commits.length > 0) {
        complete = false;
        break;
      }
      throw e;
    }
    for (const item of body.values ?? []) {
      if (since && item.date <= since) break outer;
      const author = item.author ?? {};
      const user = author.user ?? null;
      const raw: string = author.raw ?? "unknown";
      const lt = raw.indexOf("<");
      const gt = raw.indexOf(">");
      const email = lt >= 0 && gt > lt ? raw.slice(lt + 1, gt) : raw;
      const account: string | null = user?.nickname ?? user?.display_name ?? null;
      const name: string =
        account ?? (lt > 0 ? raw.slice(0, lt).trim() : raw.trim());
      commits.push({
        name,
        key: (account ?? email).toLowerCase(),
        date: item.date,
        profileUrl: user?.links?.html?.href ?? null,
      });
    }
    url = body.next ?? null;
  }
  return { commits, complete };
}

async function fetchCommits(repo: Repo, since?: string): Promise<FetchResult> {
  switch (repo.host) {
    case "github":
      return fetchGitHub(repo, since);
    case "gitlab":
      return fetchGitLab(repo, since);
    case "bitbucket":
      return fetchBitbucket(repo, since);
  }
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  try {
    const payload = await req.json();
    const repo = parseRepo(payload?.url);
    // cacheOnly returns immediately on a miss so the client can stream from the
    // host instead of waiting for a full server-side fetch. count=false skips
    // the launch counter (used by the background cache fill after a miss).
    const cacheOnly = payload?.cacheOnly === true;
    const shouldCount = payload?.count !== false;
    const supabase = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    );

    let launches: number | null = null;
    if (shouldCount) {
      const { data } = await supabase.rpc("increment_launches");
      launches = data;
    }

    const { data: cached } = await supabase
      .from("repo_cache")
      .select("commits, fetched_at")
      .eq("repo_key", repo.key)
      .maybeSingle();

    if (cached && Date.now() - new Date(cached.fetched_at).getTime() < TTL_MS) {
      return json({ commits: cached.commits, cached: true, launches });
    }

    if (cacheOnly) {
      return json({ cached: false, miss: true, launches });
    }

    // Refresh incrementally: keep the cached commits and only fetch the ones
    // newer than the latest cached commit, then append. A cold cache does a
    // full fetch.
    const existing: Commit[] = Array.isArray(cached?.commits)
      ? cached!.commits
      : [];
    let commits: Commit[];
    // A merge onto an already-complete cache stays complete even if the small
    // "newer" fetch got throttled; a cold fetch is only complete if it read
    // every page.
    let complete: boolean;
    if (existing.length > 0) {
      const since = existing[existing.length - 1].date;
      const result = await fetchCommits(repo, since);
      const fresh = result.commits
        .filter((c) => c.date > since)
        .sort((a, b) => a.date.localeCompare(b.date));
      commits = existing.concat(fresh);
      complete = true;
    } else {
      const result = await fetchCommits(repo);
      commits = result.commits.sort((a, b) => a.date.localeCompare(b.date));
      complete = result.complete;
    }
    if (commits.length === 0) {
      throw new FetchError("No commits found for this repository.", 404);
    }

    // Never poison the cache with a rate-limited partial history; only store a
    // complete one. Partial results are still returned to the caller.
    if (complete) {
      await supabase.from("repo_cache").upsert({
        repo_key: repo.key,
        host: repo.host,
        commits,
        commit_count: commits.length,
        fetched_at: new Date().toISOString(),
      });
    }

    return json({ commits, cached: false, complete, launches });
  } catch (e) {
    const status = e instanceof FetchError ? e.status : 500;
    return json({ error: e instanceof Error ? e.message : String(e) }, status);
  }
});
