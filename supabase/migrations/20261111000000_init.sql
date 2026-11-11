-- App Kids: schema inicial. Cada responsável (auth.users) só enxerga os próprios dados.

create table public.children (
  id uuid primary key default gen_random_uuid(),
  parent_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  name text not null,
  birth_date date,
  avatar text not null default '🙂',
  created_at timestamptz not null default now()
);

create table public.routines (
  id uuid primary key default gen_random_uuid(),
  parent_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  child_id uuid not null references public.children(id) on delete cascade,
  title text not null,
  period text not null default 'morning' check (period in ('morning','afternoon','night')),
  created_at timestamptz not null default now()
);

create table public.tasks (
  id uuid primary key default gen_random_uuid(),
  parent_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  routine_id uuid not null references public.routines(id) on delete cascade,
  title text not null,
  icon text not null default '⭐',
  points int not null default 1 check (points >= 0),
  weekdays int[] not null default '{1,2,3,4,5,6,7}', -- 1 = segunda ... 7 = domingo (ISO)
  active boolean not null default true,
  created_at timestamptz not null default now()
);

create table public.task_completions (
  id uuid primary key default gen_random_uuid(),
  parent_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  task_id uuid not null references public.tasks(id) on delete cascade,
  child_id uuid not null references public.children(id) on delete cascade,
  day date not null default current_date,
  status text not null default 'pending' check (status in ('pending','approved','rejected')),
  completed_at timestamptz not null default now(),
  unique (task_id, day)
);

create table public.rewards (
  id uuid primary key default gen_random_uuid(),
  parent_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  title text not null,
  icon text not null default '🎁',
  cost int not null check (cost > 0),
  created_at timestamptz not null default now()
);

create table public.redemptions (
  id uuid primary key default gen_random_uuid(),
  parent_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  child_id uuid not null references public.children(id) on delete cascade,
  reward_id uuid not null references public.rewards(id) on delete cascade,
  cost int not null,
  created_at timestamptz not null default now()
);

create index on public.routines (child_id);
create index on public.tasks (routine_id);
create index on public.task_completions (child_id, day);
create index on public.redemptions (child_id);

-- Saldo de pontos = tarefas aprovadas - recompensas resgatadas.
create view public.child_points with (security_invoker = true) as
select
  c.id as child_id,
  coalesce((select sum(t.points) from public.task_completions tc
            join public.tasks t on t.id = tc.task_id
            where tc.child_id = c.id and tc.status = 'approved'), 0)
  - coalesce((select sum(r.cost) from public.redemptions r where r.child_id = c.id), 0)
  as points
from public.children c;

-- RLS: o responsável é dono de tudo que criou.
do $$
declare t text;
begin
  foreach t in array array['children','routines','tasks','task_completions','rewards','redemptions'] loop
    execute format('alter table public.%I enable row level security', t);
    execute format(
      'create policy "owner_all" on public.%I for all to authenticated
         using (parent_id = auth.uid()) with check (parent_id = auth.uid())', t);
  end loop;
end $$;
