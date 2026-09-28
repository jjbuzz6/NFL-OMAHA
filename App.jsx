import React, { useEffect, useMemo, useState } from 'react'
import {
  BadgeDollarSign,
  ChevronRight,
  CircleDollarSign,
  Crown,
  Dices,
  Flame,
  Gauge,
  Layers3,
  LogOut,
  RefreshCw,
  ShieldCheck,
  Sparkles,
  Spade,
  Trophy,
  UserRound,
  Users,
  WandSparkles,
} from 'lucide-react'
import { configured, supabase } from './supabase.js'

const SLOT_ORDER = ['QB', 'RB1', 'RB2', 'WR1', 'WR2', 'TE', 'FLEX']
const SLOT_LABELS = { QB: 'QB', RB1: 'RB', RB2: 'RB', WR1: 'WR', WR2: 'WR', TE: 'TE', FLEX: 'FLEX' }
const WILDCARDS = [
  { key: 'NFL', title: 'NFL Wildcard', text: 'Random same-position player from anywhere in the NFL.' },
  { key: 'CONFERENCE', title: 'Conference Wildcard', text: 'Random same-position player from the same AFC/NFC conference.' },
  { key: 'DIVISION', title: 'Division Wildcard', text: 'Random same-position player from the same division.' },
]

function fmt(n = 0) { return Number(n || 0).toFixed(1) }

function Logo() {
  return <div className="logo"><div className="logo-mark"><Spade size={18}/><span>FC</span></div><div><strong>FANTASY</strong><span>CARDROOM</span></div></div>
}

function Shell({ profile, active, setActive, onLogout, children }) {
  return <div className="app-shell">
    <aside className="sidebar">
      <Logo />
      <nav>
        {[
          ['lobby', Layers3, 'Contest Lobby'],
          ['hands', Spade, 'My Hands'],
          ['leaderboard', Trophy, 'Leaderboard'],
          ...(profile?.is_admin ? [['admin', ShieldCheck, 'Admin Room']] : []),
        ].map(([id, Icon, label]) => <button key={id} className={active === id ? 'active' : ''} onClick={() => setActive(id)}><Icon size={18}/>{label}</button>)}
      </nav>
      <div className="sidebar-bottom">
        <div className="credit-chip"><CircleDollarSign size={18}/><div><span>Bankroll</span><b>{profile?.credits ?? 0} credits</b></div></div>
        <button className="ghost wide" onClick={onLogout}><LogOut size={17}/> Sign out</button>
      </div>
    </aside>
    <main>{children}</main>
  </div>
}

function Auth() {
  const [mode, setMode] = useState('login')
  const [email, setEmail] = useState('')
  const [password, setPassword] = useState('')
  const [username, setUsername] = useState('')
  const [message, setMessage] = useState('')
  const [busy, setBusy] = useState(false)

  async function submit(e) {
    e.preventDefault(); setBusy(true); setMessage('')
    try {
      if (mode === 'signup') {
        const { error } = await supabase.auth.signUp({ email, password, options: { data: { username } } })
        if (error) throw error
        setMessage('Account created. Check your email if confirmations are enabled.')
      } else {
        const { error } = await supabase.auth.signInWithPassword({ email, password })
        if (error) throw error
      }
    } catch (err) { setMessage(err.message) }
    finally { setBusy(false) }
  }

  return <div className="auth-wrap">
    <div className="felt-light"/>
    <div className="auth-card">
      <Logo />
      <div className="eyebrow">PRIVATE TABLE · FANTASY FOOTBALL</div>
      <h1>Build the hand.<br/><em>Beat the room.</em></h1>
      <p>Draw hidden NFL starters, lock a seven-player fantasy hand, use your wildcards, and sweat the live leaderboard.</p>
      <form onSubmit={submit}>
        {mode === 'signup' && <label>Username<input required minLength="3" maxLength="24" value={username} onChange={e => setUsername(e.target.value)} placeholder="riverking"/></label>}
        <label>Email<input required type="email" value={email} onChange={e => setEmail(e.target.value)} placeholder="you@example.com"/></label>
        <label>Password<input required minLength="8" type="password" value={password} onChange={e => setPassword(e.target.value)} placeholder="••••••••"/></label>
        <button className="primary" disabled={busy}>{busy ? 'Dealing…' : mode === 'signup' ? 'Create player' : 'Enter cardroom'} <ChevronRight size={17}/></button>
      </form>
      {message && <div className="notice">{message}</div>}
      <button className="link" onClick={() => setMode(mode === 'login' ? 'signup' : 'login')}>{mode === 'login' ? 'Need a username? Create an account' : 'Already have a seat? Sign in'}</button>
    </div>
  </div>
}

function Topbar({ profile, title, kicker }) {
  return <header className="topbar"><div><div className="eyebrow">{kicker}</div><h2>{title}</h2></div><div className="user-pill"><UserRound size={18}/><div><b>{profile?.username}</b><span>{profile?.is_admin ? 'Administrator' : 'Player'}</span></div></div></header>
}

function ContestLobby({ profile, onOpenHand }) {
  const [contests, setContests] = useState([])
  const [busy, setBusy] = useState(null)
  const [error, setError] = useState('')
  useEffect(() => { load() }, [])
  async function load() {
    const { data, error } = await supabase.from('contest_lobby').select('*').order('week')
    if (error) setError(error.message); else setContests(data || [])
  }
  async function buy(contest) {
    setBusy(contest.id); setError('')
    const { data, error } = await supabase.rpc('buy_hand', { p_contest_id: contest.id })
    setBusy(null)
    if (error) return setError(error.message)
    onOpenHand(data)
  }
  return <>
    <Topbar profile={profile} kicker="THE CAGE" title="Contest Lobby"/>
    <section className="content">
      <div className="hero-panel">
        <div><div className="eyebrow gold">WEEKLY TABLES</div><h3>Seven cards. Three wildcards.<br/>One live sweat.</h3><p>Every entry costs five credits. You can build up to ten hands in each contest.</p></div>
        <div className="pot-visual"><div className="chip c1">5</div><div className="chip c2">5</div><div className="chip c3">5</div><span>60 / 30 / 10</span></div>
      </div>
      {error && <div className="notice error">{error}</div>}
      <div className="section-head"><h3>Open contests</h3><span>{contests.length} tables</span></div>
      <div className="contest-grid">
        {contests.map(c => <article className="contest-card" key={c.id}>
          <div className="contest-top"><span className={`status ${c.status}`}>{c.status}</span><span>Week {c.week} · {c.season}</span></div>
          <h3>{c.name}</h3>
          <div className="contest-stats">
            <div><Users/><b>{c.entry_count}</b><span>hands</span></div>
            <div><BadgeDollarSign/><b>{c.pot_credits}</b><span>credit pot</span></div>
            <div><Spade/><b>{c.my_hand_count}/10</b><span>your hands</span></div>
          </div>
          <div className="payout-row"><span><Crown size={15}/> 1st {fmt(c.pot_credits * .6)}</span><span>2nd {fmt(c.pot_credits * .3)}</span><span>3rd {fmt(c.pot_credits * .1)}</span></div>
          <button className="primary wide" onClick={() => buy(c)} disabled={busy === c.id || c.status !== 'open' || c.my_hand_count >= 10 || profile.credits < c.entry_cost}>{busy === c.id ? 'Buying…' : `Buy hand · ${c.entry_cost} credits`} <ChevronRight size={17}/></button>
        </article>)}
        {!contests.length && <div className="empty">No open contests yet. The administrator can create one in the Admin Room.</div>}
      </div>
    </section>
  </>
}

function CardBack({ card, onPick, disabled }) {
  return <button className="playing-card back" onClick={() => onPick(card.choice_id)} disabled={disabled}>
    <div className="corner"><b>{card.position}</b><Spade size={15}/></div>
    <div className="card-back-pattern"><div className="mini-ball">◆</div><strong>{card.division}</strong><span>{card.position}</span><small>MYSTERY STARTER</small></div>
    <div className="corner bottom"><b>{card.position}</b><Spade size={15}/></div>
  </button>
}

function StatLine({ player }) {
  const s = player?.season_stats || {}
  if (player?.position === 'QB') return <><span>{s.passing_yards ?? 0} PYD</span><span>{s.passing_tds ?? 0} PTD</span><span>{s.interceptions ?? 0} INT</span></>
  if (player?.position === 'RB') return <><span>{s.rushing_yards ?? 0} RYD</span><span>{s.receptions ?? 0} REC</span><span>{(s.rushing_tds ?? 0)+(s.receiving_tds ?? 0)} TD</span></>
  return <><span>{s.receptions ?? 0} REC</span><span>{s.receiving_yards ?? 0} YD</span><span>{s.receiving_tds ?? 0} TD</span></>
}

function PlayerCard({ player, slot, compact=false, onWildcard }) {
  if (!player) return <div className={`playing-card slot-empty ${compact ? 'compact' : ''}`}><span>{SLOT_LABELS[slot]}</span><small>OPEN SLOT</small></div>
  return <div className={`playing-card player ${compact ? 'compact' : ''}`}>
    <div className="player-photo">{player.headshot_url ? <img src={player.headshot_url} alt={player.name}/> : <div className="silhouette"><UserRound size={48}/></div>}</div>
    <div className="player-card-body"><div className="player-meta"><span>{player.position} · {player.team}</span><span>{player.division}</span></div><h4>{player.name}</h4><div className="mini-stats"><StatLine player={player}/></div><div className="points"><Flame size={14}/>{fmt(player.fantasy_points)} PTS</div></div>
    {onWildcard && <button className="card-action" onClick={() => onWildcard(player)}><WandSparkles size={15}/> Wildcard</button>}
  </div>
}

function HandBuilder({ profile, handId, onBack }) {
  const [hand, setHand] = useState(null)
  const [cards, setCards] = useState([])
  const [loading, setLoading] = useState(true)
  const [reveal, setReveal] = useState(null)
  const [error, setError] = useState('')
  const [wildTarget, setWildTarget] = useState(null)

  useEffect(() => { loadHand() }, [handId])
  async function loadHand() {
    setLoading(true)
    const { data, error } = await supabase.from('hand_detail').select('*').eq('hand_id', handId).single()
    if (error) { setError(error.message); setLoading(false); return }
    setHand(data)
    setLoading(false)
    if (data.status === 'building') await draw()
  }
  async function draw() {
    const { data, error } = await supabase.rpc('create_draw', { p_hand_id: handId })
    if (error) setError(error.message); else setCards(data || [])
  }
  async function pick(choiceId) {
    setError('')
    const { data, error } = await supabase.rpc('select_draw_choice', { p_choice_id: choiceId })
    if (error) return setError(error.message)
    setReveal(data)
    setCards([])
    setTimeout(async () => { setReveal(null); await loadHand() }, 1100)
  }
  async function wildcard(type) {
    if (!wildTarget) return
    const { data, error } = await supabase.rpc('apply_wildcard', { p_hand_player_id: wildTarget.hand_player_id, p_type: type })
    if (error) return setError(error.message)
    setWildTarget(null); setReveal(data); setTimeout(async () => { setReveal(null); await loadHand() }, 1100)
  }

  const playersBySlot = useMemo(() => Object.fromEntries((hand?.players || []).map(p => [p.slot, p])), [hand])
  if (loading) return <div className="loading"><Dices className="spin"/> Shuffling the deck…</div>
  return <>
    <Topbar profile={profile} kicker={`HAND #${hand?.hand_number ?? ''}`} title={hand?.contest_name || 'Build Your Hand'}/>
    <section className="content builder">
      <button className="link back-link" onClick={onBack}>← Back to my hands</button>
      <div className="builder-head"><div><div className="eyebrow gold">{hand?.status === 'building' ? 'DEAL IN PROGRESS' : 'HAND LOCKED'}</div><h3>{hand?.status === 'building' ? `${hand?.players?.length || 0} of 7 cards selected` : `${fmt(hand?.score)} live points`}</h3></div><div className="progress"><span style={{width:`${((hand?.players?.length || 0)/7)*100}%`}}/></div></div>
      {error && <div className="notice error">{error}</div>}
      <div className="hand-rack">{SLOT_ORDER.map(slot => <div key={slot}><div className="slot-label">{slot}</div><PlayerCard compact slot={slot} player={playersBySlot[slot]} onWildcard={hand?.status === 'active' ? setWildTarget : null}/></div>)}</div>
      {hand?.status === 'building' && <div className="deal-zone">
        <div className="deal-title"><Dices/><div><h3>Choose one card</h3><p>You can see only position and division until you commit.</p></div></div>
        <div className="deal-cards">{cards.map(c => <CardBack key={c.choice_id} card={c} onPick={pick} disabled={Boolean(reveal)}/>)}</div>
      </div>}
      {hand?.status === 'active' && <div className="wild-zone"><div><div className="eyebrow gold">THE DRAW IS CLOSED</div><h3>Three wildcards remain in your sleeve.</h3><p>Select a player card above, then choose the scope of the random redraw.</p></div><div className="wild-summary">{WILDCARDS.map(w => <div key={w.key}><WandSparkles size={16}/><span>{w.title}</span><b>{hand?.wildcards_used?.includes(w.key) ? 'USED' : 'LIVE'}</b></div>)}</div></div>}
    </section>
    {reveal && <div className="modal"><div className="reveal-wrap"><div className="eyebrow gold">CARD REVEALED</div><PlayerCard player={reveal}/><Sparkles className="spark s1"/><Sparkles className="spark s2"/></div></div>}
    {wildTarget && <div className="modal"><div className="wild-modal"><button className="modal-x" onClick={() => setWildTarget(null)}>×</button><div className="eyebrow gold">RESHUFFLE {wildTarget.name}</div><h3>Choose your wildcard</h3><p>The replacement is random, cannot duplicate another player in this hand, and stays at the same fantasy position.</p>{WILDCARDS.map(w => <button key={w.key} className="wild-choice" disabled={hand?.wildcards_used?.includes(w.key)} onClick={() => wildcard(w.key)}><WandSparkles/><div><b>{w.title}</b><span>{w.text}</span></div><ChevronRight/></button>)}</div></div>}
  </>
}

function MyHands({ profile, onOpen }) {
  const [hands, setHands] = useState([])
  useEffect(() => { load() }, [])
  async function load() {
    const { data } = await supabase.from('my_hands').select('*').order('created_at', { ascending: false })
    setHands(data || [])
  }
  return <><Topbar profile={profile} kicker="YOUR ACTION" title="My Hands"/><section className="content"><div className="section-head"><h3>Active & recent hands</h3><span>{hands.length} total</span></div><div className="hands-list">{hands.map(h => <button key={h.hand_id} onClick={() => onOpen(h.hand_id)}><div className="hand-number"><Spade/>#{h.hand_number}</div><div className="hand-copy"><b>{h.contest_name}</b><span>Week {h.week} · {h.player_count}/7 players · {h.status}</span></div><div className="hand-score"><b>{fmt(h.score)}</b><span>PTS</span></div><ChevronRight/></button>)}{!hands.length && <div className="empty">You do not have any hands yet. Buy one from the Contest Lobby.</div>}</div></section></>
}

function Leaderboard({ profile }) {
  const [contests, setContests] = useState([])
  const [contestId, setContestId] = useState('')
  const [rows, setRows] = useState([])
  useEffect(() => { (async()=>{ const {data}=await supabase.from('contest_lobby').select('id,name,week').order('week'); setContests(data||[]); if(data?.[0]) setContestId(data[0].id) })() }, [])
  useEffect(() => { if (!contestId) return; load(); const channel=supabase.channel(`leader-${contestId}`).on('postgres_changes',{event:'UPDATE',schema:'public',table:'hands',filter:`contest_id=eq.${contestId}`},load).subscribe(); return()=>supabase.removeChannel(channel) }, [contestId])
  async function load(){ const {data}=await supabase.from('leaderboard').select('*').eq('contest_id',contestId).order('rank'); setRows(data||[]) }
  return <><Topbar profile={profile} kicker="LIVE ROOM" title="Leaderboard"/><section className="content"><div className="leader-controls"><select value={contestId} onChange={e=>setContestId(e.target.value)}>{contests.map(c=><option value={c.id} key={c.id}>{c.name} · Wk {c.week}</option>)}</select><div className="live-dot"><span/> LIVE SCORING</div></div><div className="leader-table"><div className="leader-head"><span>Rank</span><span>Player / Hand</span><span>Players</span><span>Score</span></div>{rows.map(r=><div className={`leader-row ${r.is_mine?'mine':''}`} key={r.hand_id}><div className="rank">{r.rank <= 3 ? <Trophy size={18}/> : null}#{r.rank}</div><div><b>{r.username}</b><span>Hand #{r.hand_number}</span></div><div className="tiny-lineup">{(r.player_abbrs||[]).map((p,i)=><span key={i}>{p}</span>)}</div><div className="leader-score">{fmt(r.score)}</div></div>)}{!rows.length&&<div className="empty">No completed hands in this contest yet.</div>}</div></section></>
}

function AdminRoom({ profile }) {
  const [form, setForm] = useState({ name:'Sunday Main', season:new Date().getFullYear(), week:1, locks_at:'' })
  const [users, setUsers] = useState([])
  const [contests, setContests] = useState([])
  const [message, setMessage] = useState('')
  useEffect(()=>{load()},[])
  async function load(){ const [{data:u},{data:c}] = await Promise.all([supabase.from('admin_users').select('*').limit(50),supabase.from('admin_contests').select('*').order('created_at',{ascending:false})]);setUsers(u||[]);setContests(c||[]) }
  async function create(e){e.preventDefault();const {error}=await supabase.rpc('admin_create_contest',{p_name:form.name,p_season:Number(form.season),p_week:Number(form.week),p_locks_at:form.locks_at||null});setMessage(error?error.message:'Contest created.');if(!error)load()}
  async function addCredits(userId){const amount=Number(prompt('Credits to add:', '25'));if(!Number.isFinite(amount)||amount<=0)return;const {error}=await supabase.rpc('admin_adjust_credits',{p_user_id:userId,p_amount:amount,p_note:'Admin credit adjustment'});setMessage(error?error.message:`Added ${amount} credits.`);if(!error)load()}
  async function status(id,status){const {error}=await supabase.rpc('admin_set_contest_status',{p_contest_id:id,p_status:status});setMessage(error?error.message:`Contest set to ${status}.`);if(!error)load()}
  async function finalize(id){if(!confirm('Finalize scoring and pay the top three?'))return;const {error}=await supabase.rpc('admin_finalize_contest',{p_contest_id:id});setMessage(error?error.message:'Contest finalized and credits paid.');if(!error)load()}
  async function sync(kind){setMessage(`Starting ${kind} sync…`);const {data,error}=await supabase.functions.invoke(kind);setMessage(error?error.message:(data?.message||'Sync complete.'));if(!error)load()}
  return <><Topbar profile={profile} kicker="HOUSE CONTROL" title="Admin Room"/><section className="content admin-grid"><div className="admin-card"><div className="eyebrow gold">OPEN A TABLE</div><h3>Create contest</h3><form onSubmit={create}><label>Name<input value={form.name} onChange={e=>setForm({...form,name:e.target.value})}/></label><div className="two"><label>Season<input type="number" value={form.season} onChange={e=>setForm({...form,season:e.target.value})}/></label><label>Week<input type="number" min="1" max="22" value={form.week} onChange={e=>setForm({...form,week:e.target.value})}/></label></div><label>Lock time (optional)<input type="datetime-local" value={form.locks_at} onChange={e=>setForm({...form,locks_at:e.target.value})}/></label><button className="primary wide">Create contest</button></form></div><div className="admin-card"><div className="eyebrow gold">DATA FEED</div><h3>NFL sync controls</h3><p>Refresh the eligible starter pool before entries open. Live stats are normally handled by Supabase Cron.</p><button className="secondary wide" onClick={()=>sync('sync-players')}><RefreshCw/> Sync starters & season stats</button><button className="secondary wide" onClick={()=>sync('sync-live-stats')}><Gauge/> Run live scoring now</button></div></section><section className="content admin-tables">{message&&<div className="notice">{message}</div>}<div className="admin-card wide-card"><div className="section-head"><h3>Contests</h3></div>{contests.map(c=><div className="admin-row" key={c.id}><div><b>{c.name}</b><span>Week {c.week} · {c.entry_count} entries · {c.pot_credits} credits</span></div><div className="row-actions">{c.status==='open'&&<button onClick={()=>status(c.id,'locked')}>Lock</button>}{c.status==='locked'&&<button onClick={()=>status(c.id,'live')}>Go live</button>}{c.status==='live'&&<button onClick={()=>finalize(c.id)}>Finalize + Pay</button>}<span className={`status ${c.status}`}>{c.status}</span></div></div>)}</div><div className="admin-card wide-card"><div className="section-head"><h3>Players & bankrolls</h3></div>{users.map(u=><div className="admin-row" key={u.id}><div><b>{u.username}</b><span>{u.email}</span></div><div className="row-actions"><b>{u.credits} cr</b><button onClick={()=>addCredits(u.id)}>Add credits</button></div></div>)}</div></section></>
}

function Unconfigured() { return <div className="auth-wrap"><div className="auth-card"><Logo/><h1>Connect Supabase</h1><p>Copy <code>.env.example</code> to <code>.env</code> and add your project URL and publishable key, then restart Vite.</p></div></div> }

export default function App() {
  const [session, setSession] = useState(null)
  const [profile, setProfile] = useState(null)
  const [view, setView] = useState('lobby')
  const [handId, setHandId] = useState(null)

  useEffect(() => {
    if (!configured) return
    supabase.auth.getSession().then(({data}) => setSession(data.session))
    const {data:{subscription}}=supabase.auth.onAuthStateChange((_event,s)=>setSession(s))
    return()=>subscription.unsubscribe()
  }, [])
  useEffect(()=>{
    if(!session){setProfile(null);return}
    loadProfile()
    const channel=supabase.channel(`profile-${session.user.id}`).on('postgres_changes',{event:'UPDATE',schema:'public',table:'profiles',filter:`id=eq.${session.user.id}`},payload=>setProfile(payload.new)).subscribe()
    return()=>supabase.removeChannel(channel)
  },[session])
  async function loadProfile(){ const {data}=await supabase.from('profiles').select('*').eq('id',session.user.id).single();setProfile(data) }
  async function logout(){ await supabase.auth.signOut() }
  function openHand(id){setHandId(id);setView('builder')}
  if(!configured) return <Unconfigured/>
  if(!session) return <Auth/>
  if(!profile) return <div className="loading"><Dices className="spin"/> Opening the cardroom…</div>
  return <Shell profile={profile} active={view==='builder'?'hands':view} setActive={v=>{setView(v);setHandId(null)}} onLogout={logout}>
    {view==='lobby'&&<ContestLobby profile={profile} onOpenHand={openHand}/>} 
    {view==='hands'&&<MyHands profile={profile} onOpen={openHand}/>} 
    {view==='leaderboard'&&<Leaderboard profile={profile}/>} 
    {view==='admin'&&profile.is_admin&&<AdminRoom profile={profile}/>} 
    {view==='builder'&&handId&&<HandBuilder profile={profile} handId={handId} onBack={()=>setView('hands')}/>} 
  </Shell>
}
