-- touch_updated: only record "last edited by" for users who still exist.
-- When an account is deleted, clearing its "who did it" columns updates rows
-- as that (now deleted) user; stamping their id back broke the foreign key.
create or replace function public.touch_updated() returns trigger
language plpgsql as $$
begin
  new.updated_at := now();
  new.updated_by := case
    when exists (select 1 from public.profiles where id = auth.uid()) then auth.uid()
  end;
  return new;
end $$;
