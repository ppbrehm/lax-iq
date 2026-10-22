-- Run this in Supabase Dashboard -> SQL Editor
-- Required by App Store review for any app with account creation: lets a
-- signed-in user permanently delete their own account from within the app.

-- Removes the caller's own team memberships and any invite claims under their
-- name, then deletes their auth.users row. Deliberately does NOT touch team-
-- level data (teams, games, rosters, saved plays) since those are shared with
-- other coaches on the team and should survive one coach leaving.
create or replace function delete_own_account()
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  delete from team_members where user_id = auth.uid();
  update invited_emails set claimed_by = null, claimed_at = null where claimed_by = auth.uid();
  delete from invited_emails where invited_by = auth.uid() and claimed_by is null;
  delete from auth.users where id = auth.uid();
end;
$$;

grant execute on function delete_own_account() to authenticated;
