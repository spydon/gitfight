-- The committer identity key changed (now grouped by host account instead of
-- email), so any history cached under the old format would keep its old keys
-- because the cache is now refreshed incrementally. Clear it once so every
-- repository re-populates with the new identity keys; future refreshes only
-- append newer commits.
delete from public.repo_cache;
