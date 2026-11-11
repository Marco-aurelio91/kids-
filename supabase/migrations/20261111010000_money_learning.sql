-- Fase 2: dinheiro (R$), mesada, metas, aprendizado e categorias de tarefa.

-- ---------- Tarefas ----------
alter table public.tasks
  add column category text not null default 'routine'
    check (category in ('routine','chore','study','activity')),
  add column reward_cents int not null default 0 check (reward_cents >= 0),
  add column needs_approval boolean not null default true;

-- Tarefas sem recompensa em R$ e sem necessidade de aprovação já nascem aprovadas.
create function public.auto_approve_completion() returns trigger
language plpgsql as $$
declare t record;
begin
  select needs_approval, reward_cents into t from public.tasks where id = new.task_id;
  if found and not t.needs_approval and t.reward_cents = 0 then
    new.status := 'approved';
  end if;
  return new;
end $$;

create trigger task_completions_auto_approve
  before insert on public.task_completions
  for each row execute function public.auto_approve_completion();

-- ---------- Carteira (valores em centavos) ----------
create table public.savings_goals (
  id uuid primary key default gen_random_uuid(),
  parent_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  child_id uuid not null references public.children(id) on delete cascade,
  title text not null,
  icon text not null default '🎯',
  target_cents int not null check (target_cents > 0),
  created_at timestamptz not null default now()
);

create table public.wallet_transactions (
  id uuid primary key default gen_random_uuid(),
  parent_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  child_id uuid not null references public.children(id) on delete cascade,
  pot text not null check (pot in ('spend','save','give')),
  kind text not null check (kind in ('task','allowance','bonus','transfer','payout')),
  amount_cents int not null check (amount_cents <> 0), -- positivo entra, negativo sai
  description text not null default '',
  completion_id uuid unique references public.task_completions(id) on delete set null,
  goal_id uuid references public.savings_goals(id) on delete set null,
  created_at timestamptz not null default now()
);

create table public.allowances (
  id uuid primary key default gen_random_uuid(),
  parent_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  child_id uuid not null unique references public.children(id) on delete cascade,
  amount_cents int not null check (amount_cents > 0),
  frequency text not null check (frequency in ('weekly','monthly')),
  next_due date not null default current_date,
  active boolean not null default true
);

create index on public.wallet_transactions (child_id, created_at desc);
create index on public.savings_goals (child_id);

create view public.child_wallet with (security_invoker = true) as
select
  c.id as child_id,
  coalesce(sum(t.amount_cents) filter (where t.pot = 'spend'), 0)::int as spend_cents,
  coalesce(sum(t.amount_cents) filter (where t.pot = 'save'), 0)::int as save_cents,
  coalesce(sum(t.amount_cents) filter (where t.pot = 'give'), 0)::int as give_cents,
  coalesce(sum(t.amount_cents), 0)::int as total_cents
from public.children c
left join public.wallet_transactions t on t.child_id = c.id
group by c.id;

-- Tarefa aprovada com recompensa em R$ credita no pote "gastar"; reprovar depois estorna.
create function public.pay_task_reward() returns trigger
language plpgsql as $$
declare t record;
begin
  if new.status = 'approved' and old.status is distinct from 'approved' then
    select title, reward_cents into t from public.tasks where id = new.task_id;
    if found and t.reward_cents > 0 then
      insert into public.wallet_transactions
        (parent_id, child_id, pot, kind, amount_cents, description, completion_id)
      values (new.parent_id, new.child_id, 'spend', 'task', t.reward_cents, t.title, new.id)
      on conflict (completion_id) do nothing;
    end if;
  elsif old.status = 'approved' and new.status <> 'approved' then
    delete from public.wallet_transactions where completion_id = new.id;
  end if;
  return new;
end $$;

create trigger task_completions_pay_reward
  after update of status on public.task_completions
  for each row execute function public.pay_task_reward();

-- Move dinheiro entre potes (e para metas) de forma atômica, sem deixar saldo negativo.
create function public.transfer_money(
  p_child uuid, p_from text, p_to text, p_cents int, p_goal uuid default null
) returns void language plpgsql as $$
declare bal int; goal_title text;
begin
  if p_cents <= 0 then raise exception 'Valor inválido'; end if;
  if not exists (select 1 from public.children where id = p_child) then
    raise exception 'Filho não encontrado';
  end if;
  if p_from = p_to and p_goal is null then raise exception 'Escolha potes diferentes'; end if;
  select coalesce(sum(amount_cents), 0) into bal
    from public.wallet_transactions where child_id = p_child and pot = p_from;
  if bal < p_cents then raise exception 'Saldo insuficiente'; end if;
  if p_goal is not null then
    select title into goal_title from public.savings_goals where id = p_goal and child_id = p_child;
    if goal_title is null then raise exception 'Meta não encontrada'; end if;
  end if;
  insert into public.wallet_transactions (child_id, pot, kind, amount_cents, description)
    values (p_child, p_from, 'transfer', -p_cents,
            case when goal_title is null then 'Transferência' else 'Para a meta: ' || goal_title end);
  insert into public.wallet_transactions (child_id, pot, kind, amount_cents, description, goal_id)
    values (p_child, p_to, 'transfer', p_cents,
            case when goal_title is null then 'Transferência' else 'Meta: ' || goal_title end, p_goal);
end $$;

-- Registra que o responsável pagou/entregou dinheiro real (PIX, espécie) e baixa do saldo.
create function public.payout_money(p_child uuid, p_pot text, p_cents int, p_desc text default '')
returns void language plpgsql as $$
declare bal int;
begin
  if p_cents <= 0 then raise exception 'Valor inválido'; end if;
  if not exists (select 1 from public.children where id = p_child) then
    raise exception 'Filho não encontrado';
  end if;
  select coalesce(sum(amount_cents), 0) into bal
    from public.wallet_transactions where child_id = p_child and pot = p_pot;
  if bal < p_cents then raise exception 'Saldo insuficiente'; end if;
  insert into public.wallet_transactions (child_id, pot, kind, amount_cents, description)
    values (p_child, p_pot, 'payout', -p_cents, coalesce(nullif(p_desc, ''), 'Pagamento'));
end $$;

-- Credita mesadas vencidas (idempotente: avança next_due a cada crédito).
create function public.apply_allowances() returns int
language plpgsql as $$
declare a record; d date; n int := 0;
begin
  for a in select * from public.allowances where active and next_due <= current_date loop
    d := a.next_due;
    while d <= current_date loop
      insert into public.wallet_transactions (child_id, pot, kind, amount_cents, description)
        values (a.child_id, 'spend', 'allowance', a.amount_cents, 'Mesada');
      d := case a.frequency when 'weekly' then d + 7 else (d + interval '1 month')::date end;
      n := n + 1;
    end loop;
    update public.allowances set next_due = d where id = a.id;
  end loop;
  return n;
end $$;

-- ---------- Aprendizado ----------
create table public.lessons (
  id uuid primary key default gen_random_uuid(),
  slug text not null unique,
  title text not null,
  icon text not null default '📘',
  category text not null check (category in ('financas','habitos','conhecimentos')),
  min_age int not null default 6,
  content text not null,
  quiz jsonb not null default '[]', -- [{"q": "...", "options": ["..."], "answer": 0}]
  points int not null default 5
);

create table public.lesson_progress (
  id uuid primary key default gen_random_uuid(),
  parent_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  child_id uuid not null references public.children(id) on delete cascade,
  lesson_id uuid not null references public.lessons(id) on delete cascade,
  score_pct int not null check (score_pct between 0 and 100),
  completed_at timestamptz not null default now(),
  unique (child_id, lesson_id)
);

-- RLS
alter table public.lessons enable row level security;
create policy "lessons_read" on public.lessons for select to authenticated using (true);

do $$
declare t text;
begin
  foreach t in array array['savings_goals','wallet_transactions','allowances','lesson_progress'] loop
    execute format('alter table public.%I enable row level security', t);
    execute format(
      'create policy "owner_all" on public.%I for all to authenticated
         using (parent_id = auth.uid()) with check (parent_id = auth.uid())', t);
  end loop;
end $$;

-- Pontos: tarefas aprovadas + aulas (proporcional ao acerto) - recompensas resgatadas.
drop view public.child_points;
create view public.child_points with (security_invoker = true) as
select
  c.id as child_id,
  (
    coalesce((select sum(t.points) from public.task_completions tc
              join public.tasks t on t.id = tc.task_id
              where tc.child_id = c.id and tc.status = 'approved'), 0)
    + coalesce((select sum(round(l.points * lp.score_pct / 100.0)) from public.lesson_progress lp
                join public.lessons l on l.id = lp.lesson_id
                where lp.child_id = c.id), 0)
    - coalesce((select sum(r.cost) from public.redemptions r where r.child_id = c.id), 0)
  )::int as points
from public.children c;

-- ---------- Conteúdo inicial ----------
insert into public.lessons (slug, title, icon, category, min_age, points, content, quiz) values
('ganhar-gastar-guardar', 'Ganhar, gastar e guardar', '🐷', 'financas', 6, 5,
 $c$O dinheiro que a gente recebe pode ter três destinos: gastar, guardar e doar. Quando você gasta tudo de uma vez, não sobra nada para os seus sonhos. Quando você guarda um pouquinho sempre, o dinheiro vai crescendo até comprar algo grande. E dividir um pouco com quem precisa também faz bem.$c$,
 $q$[{"q":"Qual pote serve para juntar dinheiro para um sonho?","options":["Gastar","Guardar","Nenhum"],"answer":1},
     {"q":"Por que é bom guardar um pouco sempre?","options":["Porque o dinheiro some se não guardar","Porque o dinheiro vai crescendo até dar para algo maior","Porque guardar é obrigatório"],"answer":1}]$q$),
('necessidade-ou-desejo', 'Necessidade ou desejo?', '🤔', 'financas', 6, 5,
 $c$Necessidade é o que a gente precisa para viver bem: comida, moradia, material da escola. Desejo é o que a gente quer, mas dá para viver sem: um brinquedo novo, um doce a mais. Antes de comprar, pergunte: eu preciso disso ou eu quero isso? Esperar alguns dias ajuda a descobrir se o desejo é mesmo importante.$c$,
 $q$[{"q":"Qual destes é uma necessidade?","options":["Caderno para a escola","Um quinto brinquedo igual","Figurinhas extras"],"answer":0},
     {"q":"O que ajuda a decidir se vale a pena comprar um desejo?","options":["Comprar na hora","Esperar alguns dias e pensar","Pedir emprestado"],"answer":1}]$q$),
('poupar-para-um-sonho', 'Poupar para um sonho', '🎯', 'financas', 7, 5,
 $c$Um sonho grande custa mais do que você tem hoje, e tudo bem! Defina quanto custa e divida pelo tempo que você tem. Se uma bicicleta custa R$ 300 e você guarda R$ 25 por semana, em 12 semanas ela é sua. Crie uma meta no app e acompanhe a barrinha enchendo.$c$,
 $q$[{"q":"Uma bicicleta custa R$ 300. Guardando R$ 25 por semana, em quantas semanas você junta o valor?","options":["6","12","30"],"answer":1},
     {"q":"Qual é o primeiro passo para poupar para um sonho?","options":["Descobrir quanto ele custa","Gastar o dinheiro antes","Esquecer o sonho"],"answer":0}]$q$),
('doar-tambem-e-usar', 'Doar também é usar o dinheiro', '❤️', 'financas', 6, 5,
 $c$Doar é usar uma parte do que temos para ajudar outras pessoas ou animais. Não precisa ser muito: o importante é o hábito. Você pode doar dinheiro, mas também tempo, roupas e brinquedos que não usa mais.$c$,
 $q$[{"q":"Além de dinheiro, o que mais podemos doar?","options":["Tempo e objetos que não usamos mais","Nada além de dinheiro","Só comida"],"answer":0}]$q$),
('meu-primeiro-orcamento', 'Meu primeiro orçamento', '🧾', 'financas', 9, 8,
 $c$Orçamento é um plano para o seu dinheiro: quanto entra, quanto sai e quanto sobra. Anote o que você recebe (mesada, tarefas) e o que pretende gastar. Se o que sai é maior do que o que entra, é hora de cortar algum gasto ou ganhar mais. Uma regra simples para começar: separe parte para gastar, parte para guardar e uma parte pequena para doar.$c$,
 $q$[{"q":"Você recebeu R$ 50 e gastou R$ 60. O que aconteceu?","options":["Sobrou dinheiro","Gastou mais do que tinha","Ficou tudo certo"],"answer":1},
     {"q":"Para que serve um orçamento?","options":["Para planejar entradas e saídas de dinheiro","Para gastar mais rápido","Para esconder dinheiro"],"answer":0}]$q$),
('o-que-sao-juros', 'O que são juros?', '📈', 'financas', 11, 10,
 $c$Juros são o preço do dinheiro no tempo. Quando você guarda dinheiro em um investimento, o banco paga juros a você. Quando você pega dinheiro emprestado, você paga juros. Exemplo: R$ 100 rendendo 1% ao mês viram R$ 101 no primeiro mês; no segundo, o 1% vale sobre R$ 101. É o chamado juro composto: o tempo trabalha a seu favor quando você investe e contra você quando você deve.$c$,
 $q$[{"q":"R$ 100 rendendo 1% ao mês valem quanto depois de um mês?","options":["R$ 100","R$ 101","R$ 110"],"answer":1},
     {"q":"Quando os juros trabalham contra você?","options":["Quando você investe","Quando você está devendo","Nunca"],"answer":1},
     {"q":"No juro composto, o rendimento do mês seguinte é calculado sobre...","options":["Só o valor inicial","O valor inicial mais os juros já ganhos","Um valor sorteado"],"answer":1}]$q$),
('golpes-e-compras-online', 'Cuidado com golpes e compras online', '🛡️', 'financas', 10, 8,
 $c$Golpistas usam mensagens com promessas boas demais: prêmios, dinheiro fácil, links para clicar. Nunca passe senhas, códigos ou dados de cartão por mensagem, e nunca faça PIX para quem você não conhece. Antes de comprar online, converse com um adulto e desconfie de preços muito abaixo do normal. Se algo parecer estranho, pare e avise seus pais.$c$,
 $q$[{"q":"Chegou uma mensagem dizendo que você ganhou um prêmio e precisa clicar num link. O que fazer?","options":["Clicar rápido","Não clicar e avisar um adulto","Responder com seus dados"],"answer":1},
     {"q":"Você pode passar o código de verificação que chegou no seu celular para outra pessoa?","options":["Sim, se pedirem com educação","Nunca","Só para amigos"],"answer":1}]$q$),
('sono-superpoder', 'Sono: o superpoder da noite', '😴', 'habitos', 6, 5,
 $c$Dormir bem ajuda a aprender, a crescer e a ficar de bom humor. Crianças de 6 a 12 anos precisam de cerca de 9 a 12 horas de sono, e adolescentes de 8 a 10 horas. Para dormir melhor: horário fixo, quarto escuro e silencioso e telas desligadas cerca de uma hora antes de deitar.$c$,
 $q$[{"q":"O que ajuda a dormir melhor?","options":["Usar o celular na cama","Ter horário fixo para dormir","Tomar refrigerante à noite"],"answer":1}]$q$),
('como-estudar-melhor', 'Como estudar melhor', '📚', 'habitos', 10, 8,
 $c$Estudar em blocos curtos funciona melhor do que horas seguidas. Experimente a técnica Pomodoro: 25 minutos de foco total e 5 minutos de pausa. Deixe o celular longe, tenha água por perto e comece pela matéria mais difícil. Revisar no dia seguinte fixa muito mais o conteúdo.$c$,
 $q$[{"q":"Quanto dura um bloco de foco na técnica Pomodoro?","options":["25 minutos","2 horas","5 minutos"],"answer":0},
     {"q":"O que ajuda a manter o foco?","options":["Celular ao lado","Celular longe","Ligar a TV"],"answer":1}]$q$),
('agua-de-onde-vem', 'Água: de onde ela vem?', '💧', 'conhecimentos', 6, 5,
 $c$A água da torneira vem de rios, represas e poços. Ela passa por uma estação de tratamento, onde é limpa, antes de chegar na sua casa. Só uma pequena parte da água do planeta é doce e fácil de usar, por isso economizar é importante: feche a torneira ao escovar os dentes e tome banhos mais curtos.$c$,
 $q$[{"q":"O que fazer para economizar água?","options":["Deixar a torneira aberta ao escovar os dentes","Fechar a torneira ao escovar os dentes","Tomar banhos bem longos"],"answer":1}]$q$);
