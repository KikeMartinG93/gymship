-- Gymship Supabase schema
-- Run in the Supabase SQL editor (Project → SQL Editor → New query).
-- Designed for the free tier: no extensions beyond pgcrypto (bundled).

create extension if not exists pgcrypto;

-- ---------------------------------------------------------------------------
-- profiles: one row per authenticated user (Sign in with Google is used by the app)
-- ---------------------------------------------------------------------------
create table if not exists public.profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  handle text not null unique,
  name text not null,
  created_at timestamptz not null default now(),
  constraint handle_format check (handle ~ '^[a-z0-9_]{3,20}$')
);

alter table public.profiles enable row level security;

create policy "profiles are readable by any authenticated user"
  on public.profiles for select
  to authenticated
  using (true);

create policy "users can insert their own profile"
  on public.profiles for insert
  to authenticated
  with check (auth.uid() = id);

create policy "users can update their own profile"
  on public.profiles for update
  to authenticated
  using (auth.uid() = id);

-- ---------------------------------------------------------------------------
-- groups: up to 5 members, joined via invite_code
-- ---------------------------------------------------------------------------
create table if not exists public.groups (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  owner_id uuid not null references public.profiles (id) on delete cascade,
  invite_code text not null unique,
  created_at timestamptz not null default now(),
  -- Default length for this group's workouts: 60 (1hr), 120 (2hr), or 150 (2.5hr) minutes.
  workout_duration_minutes integer not null default 60,
  constraint workout_duration_allowed check (workout_duration_minutes in (60, 120, 150)),
  -- Where this group works out — geocoded once and reused to calculate
  -- everyone's ETA once a workout is committed to.
  gym_address text,
  gym_latitude double precision,
  gym_longitude double precision
);

alter table public.groups enable row level security;

create policy "groups are readable by any authenticated user"
  on public.groups for select
  to authenticated
  using (true);

create policy "authenticated users can create groups"
  on public.groups for insert
  to authenticated
  with check (auth.uid() = owner_id);

drop policy if exists "group members can update their groups" on public.groups;
create policy "group members can update their groups"
  on public.groups for update
  to authenticated
  using (
    exists (
      select 1 from public.group_members gm
      where gm.group_id = groups.id
        and gm.user_id = auth.uid()
    )
  );

-- ---------------------------------------------------------------------------
-- group_members: join table, capped at 5 rows per group_id via trigger
-- ---------------------------------------------------------------------------
create table if not exists public.group_members (
  id uuid primary key default gen_random_uuid(),
  group_id uuid not null references public.groups (id) on delete cascade,
  user_id uuid not null references public.profiles (id) on delete cascade,
  joined_at timestamptz not null default now(),
  unique (group_id, user_id)
);

alter table public.group_members enable row level security;

create policy "group members are readable by any authenticated user"
  on public.group_members for select
  to authenticated
  using (true);

create policy "users can add themselves to a group"
  on public.group_members for insert
  to authenticated
  with check (auth.uid() = user_id);

create or replace function public.enforce_group_member_limit()
returns trigger as $$
begin
  if (select count(*) from public.group_members where group_id = new.group_id) >= 5 then
    raise exception 'Group already has the maximum of 5 members';
  end if;
  return new;
end;
$$ language plpgsql security definer;

drop trigger if exists trg_enforce_group_member_limit on public.group_members;
create trigger trg_enforce_group_member_limit
  before insert on public.group_members
  for each row execute function public.enforce_group_member_limit();

-- ---------------------------------------------------------------------------
-- busy_slots: per-user busy time blocks, scoped to a group, synced from
-- EventKit-derived DateIntervals on each member's device
-- ---------------------------------------------------------------------------
create table if not exists public.busy_slots (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles (id) on delete cascade,
  group_id uuid references public.groups (id) on delete cascade,
  starts_at timestamptz not null,
  ends_at timestamptz not null,
  updated_at timestamptz not null default now(),
  constraint valid_range check (ends_at > starts_at)
);

create index if not exists busy_slots_group_id_idx on public.busy_slots (group_id);
create index if not exists busy_slots_user_id_idx on public.busy_slots (user_id);

alter table public.busy_slots enable row level security;

create policy "busy slots are readable by members of the same group"
  on public.busy_slots for select
  to authenticated
  using (
    group_id is null
    or exists (
      select 1 from public.group_members gm
      where gm.group_id = busy_slots.group_id
        and gm.user_id = auth.uid()
    )
  );

create policy "users manage their own busy slots"
  on public.busy_slots for insert
  to authenticated
  with check (auth.uid() = user_id);

create policy "users update their own busy slots"
  on public.busy_slots for update
  to authenticated
  using (auth.uid() = user_id);

create policy "users delete their own busy slots"
  on public.busy_slots for delete
  to authenticated
  using (auth.uid() = user_id);

-- ---------------------------------------------------------------------------
-- workout_proposals: a proposed workout slot for a specific group
-- ---------------------------------------------------------------------------
create table if not exists public.workout_proposals (
  id uuid primary key default gen_random_uuid(),
  group_id uuid not null references public.groups (id) on delete cascade,
  created_by uuid not null references public.profiles (id) on delete cascade,
  title text not null default 'Workout',
  starts_at timestamptz not null,
  ends_at timestamptz not null,
  created_at timestamptz not null default now(),
  -- true when this was auto-generated by the on-device Apple Intelligence
  -- slot finder rather than proposed manually by a member.
  is_suggested boolean not null default false,
  constraint valid_proposal_range check (ends_at > starts_at)
);

create index if not exists workout_proposals_group_id_idx on public.workout_proposals (group_id);

-- At most one Apple-Intelligence-suggested proposal per group per calendar
-- day. Every member's device computes suggestions independently, so this
-- guarantees they converge on the same slot: whichever device's insert lands
-- first wins, and everyone else's app just displays that same row.
create unique index if not exists workout_proposals_one_suggested_per_day
  on public.workout_proposals (group_id, ((starts_at at time zone 'utc')::date))
  where is_suggested;

alter table public.workout_proposals enable row level security;

create policy "proposals are readable by group members"
  on public.workout_proposals for select
  to authenticated
  using (
    exists (
      select 1 from public.group_members gm
      where gm.group_id = workout_proposals.group_id
        and gm.user_id = auth.uid()
    )
  );

create policy "group members can create proposals"
  on public.workout_proposals for insert
  to authenticated
  with check (
    auth.uid() = created_by
    and exists (
      select 1 from public.group_members gm
      where gm.group_id = workout_proposals.group_id
        and gm.user_id = auth.uid()
    )
  );

-- ---------------------------------------------------------------------------
-- workout_responses: each member's RSVP (accepted/declined/pending) to a
-- proposal. Only "accepted" rows count as a real commitment.
-- ---------------------------------------------------------------------------
create table if not exists public.workout_responses (
  id uuid primary key default gen_random_uuid(),
  proposal_id uuid not null references public.workout_proposals (id) on delete cascade,
  user_id uuid not null references public.profiles (id) on delete cascade,
  status text not null default 'pending' check (status in ('accepted', 'declined', 'pending')),
  updated_at timestamptz not null default now(),
  unique (proposal_id, user_id)
);

create index if not exists workout_responses_proposal_id_idx on public.workout_responses (proposal_id);

alter table public.workout_responses enable row level security;

create policy "responses are readable by group members"
  on public.workout_responses for select
  to authenticated
  using (
    exists (
      select 1 from public.workout_proposals wp
      join public.group_members gm on gm.group_id = wp.group_id
      where wp.id = workout_responses.proposal_id
        and gm.user_id = auth.uid()
    )
  );

create policy "users manage their own responses"
  on public.workout_responses for insert
  to authenticated
  with check (auth.uid() = user_id);

create policy "users update their own responses"
  on public.workout_responses for update
  to authenticated
  using (auth.uid() = user_id);

-- ---------------------------------------------------------------------------
-- ride_assignments: how each committed member is getting to a workout —
-- driving themselves from an address, or getting picked up by another
-- committed member from a pickup address. Used to calculate ETAs once a
-- workout has been committed to (>= 2 accepted responses on a proposal).
-- ---------------------------------------------------------------------------
create table if not exists public.ride_assignments (
  id uuid primary key default gen_random_uuid(),
  proposal_id uuid not null references public.workout_proposals (id) on delete cascade,
  user_id uuid not null references public.profiles (id) on delete cascade,
  mode text not null default 'driving' check (mode in ('driving', 'picked_up')),
  driver_id uuid references public.profiles (id) on delete set null,
  start_address text,
  start_latitude double precision,
  start_longitude double precision,
  updated_at timestamptz not null default now(),
  unique (proposal_id, user_id),
  constraint picked_up_needs_driver check (mode = 'driving' or driver_id is not null)
);

create index if not exists ride_assignments_proposal_id_idx on public.ride_assignments (proposal_id);

alter table public.ride_assignments enable row level security;

create policy "ride assignments are readable by group members"
  on public.ride_assignments for select
  to authenticated
  using (
    exists (
      select 1 from public.workout_proposals wp
      join public.group_members gm on gm.group_id = wp.group_id
      where wp.id = ride_assignments.proposal_id
        and gm.user_id = auth.uid()
    )
  );

create policy "users manage their own ride assignment"
  on public.ride_assignments for insert
  to authenticated
  with check (auth.uid() = user_id);

create policy "users update their own ride assignment"
  on public.ride_assignments for update
  to authenticated
  using (auth.uid() = user_id);

-- ---------------------------------------------------------------------------
-- Realtime: enable change broadcasts so group members see availability,
-- proposals, and RSVPs update live.
-- ---------------------------------------------------------------------------
alter publication supabase_realtime add table public.busy_slots;
alter publication supabase_realtime add table public.workout_proposals;
alter publication supabase_realtime add table public.workout_responses;
alter publication supabase_realtime add table public.ride_assignments;
