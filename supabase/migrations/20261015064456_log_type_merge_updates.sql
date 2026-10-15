-- #52: log updates to merge rules too. merge_types re-points existing rules
-- (its "on conflict do update", and rules that targeted a type being merged
-- away), and those changes left no change_log row, so group history missed
-- "merged X into Y". log_change records only changed columns and skips
-- no-op updates, so re-merging into the same type logs nothing.
drop trigger log_type_merges on public.type_merges;
create trigger log_type_merges after insert or update or delete on public.type_merges
  for each row execute function public.log_change('type_merge', 'id');
