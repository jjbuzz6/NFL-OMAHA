-- OPTIONAL DEMO DATA ONLY. These are fictional players, not NFL data.
-- Run after schema.sql if you want to test the card mechanics before connecting a sports-data feed.
with divisions as (
  select * from (values
    ('AFC','AFC East','BUF'),('AFC','AFC North','BAL'),('AFC','AFC South','HOU'),('AFC','AFC West','KC'),
    ('NFC','NFC East','PHI'),('NFC','NFC North','DET'),('NFC','NFC South','TB'),('NFC','NFC West','SF')
  ) v(conference,division,team)
), positions as (select unnest(array['QB','RB','WR','TE']) pos), nums as (select generate_series(1,2) n)
insert into public.players(provider_id,season,name,position,team,conference,division,is_starter,season_stats)
select 'demo-'||replace(d.division,' ','-')||'-'||p.pos||'-'||n,
       2026,
       'Demo '||d.team||' '||p.pos||' '||chr(64+n),
       p.pos::public.fantasy_position,d.team,d.conference,d.division,true,
       case when p.pos='QB' then jsonb_build_object('passing_yards',1800+n*100,'passing_tds',12+n,'interceptions',4)
            when p.pos='RB' then jsonb_build_object('rushing_yards',620+n*50,'rushing_tds',5+n,'receptions',20+n*3,'receiving_yards',160)
            else jsonb_build_object('receptions',38+n*4,'receiving_yards',510+n*45,'receiving_tds',4+n) end
from divisions d cross join positions p cross join nums
on conflict(provider_id) do update set is_starter=excluded.is_starter,season_stats=excluded.season_stats;
