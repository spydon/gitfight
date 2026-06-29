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
const MAX_COMMITS = 20000;
const TTL_MS = 6 * 60 * 60 * 1000; // Re-fetch a repository at most every 6h.

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
  const res = await fetch(url, { headers: { Accept: "application/json", ...headers } });
  if (res.status === 404) throw new FetchError("Repository not found (is it public?).", 404);
  if (res.status === 403 || res.status === 429) {
    throw new FetchError("Rate limited by the host, try again later.", 429);
  }
  if (!res.ok) throw new FetchError(`Host returned status ${res.status}.`, 502);
  return res.json();
}

function githubHeaders(): Record<string, string> {
  const token = Deno.env.get("GITHUB_TOKEN");
  return token ? { Authorization: `Bearer ${token}` } : {};
}

async function fetchGitHub(repo: Repo): Promise<Commit[]> {
  const commits: Commit[] = [];
  for (let page = 1; commits.length < MAX_COMMITS; page++) {
    const url =
      `https://api.github.com/repos/${repo.owner}/${repo.name}/commits` +
      `?per_page=${PER_PAGE}&page=${page}`;
    let list: any[];
    try {
      list = await getJson(url, githubHeaders());
    } catch (e) {
      if (e instanceof FetchError && e.status === 429 && commits.length > 0) break;
      throw e;
    }
    if (list.length === 0) break;
    for (const item of list) {
      const author = item.commit?.author ?? {};
      const ghUser = item.author ?? null;
      const name: string = ghUser?.login ?? author.name ?? "unknown";
      const email: string = author.email ?? name;
      commits.push({
        name,
        key: email.toLowerCase(),
        date: author.date,
        profileUrl: ghUser?.html_url ?? null,
      });
    }
    if (list.length < PER_PAGE) break;
  }
  return commits;
}

async function fetchGitLab(repo: Repo): Promise<Commit[]> {
  const encoded = encodeURIComponent(repo.owner);
  const commits: Commit[] = [];
  for (let page = 1; commits.length < MAX_COMMITS; page++) {
    const url =
      `https://gitlab.com/api/v4/projects/${encoded}/repository/commits` +
      `?per_page=${PER_PAGE}&page=${page}`;
    let list: any[];
    try {
      list = await getJson(url);
    } catch (e) {
      if (e instanceof FetchError && e.status === 429 && commits.length > 0) break;
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
  return commits;
}

async function fetchBitbucket(repo: Repo): Promise<Commit[]> {
  const commits: Commit[] = [];
  let url: string | null =
    `https://api.bitbucket.org/2.0/repositories/${repo.owner}/${repo.name}/commits?pagelen=${PER_PAGE}`;
  while (url && commits.length < MAX_COMMITS) {
    let body: any;
    try {
      body = await getJson(url);
    } catch (e) {
      if (e instanceof FetchError && e.status === 429 && commits.length > 0) break;
      throw e;
    }
    for (const item of body.values ?? []) {
      const author = item.author ?? {};
      const user = author.user ?? null;
      const raw: string = author.raw ?? "unknown";
      const lt = raw.indexOf("<");
      const gt = raw.indexOf(">");
      const email = lt >= 0 && gt > lt ? raw.slice(lt + 1, gt) : raw;
      const name: string =
        user?.nickname ?? user?.display_name ?? (lt > 0 ? raw.slice(0, lt).trim() : raw.trim());
      commits.push({
        name,
        key: email.toLowerCase(),
        date: item.date,
        profileUrl: user?.links?.html?.href ?? null,
      });
    }
    url = body.next ?? null;
  }
  return commits;
}

async function fetchCommits(repo: Repo): Promise<Commit[]> {
  switch (repo.host) {
    case "github":
      return fetchGitHub(repo);
    case "gitlab":
      return fetchGitLab(repo);
    case "bitbucket":
      return fetchBitbucket(repo);
  }
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  try {
    const repo = parseRepo((await req.json())?.url);
    const supabase = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    );

    // Count this launch (one bump per "Launch" press, cache hit or miss).
    const { data: launches } = await supabase.rpc("increment_launches");

    const { data: cached } = await supabase
      .from("repo_cache")
      .select("commits, fetched_at")
      .eq("repo_key", repo.key)
      .maybeSingle();

    if (cached && Date.now() - new Date(cached.fetched_at).getTime() < TTL_MS) {
      return json({ commits: cached.commits, cached: true, launches });
    }

    const commits = await fetchCommits(repo);
    if (commits.length === 0) {
      throw new FetchError("No commits found for this repository.", 404);
    }
    commits.sort((a, b) => a.date.localeCompare(b.date));

    await supabase.from("repo_cache").upsert({
      repo_key: repo.key,
      host: repo.host,
      commits,
      commit_count: commits.length,
      fetched_at: new Date().toISOString(),
    });

    return json({ commits, cached: false, launches });
  } catch (e) {
    const status = e instanceof FetchError ? e.status : 500;
    return json({ error: e instanceof Error ? e.message : String(e) }, status);
  }
});
