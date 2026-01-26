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
