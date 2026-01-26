-- Echo production schema (v2)
-- Buckets:
--   - Uses "voice-notes" bucket as the clips bucket (private; read via RLS).
--   - "echo-replies" is private; access via RLS or signed URLs.
-- Playback:
--   - Clips are streamed via authenticated storage reads (RLS-gated).
-- Skip enforcement:
--   - Call public.consume_skip() to enforce 3 skips/day per user.
-- Compatibility:
--   - public.voice_notes remains the canonical clips table for the current app.
--   - public.clips is a view over voice_notes for forward compatibility.

create extension if not exists pgcrypto;
create extension if not exists citext;

-- Helpers
create or replace function public.set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

create or replace function public.normalize_profile_handle()
returns trigger
language plpgsql
as $$
begin
  if new.handle is not null then
    new.handle = lower(new.handle);
  end if;
  return new;
end;
$$;

create or replace function public.set_hashtags_search_vector()
returns trigger
language plpgsql
as $$
begin
  new.search_vector := to_tsvector(
    'simple',
    coalesce(new.name, '') || ' ' || array_to_string(new.synonyms, ' ')
  );
  return new;
end;
$$;

create or replace function public.current_local_date(p_user_id uuid)
returns date
language plpgsql
stable
as $$
declare
  tz text;
  local_ts timestamp;
begin
  select timezone into tz from public.profiles where user_id = p_user_id;
  if tz is null or tz = '' then
    tz := 'UTC';
  end if;
  begin
    local_ts := timezone(tz, now());
  exception when others then
    local_ts := timezone('UTC', now());
  end;
  return local_ts::date;
end;
$$;

create or replace function public.consume_skip()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid;
  v_date date;
  v_used smallint;
begin
  v_uid := auth.uid();
  if v_uid is null then
    raise exception 'Not authenticated';
  end if;

  v_date := public.current_local_date(v_uid);

  insert into public.daily_skip_usage (user_id, local_date, skips_used)
  values (v_uid, v_date, 0)
  on conflict (user_id, local_date) do nothing;

  select skips_used
    into v_used
    from public.daily_skip_usage
   where user_id = v_uid
     and local_date = v_date
   for update;

  if v_used < 3 then
    update public.daily_skip_usage
       set skips_used = skips_used + 1,
           updated_at = now()
     where user_id = v_uid
       and local_date = v_date
    returning skips_used into v_used;

    return jsonb_build_object(
      'ok', true,
      'skips_left', 3 - v_used,
      'local_date', v_date
    );
  end if;

  return jsonb_build_object(
    'ok', false,
    'skips_left', 0,
    'local_date', v_date
  );
end;
$$;

grant execute on function public.consume_skip() to authenticated;

-- Profiles
create table if not exists public.profiles (
  user_id uuid primary key references auth.users(id) on delete cascade,
  handle citext not null,
  timezone text not null default 'UTC',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create unique index if not exists profiles_handle_unique
  on public.profiles (handle);

comment on table public.profiles is 'User profiles for Echo.';
comment on column public.profiles.handle is 'Lowercased public handle.';

-- Hashtags (existing table, extended)
alter table public.hashtags
  add column if not exists category text;

alter table public.hashtags
  add column if not exists synonyms text[] not null default '{}'::text[];

alter table public.hashtags
  add column if not exists is_active boolean not null default true;

alter table public.hashtags
  add column if not exists updated_at timestamptz not null default now();

alter table public.hashtags
  add column if not exists search_vector tsvector;

update public.hashtags
   set search_vector = to_tsvector(
     'simple',
     coalesce(name, '') || ' ' || array_to_string(synonyms, ' ')
   )
 where search_vector is null;

create index if not exists hashtags_search_idx
  on public.hashtags using gin (search_vector);

comment on table public.hashtags is 'Curated hashtag communities.';

-- Voice notes (canonical clips table)
alter table public.voice_notes
  add column if not exists storage_bucket text not null default 'voice-notes';

alter table public.voice_notes
  add column if not exists status text not null default 'active';

alter table public.voice_notes
  add column if not exists is_ephemeral boolean not null default false;

alter table public.voice_notes
  add column if not exists updated_at timestamptz not null default now();

update public.voice_notes set storage_bucket = 'voice-notes'
where storage_bucket is null;

update public.voice_notes set status = 'active'
where status is null;

update public.voice_notes
   set is_ephemeral = (expires_at is not null)
 where is_ephemeral is null;

update public.voice_notes set updated_at = now()
where updated_at is null;

alter table public.voice_notes
  drop constraint if exists voice_notes_status_check;
alter table public.voice_notes
  add constraint voice_notes_status_check
  check (status in ('active', 'under_review', 'removed'));

alter table public.voice_notes
  drop constraint if exists voice_notes_duration_check;
alter table public.voice_notes
  add constraint voice_notes_duration_check
  check (duration_seconds > 0 and duration_seconds <= 12);

alter table public.voice_notes
  drop constraint if exists voice_notes_ephemeral_check;
alter table public.voice_notes
  add constraint voice_notes_ephemeral_check
  check (
    (is_ephemeral = false and expires_at is null) or
    (is_ephemeral = true and expires_at is not null)
  );

alter table public.voice_notes
  drop constraint if exists voice_notes_expires_after_created;
alter table public.voice_notes
  add constraint voice_notes_expires_after_created
  check (expires_at is null or expires_at > created_at);

alter table public.voice_notes
  drop constraint if exists voice_notes_storage_path_check;
alter table public.voice_notes
  add constraint voice_notes_storage_path_check
  check (storage_path like author_id::text || '/%');

alter table public.voice_notes
  drop constraint if exists voice_notes_storage_bucket_check;
alter table public.voice_notes
  add constraint voice_notes_storage_bucket_check
  check (storage_bucket = 'voice-notes');

comment on table public.voice_notes is 'Canonical clips table for Echo (kept for app compatibility).';
comment on column public.voice_notes.allow_replies is 'Equivalent to allow_private_replies.';

create index if not exists voice_notes_hashtag_created_active_idx
  on public.voice_notes (hashtag_id, created_at desc)
  where status = 'active';

create index if not exists voice_notes_author_created_idx
  on public.voice_notes (author_id, created_at desc);

create index if not exists voice_notes_expires_at_idx
  on public.voice_notes (expires_at)
  where expires_at is not null;

-- Blocks
create table if not exists public.blocks (
  blocker_user_id uuid not null references public.profiles(user_id) on delete cascade,
  blocked_user_id uuid not null references public.profiles(user_id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (blocker_user_id, blocked_user_id),
  check (blocker_user_id <> blocked_user_id)
);

create or replace function public.fetch_clips_batch(
  p_hashtag_id text,
  p_limit int default 20
)
returns setof public.voice_notes
language sql
as $$
  select vn.*
  from public.voice_notes vn
  where vn.hashtag_id = p_hashtag_id
    and vn.status = 'active'
    and (vn.expires_at is null or vn.expires_at > now())
    and (
      auth.uid() is null
      or not exists (
        select 1
        from public.blocks b
        where b.blocker_user_id = auth.uid()
          and b.blocked_user_id = vn.author_id
      )
    )
  order by vn.created_at desc, random()
  limit p_limit;
$$;

grant execute on function public.fetch_clips_batch(text, int) to anon, authenticated;

-- Reports
create table if not exists public.reports (
  id uuid primary key default gen_random_uuid(),
  reporter_user_id uuid null references public.profiles(user_id) on delete set null,
  clip_id text not null references public.voice_notes(id) on delete cascade,
  reason text not null check (
    reason in (
      'harassment_hate',
      'sexual',
      'self_harm',
      'threats_violence',
      'spam',
      'other'
    )
  ),
  details text,
  created_at timestamptz not null default now(),
  status text not null default 'open' check (
    status in ('open', 'reviewed', 'dismissed', 'actioned')
  )
);

create unique index if not exists reports_unique_reporter_clip
  on public.reports (reporter_user_id, clip_id)
  where reporter_user_id is not null;

create index if not exists reports_clip_created_idx
  on public.reports (clip_id, created_at desc);

-- Private replies
create table if not exists public.private_replies (
  id uuid primary key default gen_random_uuid(),
  parent_clip_id text not null references public.voice_notes(id) on delete cascade,
  from_user_id uuid not null references public.profiles(user_id) on delete cascade,
  to_user_id uuid not null references public.profiles(user_id) on delete cascade,
  storage_bucket text not null default 'echo-replies',
  storage_path text not null,
  duration_ms integer not null check (duration_ms > 0 and duration_ms <= 12000),
  status text not null default 'active' check (status in ('active', 'removed')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (from_user_id <> to_user_id)
);

alter table public.private_replies
  drop constraint if exists private_replies_storage_path_check;
alter table public.private_replies
  add constraint private_replies_storage_path_check
  check (storage_path like from_user_id::text || '/%');

alter table public.private_replies
  drop constraint if exists private_replies_storage_bucket_check;
alter table public.private_replies
  add constraint private_replies_storage_bucket_check
  check (storage_bucket = 'echo-replies');

create index if not exists private_replies_parent_created_idx
  on public.private_replies (parent_clip_id, created_at desc);

comment on table public.private_replies is 'Optional private audio replies.';

create or replace function public.enforce_private_reply_target()
returns trigger
language plpgsql
as $$
declare
  parent_owner uuid;
  parent_allows boolean;
begin
  select author_id, allow_replies
    into parent_owner, parent_allows
    from public.voice_notes
   where id = new.parent_clip_id;

  if parent_owner is null then
    raise exception 'Parent clip not found.';
  end if;
  if new.to_user_id <> parent_owner then
    raise exception 'Recipient must be parent clip owner.';
  end if;
  if parent_allows is distinct from true then
    raise exception 'Private replies are disabled for this clip.';
  end if;

  return new;
end;
$$;

-- Daily skip usage
create table if not exists public.daily_skip_usage (
  user_id uuid not null references public.profiles(user_id) on delete cascade,
  local_date date not null,
  skips_used smallint not null default 0 check (skips_used >= 0 and skips_used <= 3),
  updated_at timestamptz not null default now(),
  primary key (user_id, local_date)
);

create index if not exists daily_skip_usage_user_date_idx
  on public.daily_skip_usage (user_id, local_date);

-- Triggers (updated_at)

drop trigger if exists profiles_set_updated_at on public.profiles;
create trigger profiles_set_updated_at
  before update on public.profiles
  for each row execute function public.set_updated_at();

drop trigger if exists profiles_normalize_handle on public.profiles;
create trigger profiles_normalize_handle
  before insert or update on public.profiles
  for each row execute function public.normalize_profile_handle();

drop trigger if exists hashtags_set_updated_at on public.hashtags;
create trigger hashtags_set_updated_at
  before update on public.hashtags
  for each row execute function public.set_updated_at();

drop trigger if exists hashtags_set_search_vector on public.hashtags;
create trigger hashtags_set_search_vector
  before insert or update of name, synonyms on public.hashtags
  for each row execute function public.set_hashtags_search_vector();

drop trigger if exists voice_notes_set_updated_at on public.voice_notes;
create trigger voice_notes_set_updated_at
  before update on public.voice_notes
  for each row execute function public.set_updated_at();

drop trigger if exists private_replies_set_updated_at on public.private_replies;
create trigger private_replies_set_updated_at
  before update on public.private_replies
  for each row execute function public.set_updated_at();

drop trigger if exists daily_skip_usage_set_updated_at on public.daily_skip_usage;
create trigger daily_skip_usage_set_updated_at
  before update on public.daily_skip_usage
  for each row execute function public.set_updated_at();

drop trigger if exists enforce_private_reply_target
  on public.private_replies;
create trigger enforce_private_reply_target
  before insert on public.private_replies
  for each row execute function public.enforce_private_reply_target();

-- RLS
alter table public.profiles enable row level security;
alter table public.hashtags enable row level security;
alter table public.voice_notes enable row level security;
alter table public.blocks enable row level security;
alter table public.reports enable row level security;
alter table public.private_replies enable row level security;
alter table public.daily_skip_usage enable row level security;

-- Drop legacy policies

drop policy if exists "Public read hashtags" on public.hashtags;

drop policy if exists "Public read voice notes" on public.voice_notes;
drop policy if exists "Insert own voice notes" on public.voice_notes;
drop policy if exists "Update own voice notes" on public.voice_notes;
drop policy if exists "Delete own voice notes" on public.voice_notes;

-- Profiles policies
create policy "Read profiles"
  on public.profiles
  for select
  to authenticated
  using (true);

create policy "Insert own profile"
  on public.profiles
  for insert
  to authenticated
  with check (auth.uid() = user_id);

create policy "Update own profile"
  on public.profiles
  for update
  to authenticated
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

-- Hashtags policies
create policy "Read active hashtags"
  on public.hashtags
  for select
  to public
  using (is_active = true);

-- Voice notes policies
create policy "Read active clips anon"
  on public.voice_notes
  for select
  to anon
  using (
    status = 'active'
    and (expires_at is null or expires_at > now())
  );

create policy "Read active clips authed"
  on public.voice_notes
  for select
  to authenticated
  using (
    status = 'active'
    and (expires_at is null or expires_at > now())
    and not exists (
      select 1
      from public.blocks b
      where b.blocker_user_id = auth.uid()
        and b.blocked_user_id = author_id
    )
  );

create policy "Insert own clips"
  on public.voice_notes
  for insert
  to authenticated
  with check (
    auth.uid() = author_id
    and duration_seconds <= 12
    and status = 'active'
    and storage_bucket = 'voice-notes'
    and storage_path like auth.uid()::text || '/%'
    and exists (
      select 1 from public.hashtags h
      where h.id = hashtag_id and h.is_active = true
    )
  );

create policy "Update own clips"
  on public.voice_notes
  for update
  to authenticated
  using (auth.uid() = author_id and status = 'active')
  with check (
    auth.uid() = author_id
    and status = 'active'
    and storage_bucket = 'voice-notes'
    and storage_path like auth.uid()::text || '/%'
  );

create policy "Delete own clips"
  on public.voice_notes
  for delete
  to authenticated
  using (auth.uid() = author_id);

-- Blocks policies
create policy "Manage own blocks"
  on public.blocks
  for all
  to authenticated
  using (blocker_user_id = auth.uid())
  with check (blocker_user_id = auth.uid());

-- Reports policies
create policy "Insert reports"
  on public.reports
  for insert
  to authenticated
  with check (reporter_user_id = auth.uid());

create policy "Read own reports"
  on public.reports
  for select
  to authenticated
  using (reporter_user_id = auth.uid());

-- Private replies policies
create policy "Read private replies"
  on public.private_replies
  for select
  to authenticated
  using (from_user_id = auth.uid() or to_user_id = auth.uid());

create policy "Insert private replies"
  on public.private_replies
  for insert
  to authenticated
  with check (
    from_user_id = auth.uid()
    and duration_ms <= 12000
    and storage_bucket = 'echo-replies'
    and storage_path like auth.uid()::text || '/%'
    and exists (
      select 1
      from public.voice_notes vn
      where vn.id = parent_clip_id
        and vn.author_id = to_user_id
        and vn.allow_replies = true
    )
  );

create policy "Update private replies"
  on public.private_replies
  for update
  to authenticated
  using (from_user_id = auth.uid() or to_user_id = auth.uid())
  with check (from_user_id = auth.uid() or to_user_id = auth.uid());

create policy "Delete private replies"
  on public.private_replies
  for delete
  to authenticated
  using (from_user_id = auth.uid());

-- Daily skip usage policies
create policy "Read own skip usage"
  on public.daily_skip_usage
  for select
  to authenticated
  using (user_id = auth.uid());

-- Clips view (compatibility)
create or replace view public.clips as
select
  vn.id as id,
  vn.author_id as user_id,
  vn.hashtag_id,
  vn.storage_bucket,
  vn.storage_path,
  (vn.duration_seconds * 1000)::int as duration_ms,
  vn.status,
  vn.allow_replies as allow_private_replies,
  vn.is_ephemeral,
  vn.expires_at,
  vn.created_at,
  vn.updated_at
from public.voice_notes vn;

comment on view public.clips is 'Compatibility view over voice_notes (canonical clips table).';

-- Storage buckets + policies
insert into storage.buckets (id, name, public)
values ('voice-notes', 'voice-notes', false)
on conflict (id) do update set public = false;

insert into storage.buckets (id, name, public)
values ('echo-replies', 'echo-replies', false)
on conflict (id) do update set public = false;

drop policy if exists "Public read voice notes" on storage.objects;
drop policy if exists "Authenticated uploads voice notes" on storage.objects;

drop policy if exists "Public read voice clips" on storage.objects;
drop policy if exists "Authenticated uploads voice clips" on storage.objects;
drop policy if exists "Read echo replies" on storage.objects;
drop policy if exists "Upload echo replies" on storage.objects;

create policy "Read active voice clips"
  on storage.objects
  for select
  to anon, authenticated
  using (
    bucket_id = 'voice-notes'
    and exists (
      select 1
      from public.voice_notes vn
      where vn.storage_path = storage.objects.name
        and vn.storage_bucket = 'voice-notes'
        and vn.status = 'active'
        and (vn.expires_at is null or vn.expires_at > now())
    )
  );

create policy "Authenticated uploads voice clips"
  on storage.objects
  for insert
  to authenticated
  with check (
    bucket_id = 'voice-notes'
    and name like auth.uid()::text || '/%'
  );

create policy "Read echo replies"
  on storage.objects
  for select
  to authenticated
  using (
    bucket_id = 'echo-replies'
    and exists (
      select 1
      from public.private_replies pr
      where pr.storage_path = storage.objects.name
        and pr.status = 'active'
        and pr.storage_bucket = 'echo-replies'
        and (pr.from_user_id = auth.uid() or pr.to_user_id = auth.uid())
    )
  );

create policy "Upload echo replies"
  on storage.objects
  for insert
  to authenticated
  with check (
    bucket_id = 'echo-replies'
    and name like auth.uid()::text || '/%'
  );
