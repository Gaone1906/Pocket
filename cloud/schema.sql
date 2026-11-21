create table if not exists public.records (
    user_id uuid not null default '00000000-0000-0000-0000-000000000000'::uuid,
    kind text not null check (kind ~ '^[a-z][a-z0-9.]*$'),
    id text not null check (length(id) between 1 and 200),
    data jsonb not null default '{}'::jsonb,
    deleted boolean not null default false,
    device text,
    updated_at timestamptz not null default clock_timestamp(),
    primary key (user_id, kind, id)
);

create index if not exists records_user_updated on public.records (user_id, updated_at);

alter table public.records enable row level security;

drop policy if exists "records are open to the app key" on public.records;
create policy "records are open to the app key" on public.records
    for all to anon, authenticated
    using (true)
    with check (true);

create or replace function public.touch_record() returns trigger
language plpgsql
set search_path = ''
as $$
begin
    new.updated_at := clock_timestamp();
    return new;
end
$$;

drop trigger if exists touch_record on public.records;
create trigger touch_record before insert or update on public.records
    for each row execute function public.touch_record();

grant select, insert, update, delete on public.records to anon, authenticated;

create or replace function public.luna_ingest(lines text, type text default null)
returns integer
language plpgsql
security invoker
set search_path = ''
as $$
declare
    line text;
    parts text[];
    v text;
    q text;
    n integer := 0;
begin
    foreach line in array regexp_split_to_array(coalesce(lines, ''), E'\\r?\\n') loop
        line := btrim(line);
        continue when line = '';
        parts := string_to_array(line, '|');
        continue when coalesce(array_length(parts, 1), 0) < 3;
        if type is null then
            v := btrim(parts[1]);
            q := null;
        else
            v := type;
            q := substring(parts[1] from '[0-9]+(?:\.[0-9]+)?');
        end if;
        continue when btrim(parts[2]) = '' or btrim(parts[3]) = '';
        insert into public.records (kind, id, data, device)
        values ('sleep.sample',
                left(v || '|' || btrim(parts[2]) || '|' || btrim(coalesce(parts[4], '')), 200),
                jsonb_strip_nulls(jsonb_build_object('s', btrim(parts[2]), 'e', btrim(parts[3]), 'v', v, 'q', q)),
                'shortcut')
        on conflict (user_id, kind, id) do update
            set data = excluded.data, deleted = false, device = excluded.device
            where public.records.data is distinct from excluded.data or public.records.deleted;
        n := n + 1;
    end loop;
    return n;
end
$$;

grant execute on function public.luna_ingest(text, text) to anon, authenticated;
