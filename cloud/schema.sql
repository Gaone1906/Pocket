create table if not exists public.records (
    user_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
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

drop policy if exists "records are private to their owner" on public.records;
create policy "records are private to their owner" on public.records
    for all to authenticated
    using (user_id = auth.uid())
    with check (user_id = auth.uid());

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

revoke all on public.records from anon;
grant select, insert, update, delete on public.records to authenticated;
