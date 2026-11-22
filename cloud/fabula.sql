create extension if not exists pg_net;
create extension if not exists pg_cron;

create table if not exists public.movies (
  tmdb integer primary key,
  title text not null,
  original_title text,
  year integer,
  released date,
  runtime integer,
  lang text,
  language text,
  genres text[] not null default '{}',
  keywords text[] not null default '{}',
  director text,
  "cast" text[] not null default '{}',
  overview text,
  poster text,
  backdrop text,
  vote numeric,
  votes integer,
  popularity numeric,
  collection integer,
  providers text[] not null default '{}',
  recs integer[] not null default '{}',
  imdb_id text,
  imdb_rating numeric(3,1),
  imdb_votes integer,
  updated timestamptz not null default now()
);
create index if not exists movies_year on public.movies(year);
create index if not exists movies_language on public.movies(language);
alter table public.movies add column if not exists imdb_id text, add column if not exists imdb_rating numeric(3,1), add column if not exists imdb_votes integer;
create index if not exists movies_imdb_id on public.movies(imdb_id) where imdb_id is not null;
create index if not exists movies_collection on public.movies(collection) where collection is not null;
alter table public.movies enable row level security;
create policy movies_read on public.movies for select to anon, authenticated using (true);
grant select on public.movies to anon, authenticated;

create table if not exists public.fabula_admin (
  key text primary key,
  value jsonb not null,
  updated timestamptz not null default now()
);
alter table public.fabula_admin enable row level security;
revoke all on public.fabula_admin from anon, authenticated;
insert into public.fabula_admin(key, value) values ('ingest_token', to_jsonb(encode(gen_random_bytes(24), 'hex'))) on conflict do nothing;
insert into public.fabula_admin(key, value) values ('ingest_cursor', '{"plan": 0, "page": 1}') on conflict do nothing;

create table if not exists public.match_room (
  id uuid primary key default gen_random_uuid(),
  code text unique not null,
  deck integer[] not null default '{}',
  created_at timestamptz not null default now(),
  started_at timestamptz,
  matched integer,
  matched_at timestamptz
);
create table if not exists public.match_member (
  id uuid primary key default gen_random_uuid(),
  room uuid not null references public.match_room(id) on delete cascade,
  name text not null,
  is_host boolean not null default false,
  joined_at timestamptz not null default now()
);
create table if not exists public.match_swipe (
  room uuid not null references public.match_room(id) on delete cascade,
  member uuid not null references public.match_member(id) on delete cascade,
  tmdb integer not null,
  yes boolean not null,
  at timestamptz not null default now(),
  primary key (member, tmdb)
);
create index if not exists match_swipe_room on public.match_swipe(room, tmdb);
alter table public.match_room enable row level security;
alter table public.match_member enable row level security;
alter table public.match_swipe enable row level security;
revoke all on public.match_room, public.match_member, public.match_swipe from anon, authenticated;

select cron.schedule('fabula-match-purge', '*/15 * * * *', $$delete from public.match_room where (matched_at is not null and matched_at < now() - interval '2 hours') or created_at < now() - interval '12 hours'$$);

select cron.schedule('fabula-ingest', '*/2 * * * *', $$select net.http_post(url := 'https://<project-ref>.supabase.co/functions/v1/fabula-tmdb', body := jsonb_build_object('action','ingest','token',(select value from public.fabula_admin where key='ingest_token')), headers := '{"Content-Type":"application/json"}'::jsonb, timeout_milliseconds := 150000) where coalesce((select (value->>'plan')::int from public.fabula_admin where key='ingest_cursor'), 0) < 222$$);

alter table public.movies
  add column if not exists kind text not null default 'movie',
  add column if not exists seasons integer,
  add column if not exists episodes integer,
  add column if not exists network text,
  add column if not exists status text,
  add column if not exists format text,
  add column if not exists season text,
  add column if not exists ended integer,
  add column if not exists mal_score numeric(4,2),
  add column if not exists mal_members integer,
  add column if not exists mal_scorers integer;
create index if not exists movies_kind on public.movies(kind);
insert into public.fabula_admin(key, value) values ('shows_cursor', '{"plan": 0, "page": 1}') on conflict do nothing;
insert into public.fabula_admin(key, value) values ('anime_cursor', '{"offset": 0}') on conflict do nothing;

create or replace function public.fabula_set_imdb(p_rows jsonb)
returns integer
language sql
security definer
set search_path = public
as $$
  with u as (
    update movies m set imdb_rating = (r->>'rating')::numeric, imdb_votes = (r->>'votes')::int
    from jsonb_array_elements(p_rows) r where m.tmdb = (r->>'tmdb')::int returning 1
  ) select count(*)::int from u
$$;
revoke all on function public.fabula_set_imdb(jsonb) from public, anon, authenticated;
grant execute on function public.fabula_set_imdb(jsonb) to service_role;

create or replace function public.fabula_user(p_who text)
returns uuid
language plpgsql
immutable
set search_path = public
as $$
begin
  case p_who
    when 'pranav' then return '00000000-0000-0000-0000-000000000000'::uuid;
    when 'momo' then return '6d6f6d6f-0000-4000-8000-000000000001'::uuid;
    else raise exception 'Unknown profile %', p_who;
  end case;
end
$$;
grant execute on function public.fabula_user(text) to anon, authenticated;

create or replace function public.fabula_prefix(p_who text)
returns text
language plpgsql
immutable
set search_path = public
as $$
begin
  case p_who
    when 'pranav' then return 'ortus';
    when 'momo' then return 'momo';
    else raise exception 'Unknown profile %', p_who;
  end case;
end
$$;
grant execute on function public.fabula_prefix(text) to anon, authenticated;

create or replace function public.fabula_deck(p_who text, p_kind text, p_langs text[] default null, p_genres text[] default null, p_limit integer default 20, p_exclude integer[] default '{}')
returns jsonb
language plpgsql
stable
security definer
set search_path = public
set work_mem = '32MB'
set plan_cache_mode = force_custom_plan
as $$
declare
  k text := case when p_kind in ('show', 'anime') then p_kind else 'movie' end;
  u uuid := public.fabula_user(p_who);
  pre text := public.fabula_prefix(p_who);
begin
return (
with recs_live as (
  select kind, data from records
  where user_id = u and kind in (pre || '.log', pre || '.swipe') and not coalesce(deleted, false)
),
logged as (
  select (data->>'tmdb')::int as tmdb, (data->>'rating')::numeric as r from recs_live where kind = pre || '.log' and data ? 'tmdb'
),
swiped as (
  select (data->>'tmdb')::int as tmdb, data->>'verdict' as v, coalesce((data->>'at')::timestamptz, now()) as at from recs_live where kind = pre || '.swipe' and data ? 'tmdb'
),
rated as (
  select tmdb, r, 1.0::numeric as w from logged where r is not null
  union all
  select s.tmdb,
    case s.v when 'super' then 10 when 'yes' then 8.8 else 7.0 end,
    case when s.v = 'no' then greatest(0, 0.5 * (1 - extract(epoch from now() - s.at) / (90 * 86400)))::numeric else 0.5 end
  from swiped s where s.v in ('super', 'yes', 'no') and not exists (select 1 from logged l where l.tmdb = s.tmdb)
),
r2 as (
  select m.tmdb, m.title, m.director, m.genres, m.keywords, m."cast", m.recs, m.collection, m.kind, rated.r, rated.r - 8.1 as c,
    rated.w * case when m.kind = k then 1 else 0.25 end as w
  from rated join movies m using (tmdb) where rated.w > 0
),
feat as (
  select 'g:' || x as f, c, w from r2, unnest(genres) x
  union all select 'k:' || x, c, w from r2, unnest(keywords) x
  union all select 'd:' || director, c, w from r2 where director is not null
  union all select 'c:' || x, c, w from r2, unnest("cast"[1:4]) x
),
aff as (
  select f, sum(c * w) / (sum(w) + case left(f, 1) when 'g' then 4 when 'k' then 2 else 1.5 end) as a from feat group by f
),
seen as (
  select tmdb from logged
  union select tmdb from swiped where not (v = 'no' and at < now() - interval '180 days')
),
seen_titles as (
  select lower(m.title) as t from seen s join movies m using (tmdb) where m.kind = k
),
loved as (
  select r2.tmdb, r2.title, r2.director, r2.recs, r2.r from r2 join logged using (tmdb) where r2.r >= 9
),
cand as (
  select m.tmdb, m.title, m.year, m.genres, m.keywords, m.director, m."cast", m.collection,
    case when k = 'show' then coalesce(m.imdb_rating, m.vote) else m.vote end as vote, m.votes from movies m
  where m.kind = k
    and m.tmdb not in (select tmdb from seen where tmdb is not null)
    and lower(m.title) not in (select t from seen_titles)
    and not (m.tmdb = any(coalesce(p_exclude, '{}')))
    and (p_langs is null or cardinality(p_langs) = 0 or m.language = any(p_langs))
    and (p_genres is null or cardinality(p_genres) = 0 or m.genres && p_genres)
    and m.year between 1990 and 2026
    and case k
      when 'show' then coalesce(m.imdb_rating, m.vote, 0) >= 5 and coalesce(m.imdb_votes, 0) >= 500
      when 'anime' then coalesce(m.mal_score, 0) >= 5 and coalesce(m.mal_scorers, 0) >= 500 and coalesce(m.format, '') <> 'Special'
      else coalesce(m.vote, 0) >= 5.5 and coalesce(m.runtime, 90) >= 60 and not (m.language = 'Japanese' and 'Animation' = any(m.genres))
    end
),
cf as (
  select c.tmdb, 'g:' || x as f, 'g' as t from cand c, unnest(c.genres) x
  union all select c.tmdb, 'k:' || x, 'k' from cand c, unnest(c.keywords) x
  union all select c.tmdb, 'd:' || c.director, 'd' from cand c where c.director is not null
  union all select c.tmdb, 'c:' || x, 'c' from cand c, unnest(c."cast"[1:4]) x
),
taste as (
  select data from records
  where user_id = u and kind = pre || '.taste' and id = 'book' and not coalesce(deleted, false)
),
taste_f as (
  select f, sum(w) as w from (
    select 'g:' || x as f, 1.0 as w from taste, jsonb_array_elements_text(coalesce(data->'likes'->'genres', '[]')) x
    union all select 'd:' || x, 1.0 from taste, jsonb_array_elements_text(coalesce(data->'likes'->'directors', '[]')) x
    union all select 'k:' || lower(x), 1.0 from taste, jsonb_array_elements_text(coalesce(data->'likes'->'keywords', '[]')) x
    union all select 'g:' || x, -1.0 from taste, jsonb_array_elements_text(coalesce(data->'dislikes'->'genres', '[]')) x
    union all select 'd:' || x, -1.0 from taste, jsonb_array_elements_text(coalesce(data->'dislikes'->'directors', '[]')) x
    union all select 'k:' || lower(x), -1.0 from taste, jsonb_array_elements_text(coalesce(data->'dislikes'->'keywords', '[]')) x
  ) t group by f
),
tb as (
  select cf.tmdb, greatest(-3, least(3, sum(t.w))) as n from cf join taste_f t using (f) group by cf.tmdb
),
agg as (
  select cf.tmdb,
    avg(a.a) filter (where cf.t = 'g') as ga,
    sum(a.a) filter (where cf.t = 'k') as ka,
    max(a.a) filter (where cf.t = 'd') as da,
    avg(a.a) filter (where cf.t = 'c') as ca
  from cf join aff a using (f) group by cf.tmdb
),
rb as (
  select x as tmdb, count(*) as n from loved, unnest(recs) x group by x
),
first_part as (
  select collection, min(year) as y from movies where collection is not null group by collection
),
seq as (
  select c.tmdb from cand c join first_part f on f.collection = c.collection
  where c.year > f.y
    and c.collection not in (select collection from r2 where collection is not null)
),
scored as (
  select c.*,
    1.2 * coalesce(g.ga, 0) + 0.6 * tanh(coalesce(g.ka, 0)) + 1.0 * coalesce(g.da, 0) + 0.6 * coalesce(g.ca, 0)
    + 0.35 * least(coalesce(rb.n, 0), 4)
    + 0.3 * (coalesce(c.vote, 6.5) - 7)
    + 0.04 * ln(1 + coalesce(c.votes, 0))
    - case when seq.tmdb is not null then 0.4 else 0 end
    + 0.25 * coalesce(tb.n, 0)
    + random() * 0.25 as score
  from cand c
  left join agg g on g.tmdb = c.tmdb
  left join rb on rb.tmdb = c.tmdb
  left join seq on seq.tmdb = c.tmdb
  left join tb on tb.tmdb = c.tmdb
),
dedup as (
  select distinct on (lower(title)) * from scored order by lower(title), score desc
),
ranked as (
  select s.*, row_number() over (order by score desc) as rk from dedup s
),
top as (
  select * from ranked where rk <= greatest(1, round(p_limit * 0.8))
),
explore as (
  select * from ranked
  where rk > 40 and rk <= 400 and coalesce(votes, 0) >= 300 and coalesce(vote, 0) >= 6.5
  order by random() limit greatest(0, p_limit - (select count(*) from top))
),
picked as (
  select m.*, t.rk::float as pos from top t join movies m using (tmdb)
  union all select m.*, random() * greatest(1, round(p_limit * 0.8)) + 0.5 from explore e join movies m using (tmdb)
)
select coalesce(jsonb_agg(jsonb_build_object(
  'tmdb', p.tmdb, 'title', p.title, 'year', p.year, 'runtime', p.runtime, 'language', p.language,
  'genres', p.genres, 'director', p.director, 'cast', p."cast"[1:3], 'overview', p.overview,
  'poster', p.poster, 'backdrop', p.backdrop, 'vote', p.vote, 'providers', p.providers,
  'kind', p.kind, 'imdb', case when p.imdb_votes >= case p.kind when 'show' then 500 else 1000 end then p.imdb_rating end,
  'mal', case when p.kind = 'anime' then p.mal_score end, 'seasons', p.seasons, 'episodes', p.episodes,
  'format', p.format, 'season', p.season, 'network', p.network, 'status', p.status, 'ended', p.ended,
  'why', (
    select 'Because you loved ' || l.title from loved l
    where p.tmdb = any(l.recs) or (p.director is not null and l.director = p.director)
    order by (p.tmdb = any(l.recs)) desc, l.r desc limit 1
  )
) order by p.pos), '[]'::jsonb)
from picked p
);
end
$$;
grant execute on function public.fabula_deck(text, text, text[], text[], integer, integer[]) to anon, authenticated;

create or replace function public.fabula_deck(p_kind text, p_langs text[] default null, p_genres text[] default null, p_limit integer default 20, p_exclude integer[] default '{}')
returns jsonb
language sql
stable
security definer
set search_path = public
as $$ select public.fabula_deck('pranav', p_kind, p_langs, p_genres, p_limit, p_exclude) $$;
grant execute on function public.fabula_deck(text, text[], text[], integer, integer[]) to anon, authenticated;

create or replace function public.fabula_deck(p_langs text[] default null, p_genres text[] default null, p_limit integer default 20, p_exclude integer[] default '{}')
returns jsonb
language sql
stable
security definer
set search_path = public
as $$ select public.fabula_deck('movie', p_langs, p_genres, p_limit, p_exclude) $$;
grant execute on function public.fabula_deck(text[], text[], integer, integer[]) to anon, authenticated;

create or replace function public.fabula_refine(p_who text, p_kind text, p_langs text[] default null, p_genres text[] default null, p_limit integer default 10, p_exclude integer[] default '{}')
returns jsonb
language plpgsql
stable
security definer
set search_path = public
set plan_cache_mode = force_custom_plan
as $$
declare
  k text := case when p_kind in ('show', 'anime') then p_kind else 'movie' end;
  u uuid := public.fabula_user(p_who);
  pre text := public.fabula_prefix(p_who);
begin
return (
with done as (
  select id from records
  where user_id = u and kind in (pre || '.log', pre || '.swipe', pre || '.unseen') and not coalesce(deleted, false)
),
pool as (
  select m.tmdb, m.title, m.year, m.director, m.overview, m.poster, m.language, m.genres, m.runtime, m.votes,
    m.kind, m.seasons, m.episodes, m.format
  from movies m
  where m.kind = k
    and (k <> 'movie' or not (m.language = 'Japanese' and 'Animation' = any(m.genres)))
    and (k <> 'anime' or coalesce(m.format, '') <> 'Special')
    and m.tmdb::text not in (select id from done)
    and not (m.tmdb = any(coalesce(p_exclude, '{}')))
    and (p_langs is null or cardinality(p_langs) = 0 or m.language = any(p_langs))
    and (p_genres is null or cardinality(p_genres) = 0 or m.genres && p_genres)
  order by m.votes desc nulls last
  limit 300
),
picked as (
  select * from pool order by random() * ln(2 + coalesce(votes, 0)) desc limit greatest(1, least(p_limit, 30))
)
select coalesce(jsonb_agg(jsonb_build_object(
  'tmdb', tmdb, 'title', title, 'year', year, 'director', director, 'overview', overview, 'poster', poster,
  'language', language, 'genres', genres, 'runtime', runtime, 'kind', kind, 'seasons', seasons, 'episodes', episodes,
  'format', format
) order by votes desc nulls last), '[]'::jsonb)
from picked
);
end
$$;
grant execute on function public.fabula_refine(text, text, text[], text[], integer, integer[]) to anon, authenticated;

create or replace function public.fabula_refine(p_kind text, p_langs text[] default null, p_genres text[] default null, p_limit integer default 10, p_exclude integer[] default '{}')
returns jsonb
language sql
stable
security definer
set search_path = public
as $$ select public.fabula_refine('pranav', p_kind, p_langs, p_genres, p_limit, p_exclude) $$;
grant execute on function public.fabula_refine(text, text[], text[], integer, integer[]) to anon, authenticated;

create or replace function public.fabula_films(p_ids integer[])
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(jsonb_agg(jsonb_build_object(
    'tmdb', m.tmdb, 'title', m.title, 'year', m.year, 'director', m.director, 'overview', m.overview, 'poster', m.poster,
    'language', m.language, 'genres', m.genres, 'runtime', m.runtime, 'kind', m.kind, 'seasons', m.seasons, 'episodes', m.episodes,
    'format', m.format
  ) order by array_position(p_ids, m.tmdb)), '[]'::jsonb)
  from movies m where m.tmdb = any(coalesce(p_ids, '{}')) and cardinality(p_ids) <= 200
$$;
grant execute on function public.fabula_films(integer[]) to anon, authenticated;

create or replace function public.fabula_refine(p_langs text[] default null, p_genres text[] default null, p_limit integer default 10, p_exclude integer[] default '{}')
returns jsonb
language sql
stable
security definer
set search_path = public
as $$ select public.fabula_refine('movie', p_langs, p_genres, p_limit, p_exclude) $$;
grant execute on function public.fabula_refine(text[], text[], integer, integer[]) to anon, authenticated;

create or replace function public.fabula_guide(p_who text, p_lang text, p_limit integer default 10, p_exclude integer[] default '{}')
returns jsonb
language plpgsql
stable
security definer
set search_path = public
set plan_cache_mode = force_custom_plan
as $$
declare
  u uuid := public.fabula_user(p_who);
  pre text := public.fabula_prefix(p_who);
  cfg jsonb;
  sh jsonb;
  share numeric;
begin
select l into cfg from records r, jsonb_array_elements(r.data->'langs') l
where r.user_id = u and r.kind = pre || '.guide' and r.id = 'list' and l->>'name' = p_lang limit 1;
sh := cfg->'shows';
share := case when sh is null then 0 else least(0.8, greatest(0, coalesce((sh->>'share')::numeric, 0.3))) end;
return (
with recs as (
  select kind, id, data from records
  where user_id = u and kind in (pre || '.log', pre || '.swipe', pre || '.unseen') and not coalesce(deleted, false)
),
rated as (
  select (data->>'tmdb')::int as tmdb, (data->>'rating')::numeric as r from recs where kind = pre || '.log' and data ? 'rating'
),
base as (
  select coalesce(avg(r), 7.5) as mean from rated
),
r2 as (
  select m.genres, m.keywords, m.director, rated.r - (select mean from base) as c from rated join movies m using (tmdb)
),
feat as (
  select 'g:' || x as f, c from r2, unnest(genres) x
  union all select 'k:' || x, c from r2, unnest(keywords) x
  union all select 'd:' || director, c from r2 where director is not null
),
aff as (
  select f, sum(c) / (count(*) + case left(f, 1) when 'g' then 2 when 'k' then 1.5 else 1 end) as a from feat group by f
),
films as (
  select m.tmdb, m.kind, m.year, m.genres, m.keywords, m.director, m.votes from movies m
  where m.kind = 'movie' and m.language = p_lang
    and m.year between 1990 and 2026
    and coalesce(m.runtime, 90) >= 60
    and m.tmdb::text not in (select id from recs)
    and not (m.tmdb = any(coalesce(p_exclude, '{}')))
  order by m.votes desc nulls last
  limit round(300 * (1 - share))
),
shows as (
  select m.tmdb, m.kind, m.year, m.genres, m.keywords, m.director, m.votes from movies m
  where share > 0 and m.kind = 'show'
    and m.language in (select jsonb_array_elements_text(coalesce(sh->'langs', jsonb_build_array(p_lang))))
    and (sh->'networks' is null or m.network in (select jsonb_array_elements_text(sh->'networks')))
    and m.year >= coalesce((sh->>'since')::int, 1990)
    and m.tmdb::text not in (select id from recs)
    and not (m.tmdb = any(coalesce(p_exclude, '{}')))
  order by m.votes desc nulls last
  limit round(300 * share)
),
pool as (
  select * from films union all select * from shows
),
pop as (
  select tmdb, percent_rank() over (partition by kind order by votes nulls first) as pr from pool
),
cf as (
  select p.tmdb, 'g:' || x as f, 'g' as t from pool p, unnest(p.genres) x
  union all select p.tmdb, 'k:' || x, 'k' from pool p, unnest(p.keywords) x
  union all select p.tmdb, 'd:' || p.director, 'd' from pool p where p.director is not null
),
agg as (
  select cf.tmdb,
    avg(a.a) filter (where cf.t = 'g') as ga,
    sum(a.a) filter (where cf.t = 'k') as ka,
    max(a.a) filter (where cf.t = 'd') as da
  from cf join aff a using (f) group by cf.tmdb
),
scored as (
  select p.tmdb,
    0.9 * coalesce(g.ga, 0) + 0.4 * tanh(coalesce(g.ka, 0)) + 0.5 * coalesce(g.da, 0)
    + 1.2 * pop.pr
    + case when p.kind = 'movie' and p.year >= coalesce((cfg->'recent'->>'since')::int, 9999) then coalesce((cfg->'recent'->>'boost')::numeric, 0) else 0 end
    + random() * 0.6 as score
  from pool p join pop using (tmdb) left join agg g on g.tmdb = p.tmdb
),
picked as (
  select tmdb, score from scored order by score desc limit greatest(1, least(p_limit, 20))
)
select coalesce(jsonb_agg(jsonb_build_object(
  'tmdb', m.tmdb, 'title', m.title, 'year', m.year, 'director', m.director, 'overview', m.overview, 'poster', m.poster,
  'language', m.language, 'genres', m.genres, 'runtime', m.runtime, 'kind', m.kind, 'seasons', m.seasons, 'episodes', m.episodes,
  'format', m.format
) order by p.score desc), '[]'::jsonb)
from picked p join movies m using (tmdb)
);
end
$$;
grant execute on function public.fabula_guide(text, text, integer, integer[]) to anon, authenticated;
