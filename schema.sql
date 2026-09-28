-- Fantasy Cardroom / Supabase schema
-- Run in a fresh Supabase project's SQL editor.

create extension if not exists pgcrypto;

DO $$ BEGIN
  create type public.contest_status as enum ('draft','open','locked','live','final');
EXCEPTION WHEN duplicate_object THEN null; END $$;
DO $$ BEGIN
  create type public.hand_status as enum ('building','active','complete');
EXCEPTION WHEN duplicate_object THEN null; END $$;
DO $$ BEGIN
  create type public.fantasy_position as enum ('QB','RB','WR','TE');
EXCEPTION WHEN duplicate_object THEN null; END $$;
DO $$ BEGIN
  create type public.hand_slot as enum ('QB','RB1','RB2','WR1','WR2','TE','FLEX');
EXCEPTION WHEN duplicate_object THEN null; END $$;
DO $$ BEGIN
  create type public.wildcard_type as enum ('NFL','CONFERENCE','DIVISION');
EXCEPTION WHEN duplicate_object THEN null; END $$;

create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  username text not null unique check (username ~ '^[A-Za-z0-9_]{3,24}$'),
  email text,
  credits numeric(12,2) not null default 50 check (credits >= 0),
  is_admin boolean not null default false,
  created_at timestamptz not null default now()
);

create table if not exists public.contests (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  season int not null,
  week int not null check (week between 1 and 22),
  entry_cost numeric(12,2) not null default 5 check (entry_cost > 0),
  max_hands_per_user int not null default 10 check (max_hands_per_user > 0),
  status public.contest_status not null default 'draft',
  locks_at timestamptz,
  created_by uuid references public.profiles(id),
  created_at timestamptz not null default now(),
  finalized_at timestamptz
);

create table if not exists public.players (
  id uuid primary key default gen_random_uuid(),
  provider_id text not null unique,
  season int not null,
  name text not null,
  position public.fantasy_position not null,
  team text not null,
  conference text not null check (conference in ('AFC','NFC')),
  division text not null,
  headshot_url text,
  is_starter boolean not null default false,
  season_stats jsonb not null default '{}'::jsonb,
  updated_at timestamptz not null default now()
);
create index if not exists players_pool_idx on public.players(season,is_starter,position,conference,division);

create table if not exists public.hands (
  id uuid primary key default gen_random_uuid(),
  contest_id uuid not null references public.contests(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  hand_number int not null,
  status public.hand_status not null default 'building',
  score numeric(12,2) not null default 0,
  created_at timestamptz not null default now(),
  locked_at timestamptz,
  unique(contest_id,user_id,hand_number)
);
create index if not exists hands_contest_score_idx on public.hands(contest_id,score desc);

create table if not exists public.hand_players (
  id uuid primary key default gen_random_uuid(),
  hand_id uuid not null references public.hands(id) on delete cascade,
  slot public.hand_slot not null,
  player_id uuid not null references public.players(id),
  fantasy_points numeric(12,2) not null default 0,
  created_at timestamptz not null default now(),
  unique(hand_id,slot),
  unique(hand_id,player_id)
);

create table if not exists public.draws (
  id uuid primary key default gen_random_uuid(),
  hand_id uuid not null references public.hands(id) on delete cascade,
  status text not null default 'open' check (status in ('open','selected')),
  created_at timestamptz not null default now(),
  selected_at timestamptz
);
create unique index if not exists one_open_draw_per_hand on public.draws(hand_id) where status='open';

create table if not exists public.draw_choices (
  id uuid primary key default gen_random_uuid(),
  draw_id uuid not null references public.draws(id) on delete cascade,
  player_id uuid not null references public.players(id),
  ordinal smallint not null check (ordinal between 1 and 3),
  unique(draw_id,ordinal),
  unique(draw_id,player_id)
);

create table if not exists public.wildcard_events (
  id uuid primary key default gen_random_uuid(),
  hand_id uuid not null references public.hands(id) on delete cascade,
  wildcard public.wildcard_type not null,
  target_hand_player_id uuid not null references public.hand_players(id) on delete cascade,
  old_player_id uuid not null references public.players(id),
  new_player_id uuid not null references public.players(id),
  created_at timestamptz not null default now(),
  unique(hand_id,wildcard),
  unique(hand_id,target_hand_player_id)
);

create table if not exists public.player_week_stats (
  player_id uuid not null references public.players(id) on delete cascade,
  season int not null,
  week int not null,
  fantasy_points numeric(12,2) not null default 0,
  stats jsonb not null default '{}'::jsonb,
  game_status text,
  updated_at timestamptz not null default now(),
  primary key(player_id,season,week)
);

create table if not exists public.credit_ledger (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  amount numeric(12,2) not null,
  balance_after numeric(12,2) not null,
  reason text not null,
  contest_id uuid references public.contests(id),
  hand_id uuid references public.hands(id),
  created_at timestamptz not null default now()
);

create table if not exists public.payouts (
  id uuid primary key default gen_random_uuid(),
  contest_id uuid not null references public.contests(id) on delete cascade,
  hand_id uuid not null references public.hands(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  place int not null,
  percentage numeric(8,6) not null,
  amount numeric(12,2) not null,
  created_at timestamptz not null default now(),
  unique(contest_id,hand_id)
);

-- New user -> profile. The 50-credit starting bankroll is convenient for an MVP/demo;
-- change it here if credits will only be granted by an administrator.
create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path=public as $$
declare
  wanted text;
begin
  wanted := coalesce(nullif(new.raw_user_meta_data->>'username',''), split_part(new.email,'@',1));
  wanted := regexp_replace(wanted, '[^A-Za-z0-9_]', '_', 'g');
  if length(wanted) < 3 then wanted := 'player_' || left(new.id::text,8); end if;
  begin
    insert into public.profiles(id,username,email) values(new.id,left(wanted,24),new.email);
  exception when unique_violation then
    insert into public.profiles(id,username,email) values(new.id,left(wanted,15)||'_'||left(new.id::text,8),new.email);
  end;
  return new;
end $$;
drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created after insert on auth.users for each row execute function public.handle_new_user();

-- Keep hand totals current whenever an individual card's score changes.
create or replace function public.recalc_hand_score()
returns trigger language plpgsql security definer set search_path=public as $$
declare hid uuid;
begin
  hid := coalesce(new.hand_id,old.hand_id);
  update public.hands h set score = coalesce((select sum(hp.fantasy_points) from public.hand_players hp where hp.hand_id=hid),0) where h.id=hid;
  return coalesce(new,old);
end $$;
drop trigger if exists trg_hand_score on public.hand_players;
create trigger trg_hand_score after insert or update of fantasy_points or delete on public.hand_players for each row execute function public.recalc_hand_score();

-- Push a synced player/week score into every matching contest hand.
create or replace function public.propagate_week_score()
returns trigger language plpgsql security definer set search_path=public as $$
begin
  update public.hand_players hp
     set fantasy_points = new.fantasy_points
    from public.hands h, public.contests c
   where hp.hand_id=h.id and h.contest_id=c.id
     and hp.player_id=new.player_id and c.season=new.season and c.week=new.week;
  return new;
end $$;
drop trigger if exists trg_week_score on public.player_week_stats;
create trigger trg_week_score after insert or update of fantasy_points on public.player_week_stats for each row execute function public.propagate_week_score();

-- Small SECURITY DEFINER helper avoids recursive RLS checks when policies need admin status.
create or replace function public.is_admin()
returns boolean language sql stable security definer set search_path=public as $$
  select coalesce((select is_admin from public.profiles where id=auth.uid()),false);
$$;

-- RLS
alter table public.profiles enable row level security;
alter table public.contests enable row level security;
alter table public.players enable row level security;
alter table public.hands enable row level security;
alter table public.hand_players enable row level security;
alter table public.draws enable row level security;
alter table public.draw_choices enable row level security;
alter table public.wildcard_events enable row level security;
alter table public.player_week_stats enable row level security;
alter table public.credit_ledger enable row level security;
alter table public.payouts enable row level security;

drop policy if exists profiles_own on public.profiles;
create policy profiles_own on public.profiles for select to authenticated using (id=auth.uid() or public.is_admin());
drop policy if exists contests_read on public.contests;
create policy contests_read on public.contests for select to authenticated using (true);
drop policy if exists players_read on public.players;
create policy players_read on public.players for select to authenticated using (true);
drop policy if exists hands_own on public.hands;
create policy hands_own on public.hands for select to authenticated using (user_id=auth.uid() or public.is_admin());
drop policy if exists hand_players_own on public.hand_players;
create policy hand_players_own on public.hand_players for select to authenticated using (exists(select 1 from public.hands h where h.id=hand_id and (h.user_id=auth.uid() or public.is_admin())));
drop policy if exists wildcard_own on public.wildcard_events;
create policy wildcard_own on public.wildcard_events for select to authenticated using (exists(select 1 from public.hands h where h.id=hand_id and h.user_id=auth.uid()));
drop policy if exists stats_read on public.player_week_stats;
create policy stats_read on public.player_week_stats for select to authenticated using (true);
drop policy if exists ledger_own on public.credit_ledger;
create policy ledger_own on public.credit_ledger for select to authenticated using (user_id=auth.uid() or public.is_admin());
drop policy if exists payouts_read on public.payouts;
create policy payouts_read on public.payouts for select to authenticated using (user_id=auth.uid() or public.is_admin());
-- No direct policies for draws/draw_choices: mystery identities are only exposed through safe RPCs.

-- Read models
create or replace view public.contest_lobby as
select c.id,c.name,c.season,c.week,c.entry_cost,c.max_hands_per_user,c.status,c.locks_at,
       count(h.id)::int as entry_count,
       (count(h.id)*c.entry_cost)::numeric(12,2) as pot_credits,
       count(h.id) filter(where h.user_id=auth.uid())::int as my_hand_count
from public.contests c left join public.hands h on h.contest_id=c.id
where c.status in ('open','locked','live','final')
group by c.id;

create or replace view public.my_hands as
select h.id hand_id,h.hand_number,h.status,h.score,h.created_at,c.name contest_name,c.week,c.season,
       count(hp.id)::int player_count
from public.hands h join public.contests c on c.id=h.contest_id
left join public.hand_players hp on hp.hand_id=h.id
where h.user_id=auth.uid()
group by h.id,c.id;

create or replace view public.hand_detail as
select h.id hand_id,h.hand_number,h.status,h.score,c.name contest_name,c.week,c.season,
       coalesce((select jsonb_agg(jsonb_build_object(
         'hand_player_id',hp.id,'slot',hp.slot,'player_id',p.id,'name',p.name,'position',p.position,
         'team',p.team,'conference',p.conference,'division',p.division,'headshot_url',p.headshot_url,
         'season_stats',p.season_stats,'fantasy_points',hp.fantasy_points
       ) order by array_position(array['QB','RB1','RB2','WR1','WR2','TE','FLEX'],hp.slot::text))
       from public.hand_players hp join public.players p on p.id=hp.player_id where hp.hand_id=h.id),'[]'::jsonb) players,
       coalesce((select jsonb_agg(w.wildcard) from public.wildcard_events w where w.hand_id=h.id),'[]'::jsonb) wildcards_used
from public.hands h join public.contests c on c.id=h.contest_id
where h.user_id=auth.uid();

create or replace view public.leaderboard as
select * from (
  select h.contest_id,h.id hand_id,h.hand_number,h.user_id,p.username,h.score,
         rank() over(partition by h.contest_id order by h.score desc)::int as rank,
         (h.user_id=auth.uid()) is_mine,
         array(select pl.position::text||':'||pl.team from public.hand_players hp join public.players pl on pl.id=hp.player_id where hp.hand_id=h.id order by hp.slot) player_abbrs
  from public.hands h join public.profiles p on p.id=h.user_id
  where h.status in ('active','complete')
) x;

create or replace view public.admin_users as
select p.id,p.username,p.email,p.credits,p.created_at
from public.profiles p
where public.is_admin();

create or replace view public.admin_contests as
select c.*,count(h.id)::int entry_count,(count(h.id)*c.entry_cost)::numeric(12,2) pot_credits
from public.contests c left join public.hands h on h.contest_id=c.id
where public.is_admin()
group by c.id;

grant select on public.contest_lobby,public.my_hands,public.hand_detail,public.leaderboard,public.admin_users,public.admin_contests to authenticated;

-- Atomically purchase an entry.
create or replace function public.buy_hand(p_contest_id uuid)
returns uuid language plpgsql security definer set search_path=public as $$
declare c public.contests%rowtype; p public.profiles%rowtype; n int; hid uuid;
begin
  if auth.uid() is null then raise exception 'Sign in required'; end if;
  select * into c from public.contests where id=p_contest_id for update;
  if not found then raise exception 'Contest not found'; end if;
  if c.status<>'open' or (c.locks_at is not null and now()>=c.locks_at) then raise exception 'Contest is not open for entries'; end if;
  select count(*) into n from public.hands where contest_id=c.id and user_id=auth.uid();
  if n>=c.max_hands_per_user then raise exception 'Maximum % hands reached for this contest',c.max_hands_per_user; end if;
  select * into p from public.profiles where id=auth.uid() for update;
  if p.credits<c.entry_cost then raise exception 'Not enough credits'; end if;
  update public.profiles set credits=credits-c.entry_cost where id=p.id returning * into p;
  insert into public.hands(contest_id,user_id,hand_number) values(c.id,p.id,n+1) returning id into hid;
  insert into public.credit_ledger(user_id,amount,balance_after,reason,contest_id,hand_id) values(p.id,-c.entry_cost,p.credits,'Hand entry',c.id,hid);
  return hid;
end $$;

-- Deal three masked choices. Only position + division leave the server.
create or replace function public.create_draw(p_hand_id uuid)
returns table(choice_id uuid,"position" text,division text)
language plpgsql security definer set search_path=public as $$
declare h public.hands%rowtype; c public.contests%rowtype; did uuid; elig text[] := '{}'; q int; r int; w int; t int; flex_open boolean; rec record; ord int:=0; choice_count int;
begin
  select * into h from public.hands where id=p_hand_id and user_id=auth.uid() for update;
  if not found then raise exception 'Hand not found'; end if;
  if h.status<>'building' then raise exception 'Hand is already locked'; end if;
  select * into c from public.contests where id=h.contest_id;
  if c.status<>'open' or (c.locks_at is not null and now()>=c.locks_at) then raise exception 'The contest is locked; this hand can no longer be changed'; end if;

  select d.id into did from public.draws d where d.hand_id=h.id and d.status='open' limit 1;
  if did is not null then
    return query select dc.id,p.position::text,p.division from public.draw_choices dc join public.players p on p.id=dc.player_id where dc.draw_id=did order by dc.ordinal;
    return;
  end if;

  select count(*) filter(where p.position='QB'),count(*) filter(where p.position='RB'),count(*) filter(where p.position='WR'),count(*) filter(where p.position='TE'),
         not exists(select 1 from public.hand_players x where x.hand_id=h.id and x.slot='FLEX')
    into q,r,w,t,flex_open
    from public.hand_players hp join public.players p on p.id=hp.player_id where hp.hand_id=h.id;
  if q<1 then elig:=array_append(elig,'QB'); end if;
  if r<2 or flex_open then elig:=array_append(elig,'RB'); end if;
  if w<2 or flex_open then elig:=array_append(elig,'WR'); end if;
  if t<1 or flex_open then elig:=array_append(elig,'TE'); end if;
  if coalesce(array_length(elig,1),0)=0 then raise exception 'No roster slots remain'; end if;

  insert into public.draws(hand_id) values(h.id) returning id into did;
  for rec in
    select p.id from public.players p
    where p.season=c.season and p.is_starter and p.position::text=any(elig)
      and not exists(select 1 from public.hand_players hp where hp.hand_id=h.id and hp.player_id=p.id)
    order by random() limit 3
  loop
    ord:=ord+1; insert into public.draw_choices(draw_id,player_id,ordinal) values(did,rec.id,ord);
  end loop;
  select count(*) into choice_count from public.draw_choices where draw_id=did;
  if choice_count<3 then raise exception 'The starter pool does not contain enough eligible players. Run the starter sync first.'; end if;
  return query select dc.id,p.position::text,p.division from public.draw_choices dc join public.players p on p.id=dc.player_id where dc.draw_id=did order by dc.ordinal;
end $$;

create or replace function public.select_draw_choice(p_choice_id uuid)
returns jsonb language plpgsql security definer set search_path=public as $$
declare ch record; h public.hands%rowtype; c public.contests%rowtype; p public.players%rowtype; chosen_slot public.hand_slot; pts numeric:=0; player_count int;
begin
  select dc.id choice_id,dc.draw_id,dc.player_id,d.hand_id,d.status draw_status into ch
  from public.draw_choices dc join public.draws d on d.id=dc.draw_id where dc.id=p_choice_id;
  if not found then raise exception 'Card not found'; end if;
  select * into h from public.hands where id=ch.hand_id and user_id=auth.uid() for update;
  if not found or h.status<>'building' or ch.draw_status<>'open' then raise exception 'This deal is no longer active'; end if;
  select * into c from public.contests where id=h.contest_id;
  if c.status<>'open' or (c.locks_at is not null and now()>=c.locks_at) then raise exception 'The contest is locked; this hand can no longer be changed'; end if;
  select * into p from public.players where id=ch.player_id;

  if p.position='QB' then chosen_slot:='QB';
  elsif p.position='RB' then
    if not exists(select 1 from public.hand_players where hand_id=h.id and slot='RB1') then chosen_slot:='RB1';
    elsif not exists(select 1 from public.hand_players where hand_id=h.id and slot='RB2') then chosen_slot:='RB2'; else chosen_slot:='FLEX'; end if;
  elsif p.position='WR' then
    if not exists(select 1 from public.hand_players where hand_id=h.id and slot='WR1') then chosen_slot:='WR1';
    elsif not exists(select 1 from public.hand_players where hand_id=h.id and slot='WR2') then chosen_slot:='WR2'; else chosen_slot:='FLEX'; end if;
  elsif p.position='TE' then
    if not exists(select 1 from public.hand_players where hand_id=h.id and slot='TE') then chosen_slot:='TE'; else chosen_slot:='FLEX'; end if;
  end if;
  if chosen_slot is null or exists(select 1 from public.hand_players where hand_id=h.id and slot=chosen_slot) then raise exception 'That position is already full'; end if;
  select coalesce(fantasy_points,0) into pts from public.player_week_stats where player_id=p.id and season=c.season and week=c.week;
  pts:=coalesce(pts,0);
  insert into public.hand_players(hand_id,slot,player_id,fantasy_points) values(h.id,chosen_slot,p.id,pts);
  update public.draws set status='selected',selected_at=now() where id=ch.draw_id;
  select count(*) into player_count from public.hand_players where hand_id=h.id;
  if player_count=7 then update public.hands set status='active',locked_at=now() where id=h.id; end if;
  return jsonb_build_object('name',p.name,'position',p.position,'team',p.team,'conference',p.conference,'division',p.division,'headshot_url',p.headshot_url,'season_stats',p.season_stats,'fantasy_points',pts);
end $$;

create or replace function public.apply_wildcard(p_hand_player_id uuid,p_type public.wildcard_type)
returns jsonb language plpgsql security definer set search_path=public as $$
declare hp public.hand_players%rowtype; h public.hands%rowtype; c public.contests%rowtype; oldp public.players%rowtype; newp public.players%rowtype; pts numeric:=0;
begin
  select * into hp from public.hand_players where id=p_hand_player_id for update;
  if not found then raise exception 'Player card not found'; end if;
  select * into h from public.hands where id=hp.hand_id and user_id=auth.uid() for update;
  if not found or h.status<>'active' then raise exception 'Wildcards are available only after a hand is complete'; end if;
  if exists(select 1 from public.wildcard_events where hand_id=h.id and wildcard=p_type) then raise exception '% wildcard has already been used',p_type; end if;
  if exists(select 1 from public.wildcard_events where hand_id=h.id and target_hand_player_id=hp.id) then raise exception 'Each wildcard must be used on a different player'; end if;
  select * into c from public.contests where id=h.contest_id;
  if c.status<>'open' or (c.locks_at is not null and now()>=c.locks_at) then raise exception 'The contest is locked; wildcards can no longer be used'; end if;
  select * into oldp from public.players where id=hp.player_id;

  select p.* into newp from public.players p
   where p.season=c.season and p.is_starter and p.position=oldp.position and p.id<>oldp.id
     and not exists(select 1 from public.hand_players x where x.hand_id=h.id and x.player_id=p.id)
     and (p_type='NFL' or (p_type='CONFERENCE' and p.conference=oldp.conference) or (p_type='DIVISION' and p.division=oldp.division))
   order by random() limit 1;
  if not found then raise exception 'No eligible replacement is available for this wildcard'; end if;
  select coalesce(fantasy_points,0) into pts from public.player_week_stats where player_id=newp.id and season=c.season and week=c.week;
  pts:=coalesce(pts,0);
  update public.hand_players set player_id=newp.id,fantasy_points=pts where id=hp.id;
  insert into public.wildcard_events(hand_id,wildcard,target_hand_player_id,old_player_id,new_player_id) values(h.id,p_type,hp.id,oldp.id,newp.id);
  return jsonb_build_object('name',newp.name,'position',newp.position,'team',newp.team,'conference',newp.conference,'division',newp.division,'headshot_url',newp.headshot_url,'season_stats',newp.season_stats,'fantasy_points',pts);
end $$;

create or replace function public.require_admin()
returns void language plpgsql security definer set search_path=public as $$
begin
  if not exists(select 1 from public.profiles where id=auth.uid() and is_admin) then raise exception 'Administrator access required'; end if;
end $$;

create or replace function public.admin_create_contest(p_name text,p_season int,p_week int,p_locks_at timestamptz default null)
returns uuid language plpgsql security definer set search_path=public as $$ declare cid uuid; begin
  perform public.require_admin();
  insert into public.contests(name,season,week,locks_at,status,created_by) values(p_name,p_season,p_week,p_locks_at,'open',auth.uid()) returning id into cid;
  return cid;
end $$;

create or replace function public.admin_adjust_credits(p_user_id uuid,p_amount numeric,p_note text default 'Admin adjustment')
returns numeric language plpgsql security definer set search_path=public as $$ declare bal numeric; begin
  perform public.require_admin();
  if p_amount=0 then raise exception 'Amount cannot be zero'; end if;
  update public.profiles set credits=credits+p_amount where id=p_user_id and credits+p_amount>=0 returning credits into bal;
  if bal is null then raise exception 'User not found or adjustment would make balance negative'; end if;
  insert into public.credit_ledger(user_id,amount,balance_after,reason) values(p_user_id,p_amount,bal,p_note);
  return bal;
end $$;

create or replace function public.admin_set_contest_status(p_contest_id uuid,p_status public.contest_status)
returns void language plpgsql security definer set search_path=public as $$ begin
  perform public.require_admin(); update public.contests set status=p_status where id=p_contest_id;
end $$;

create or replace function public.admin_finalize_contest(p_contest_id uuid)
returns void language plpgsql security definer set search_path=public as $$
declare pot numeric; rec record; bal numeric;
begin
  perform public.require_admin();
  if exists(select 1 from public.payouts where contest_id=p_contest_id) then raise exception 'This contest has already been paid'; end if;
  if not exists(select 1 from public.contests where id=p_contest_id and status in ('locked','live')) then raise exception 'Contest must be locked or live before finalizing'; end if;
  select count(h.id)*c.entry_cost into pot from public.contests c left join public.hands h on h.contest_id=c.id where c.id=p_contest_id group by c.id;
  pot:=coalesce(pot,0);

  for rec in
    with ranked as (
      select h.id hand_id,h.user_id,h.score,
             rank() over(order by h.score desc)::int place,
             count(*) over(partition by h.score)::int tie_count
      from public.hands h where h.contest_id=p_contest_id and h.status in ('active','complete')
    ), prizes(place,pct) as (values (1,.60::numeric),(2,.30::numeric),(3,.10::numeric))
    select r.*,
      coalesce((select sum(p.pct) from prizes p where p.place>=r.place and p.place<r.place+r.tie_count),0)/r.tie_count as share
    from ranked r where r.place<=3
  loop
    insert into public.payouts(contest_id,hand_id,user_id,place,percentage,amount)
    values(p_contest_id,rec.hand_id,rec.user_id,rec.place,rec.share,round(pot*rec.share,2));
    update public.profiles set credits=credits+round(pot*rec.share,2) where id=rec.user_id returning credits into bal;
    insert into public.credit_ledger(user_id,amount,balance_after,reason,contest_id,hand_id)
    values(rec.user_id,round(pot*rec.share,2),bal,'Contest payout',p_contest_id,rec.hand_id);
  end loop;
  update public.hands set status='complete' where contest_id=p_contest_id and status='active';
  update public.contests set status='final',finalized_at=now() where id=p_contest_id;
end $$;

grant execute on function public.buy_hand(uuid) to authenticated;
grant execute on function public.create_draw(uuid) to authenticated;
grant execute on function public.select_draw_choice(uuid) to authenticated;
grant execute on function public.apply_wildcard(uuid,public.wildcard_type) to authenticated;
grant execute on function public.admin_create_contest(text,int,int,timestamptz) to authenticated;
grant execute on function public.admin_adjust_credits(uuid,numeric,text) to authenticated;
grant execute on function public.admin_set_contest_status(uuid,public.contest_status) to authenticated;
grant execute on function public.admin_finalize_contest(uuid) to authenticated;

-- Enable realtime updates for live hand scores. If the table is already in the publication, ignore the duplicate error.
DO $$ BEGIN
  alter publication supabase_realtime add table public.hands;
EXCEPTION WHEN duplicate_object THEN null; END $$;

-- After your own account signs up, make yourself the administrator:
-- update public.profiles set is_admin=true where email='YOUR_EMAIL@example.com';
