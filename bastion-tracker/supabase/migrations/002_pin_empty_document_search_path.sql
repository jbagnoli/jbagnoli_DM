-- The body of empty_document is unchanged. Pinning search_path stops the
-- function from following a role's search_path. Built-in functions are still
-- found in pg_catalog, which PostgreSQL searches before this path.
alter function public.empty_document(text) set search_path = public;
