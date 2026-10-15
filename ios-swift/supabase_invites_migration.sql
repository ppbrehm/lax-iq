-- Run this in Supabase Dashboard -> SQL Editor

create table if not exists invited_emails (
  id uuid primary key default gen_random_uuid(),
  email text not null,
  team_id uuid not null references teams(id) on delete cascade,
  role text not null check (role in ('head_coach', 'assistant_coach')),
  invited_by uuid references auth.users(id),
  claimed_by uuid references auth.users(id),
  claimed_at timestamptz,
  created_at timestamptz not null default now()
);

create unique index if not exists invited_emails_email_team_unique
  on invited_emails (lower(email), team_id);

-- Lets an unauthenticated signup screen check invite eligibility without
-- exposing the whole table (SECURITY DEFINER bypasses RLS for this lookup only).
create or replace function check_invite(p_email text)
returns table(team_id uuid, role text)
language sql
security definer
set search_path = public
as $$
  select team_id, role from invited_emails
  where lower(email) = lower(p_email) and claimed_at is null
  limit 1;
$$;

grant execute on function check_invite(text) to anon, authenticated;

-- Avoids RLS self-recursion on team_members (a common Postgres/Supabase gotcha).
create or replace function is_team_member(p_team_id uuid)
returns boolean
language sql
security definer
set search_path = public
as $$
  select exists (
    select 1 from team_members where team_id = p_team_id and user_id = auth.uid()
  );
$$;

create or replace function is_team_head_coach(p_team_id uuid)
returns boolean
language sql
security definer
set search_path = public
as $$
  select exists (
    select 1 from team_members
    where team_id = p_team_id and user_id = auth.uid() and role = 'head_coach'
  );
$$;

alter table teams enable row level security;
alter table team_members enable row level security;
alter table invited_emails enable row level security;

drop policy if exists "owner can create teams" on teams;
create policy "owner can create teams" on teams
  for insert
  with check (auth.jwt() ->> 'email' = 'ppbrehm@gmail.com');

drop policy if exists "members and owner can view teams" on teams;
create policy "members and owner can view teams" on teams
  for select
  using (
    auth.jwt() ->> 'email' = 'ppbrehm@gmail.com'
    or is_team_member(id)
  );

drop policy if exists "members can view their team roster" on team_members;
create policy "members can view their team roster" on team_members
  for select
  using (is_team_member(team_id));

drop policy if exists "owner can view all team members" on team_members;
create policy "owner can view all team members" on team_members
  for select
  using (auth.jwt() ->> 'email' = 'ppbrehm@gmail.com');

drop policy if exists "user can join own invited team" on team_members;
create policy "user can join own invited team" on team_members
  for insert
  with check (
    user_id = auth.uid()
    and exists (
      select 1 from invited_emails ie
      where ie.team_id = team_members.team_id
        and lower(ie.email) = lower(auth.jwt() ->> 'email')
        and (ie.claimed_by is null or ie.claimed_by = auth.uid())
    )
  );

drop policy if exists "head coach can manage roles" on team_members;
create policy "head coach can manage roles" on team_members
  for update
  using (is_team_head_coach(team_id))
  with check (is_team_head_coach(team_id));

drop policy if exists "head coach can remove members" on team_members;
create policy "head coach can remove members" on team_members
  for delete
  using (is_team_head_coach(team_id));

drop policy if exists "owner or head coach can invite" on invited_emails;
create policy "owner or head coach can invite" on invited_emails
  for insert
  with check (
    auth.jwt() ->> 'email' = 'ppbrehm@gmail.com'
    or is_team_head_coach(team_id)
  );

drop policy if exists "owner or head coach can view invites" on invited_emails;
create policy "owner or head coach can view invites" on invited_emails
  for select
  using (
    auth.jwt() ->> 'email' = 'ppbrehm@gmail.com'
    or is_team_head_coach(team_id)
  );

drop policy if exists "user can claim own invite" on invited_emails;
create policy "user can claim own invite" on invited_emails
  for update
  using (lower(email) = lower(auth.jwt() ->> 'email'))
  with check (claimed_by = auth.uid());
