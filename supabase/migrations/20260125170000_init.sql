-- Initial schema and seed for Echo.
create table if not exists public.hashtags (
  id text primary key,
  name text not null,
  description text not null,
  note_count integer not null default 0,
  created_at timestamptz not null default now()
);

create table if not exists public.voice_notes (
  id text primary key,
  hashtag_id text not null references public.hashtags(id) on delete cascade,
  author_id uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now(),
  duration_seconds integer not null,
  storage_path text not null,
  allow_replies boolean not null default false,
  expires_at timestamptz,
  caption text
);

create index if not exists voice_notes_hashtag_created_idx
  on public.voice_notes (hashtag_id, created_at desc);

create index if not exists voice_notes_author_created_idx
  on public.voice_notes (author_id, created_at desc);

alter table public.hashtags enable row level security;
alter table public.voice_notes enable row level security;

create policy "Public read hashtags"
  on public.hashtags
  for select
  using (true);

create policy "Public read voice notes"
  on public.voice_notes
  for select
  using (true);

create policy "Insert own voice notes"
  on public.voice_notes
  for insert
  with check (auth.uid() = author_id);

create policy "Update own voice notes"
  on public.voice_notes
  for update
  using (auth.uid() = author_id);

create policy "Delete own voice notes"
  on public.voice_notes
  for delete
  using (auth.uid() = author_id);

insert into storage.buckets (id, name, public)
values ('voice-notes', 'voice-notes', true)
on conflict (id) do update set public = true;

create policy "Public read voice notes"
  on storage.objects
  for select
  using (bucket_id = 'voice-notes');

create policy "Authenticated uploads voice notes"
  on storage.objects
  for insert
  with check (bucket_id = 'voice-notes' and auth.role() = 'authenticated');

-- Seed data (idempotent).
insert into public.hashtags (id, name, description)
values
  ('nightwalk', '#NightWalk', 'Late-night wanderings and quiet thoughts'),
  ('studysession', '#StudySession', 'Short thoughts to keep you going'),
  ('newmom', '#NewMom', 'Real moments from new parents'),
  ('anime', '#Anime', 'Quick thoughts on shows and characters'),
  ('comedy', '#Comedy', 'Moments that made you laugh'),
  ('bookworm', '#BookWorm', 'Quick reactions to what you are reading'),
  ('quietwin', '#QuietWin', 'Small victories worth celebrating'),
  ('cooking', '#Cooking', 'Kitchen experiments and recipe thoughts')
on conflict (id) do nothing;
