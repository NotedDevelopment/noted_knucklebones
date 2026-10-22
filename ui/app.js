'use strict';
// lb-phone injects fetchNui into custom-app iframes; it posts to this resource's NUI callbacks.
async function post(name, data) {
  if (typeof fetchNui === 'function') return fetchNui(name, data || {});
  return null; // dev browser
}

const app = document.getElementById('app');
const $ = id => document.getElementById(id);
const faces = [[], [5], [1, 9], [1, 5, 9], [1, 3, 7, 9], [1, 3, 5, 7, 9], [1, 3, 4, 6, 7, 9]];
let snapshot = false;   // latest server snapshot, or false when not in a game
let previous = false;   // the snapshot before it, diffed for animations and sounds
let view = 'lobby';     // screen shown while not in a game: lobby, create, browse, profile
let profile = { name: '', nickname: '', min: 2, max: 16 }; // character name, nickname and the server's length limits
let savingNickname = false;
let roomsTimer = null;
let privacy = 'public';
try { privacy = localStorage.getItem('kb-privacy') === 'private' ? 'private' : 'public'; } catch { /* storage blocked */ }
let busy = false;
let rolling = false;    // the centre die is tumbling; lanes wait until it settles
let rollTimer, settleTimer, toastTimer;

// Sound cues are synthesised with the Web Audio API so the resource ships no audio files.
const sound = (() => {
  // Recorded dice and chip samples (Kenney Casino Audio, CC0) decoded once into Web Audio
  // buffers so they can be sequenced and pitched; UI chimes are short synthesised tones.
  const SAMPLES = {
    shake: ['dice-shake-1', 'dice-shake-2', 'dice-shake-3'],
    throw: ['die-throw-1', 'die-throw-2', 'die-throw-3', 'die-throw-4'],
    lay: ['chip-lay-1', 'chip-lay-2', 'chip-lay-3'],
    collide: ['chips-collide-1', 'chips-collide-2', 'chips-collide-3', 'chips-collide-4'],
  };
  const buffers = {};
  let ctx = null;
  let loading = false;
  let muted = false;
  try { muted = localStorage.getItem('kb-muted') === '1'; } catch { /* storage blocked */ }
  function context() {
    if (muted) return null;
    try {
      ctx = ctx || new (window.AudioContext || window.webkitAudioContext)();
      if (ctx.state === 'suspended') ctx.resume();
      if (!loading) { loading = true; for (const names of Object.values(SAMPLES)) names.forEach(load); }
      return ctx;
    } catch { return null; }
  }
  async function load(name) {
    try {
      const response = await fetch(`sounds/${name}.ogg`);
      buffers[name] = await ctx.decodeAudioData(await response.arrayBuffer());
    } catch { /* missing sample: that cue stays silent */ }
  }
  const pick = group => SAMPLES[group][Math.floor(Math.random() * SAMPLES[group].length)];
  // Play a sample `at` seconds from now; `offset`/`dur` slice it, `rate` pitches it, `fade` ramps it out.
  function sample(ac, group, { at = 0, gain = 1, rate = 1, offset = 0, dur, fade = false } = {}) {
    const buffer = buffers[pick(group)];
    if (!buffer) return;
    const t = ac.currentTime + at;
    const src = ac.createBufferSource();
    src.buffer = buffer;
    src.playbackRate.value = rate;
    const amp = ac.createGain();
    amp.gain.setValueAtTime(gain, t);
    const length = dur ?? buffer.duration - offset;
    if (fade) amp.gain.linearRampToValueAtTime(0, t + length);
    src.connect(amp).connect(ac.destination);
    src.start(t, offset, length);
  }
  function tone(ac, { freq, to, at = 0, dur = .12, type = 'sine', gain = .16 }) {
    const osc = ac.createOscillator();
    const amp = ac.createGain();
    const t = ac.currentTime + at;
    osc.type = type;
    osc.frequency.setValueAtTime(freq, t);
    if (to) osc.frequency.exponentialRampToValueAtTime(to, t + dur);
    amp.gain.setValueAtTime(0, t);
    amp.gain.linearRampToValueAtTime(gain, t + .008);
    amp.gain.exponentialRampToValueAtTime(.0008, t + dur);
    osc.connect(amp).connect(ac.destination);
    osc.start(t);
    osc.stop(t + dur + .02);
  }
  const play = fn => { const ac = context(); if (ac) fn(ac); };
  return {
    get muted() { return muted; },
    toggle() {
      muted = !muted;
      try { localStorage.setItem('kb-muted', muted ? '1' : '0'); } catch { /* storage blocked */ }
      if (!muted) this.place();
      return muted;
    },
    warm() { if (!muted) context(); },
    // A short rattle in the hand, then the die thrown onto the board.
    roll() { play(ac => { sample(ac, 'shake', { offset: .15, dur: .32, gain: .8, fade: true }); sample(ac, 'throw', { at: .28, gain: 1 }); }); },
    place() { play(ac => { sample(ac, 'lay', { gain: .9 }); }); },
    // Your die knocks the opponent's out: pieces scatter, then a bright rising zing.
    hit() {
      play(ac => {
        sample(ac, 'collide', { gain: 1, rate: 1.05 });
        tone(ac, { freq: 880, at: .08, dur: .11, type: 'triangle', gain: .1 });
        tone(ac, { freq: 1320, at: .17, dur: .22, type: 'triangle', gain: .11 });
      });
    },
    // The opponent knocks yours out: the same scatter, slower and heavier, with a low thud.
    knock() { play(ac => { sample(ac, 'collide', { gain: 1, rate: .78 }); tone(ac, { freq: 140, to: 50, at: .02, dur: .25, gain: .3 }); }); },
    turn() { play(ac => { tone(ac, { freq: 660, dur: .14, gain: .1 }); tone(ac, { freq: 990, at: .13, dur: .22, gain: .1 }); }); },
    win() { play(ac => { [523, 659, 784, 1047].forEach((f, i) => tone(ac, { freq: f, at: i * .11, dur: .26, type: 'triangle', gain: .11 })); }); },
    lose() { play(ac => { [392, 330, 262].forEach((f, i) => tone(ac, { freq: f, at: i * .16, dur: .3, type: 'triangle', gain: .1 })); }); },
    draw() { play(ac => { tone(ac, { freq: 440, dur: .25, type: 'triangle', gain: .1 }); tone(ac, { freq: 440, at: .22, dur: .25, type: 'triangle', gain: .1 }); }); },
  };
})();

function renderMute() {
  for (const el of document.querySelectorAll('[data-act="mute"]')) {
    el.textContent = sound.muted ? '🔇' : '🔊';
    el.classList.toggle('off', sound.muted);
  }
}

function toast(message) {
  const el = $('toast');
  el.textContent = message;
  el.hidden = false;
  clearTimeout(toastTimer);
  toastTimer = setTimeout(() => { el.hidden = true; }, 3200);
}

function die(value, side) {
  const el = document.createElement('div');
  el.className = `die${side === 1 ? ' dark' : ''}${value === 0 ? ' empty' : ''}`;
  for (const position of faces[value] || []) {
    const pip = document.createElement('i');
    pip.className = 'pip';
    pip.style.gridArea = `${Math.ceil(position / 3)} / ${(position - 1) % 3 + 1}`;
    el.append(pip);
  }
  return el;
}

function seatName(side) {
  const n = snapshot.names?.[side];
  return n ? `${n}${snapshot.seat === side ? ' (you)' : ''}` : (side === 0 ? 'Seat A' : 'Seat B');
}

function renderSide(side, where) {
  const game = snapshot.game;
  const data = game.sides[side];
  const mine = snapshot.seat === side && game.turn === side && game.phase === 1 && game.roll > 0 && !rolling;
  $(`label${where}`).replaceChildren(Object.assign(document.createElement('span'), { textContent: seatName(side) }),
    Object.assign(document.createElement('strong'), { textContent: data.total }));
  const columns = $(`columns${where}`);
  columns.replaceChildren();
  data.columns.forEach((values, index) => {
    const column = document.createElement('div');
    const playable = mine && !busy && values.includes(0);
    column.className = `column${playable ? ' playable' : ''}`;
    for (const value of values) column.append(die(value, side));
    column.append(Object.assign(document.createElement('span'), { className: 'score', textContent: data.scores[index] }));
    if (playable) column.addEventListener('click', () => act('place', index + 1));
    columns.append(column);
  });
}

function displayName() {
  return profile.nickname || profile.name || 'you';
}

function renderMenus() {
  $('playingAs').textContent = displayName();
  $('shownAs').textContent = displayName();
  $('clearNickname').hidden = !profile.nickname;
  $('clearNickname').textContent = profile.name ? `Use my character name (${profile.name})` : 'Use my character name';
  $('nickname').placeholder = profile.name || 'Nickname';
  $('nickname').maxLength = profile.max;
  $('nicknameRules').textContent = `${profile.min} to ${profile.max} letters, numbers, spaces, apostrophes or hyphens. Name changes are logged.`;
  for (const el of document.querySelectorAll('[data-choice]')) el.classList.toggle('selected', el.dataset.choice === privacy);
}

// Keep the public list fresh while it is on screen.
function setScreen(name) {
  app.dataset.screen = name;
  if (name === 'browse' && !roomsTimer) roomsTimer = setInterval(() => post('rooms'), 4000);
  if (name !== 'browse' && roomsTimer) { clearInterval(roomsTimer); roomsTimer = null; }
}

function render() {
  renderMenus();
  if (!snapshot) {
    setScreen(view);
    return;
  }
  const game = snapshot.game;
  const seated = snapshot.seat === 0 || snapshot.seat === 1;
  if (seated && game.phase === 0) {
    setScreen('waiting');
    $('roomCode').textContent = snapshot.code;
    const card = $('roomPrivacy');
    card.querySelector('b').textContent = snapshot.public ? 'Public game' : 'Private game';
    card.querySelector('span').textContent = snapshot.public
      ? 'Anyone can join from Public games, or with the code above.'
      : 'Only people you give the code to can join.';
    return;
  }
  setScreen('game');
  const bottom = snapshot.seat === 1 ? 1 : 0;
  renderSide(1 - bottom, 'Top');
  renderSide(bottom, 'Bottom');
  $('scoreTop').textContent = '';
  $('scoreBottom').textContent = snapshot.code;
  $('watchers').textContent = snapshot.spectators ? `👁 ${snapshot.spectators}` : '';
  $('rollText').textContent = rolling ? 'Rolling…' : game.roll ? 'Current roll' : 'Roll · Place · Remove';
  if (!rolling) $('rollDie').replaceChildren(die(game.roll, game.turn));
  const mine = seated && game.turn === snapshot.seat;
  let status;
  if (game.phase >= 2) {
    status = game.winner === -1 ? 'A draw.' : `${seatName(game.winner)} wins${game.phase === 3 ? ' by forfeit' : ''}.`;
    if (seated && snapshot.ready?.[snapshot.seat]) status += ' Waiting for the other player.';
  } else if (rolling) status = `${mine ? 'You are' : seatName(game.turn) + ' is'} rolling…`;
  else if (!seated) status = `${seatName(game.turn)} is ${game.roll ? 'choosing a lane' : 'rolling'}.`;
  else if (mine) status = game.roll ? `You rolled ${game.roll}. Tap a highlighted lane.` : 'Your turn. Roll.';
  else status = `${seatName(game.turn)} is ${game.roll ? 'choosing a lane' : 'rolling'}.`;
  $('status').textContent = status;
  $('status').classList.toggle('mine', mine && game.phase === 1 && !rolling);
  // Roll only appears when it can be pressed; otherwise the strip shows the die and a label.
  $('rollButton').hidden = !seated || game.phase !== 1 || !mine || game.roll > 0 || rolling;
  $('rollButton').disabled = busy;
  $('rematchButton').hidden = !seated || game.phase < 2;
  $('rematchButton').disabled = busy || snapshot.ready?.[snapshot.seat] === true;
  $('stopButton').hidden = seated;
  $('actions').hidden = $('rollButton').hidden && $('rematchButton').hidden && $('stopButton').hidden;
  $('rollText').hidden = !$('actions').hidden;
  $('leaveButton').hidden = !seated;
  $('leaveButton').textContent = game.phase === 1 ? '‹ Forfeit' : '‹ Leave';
}

// Tumble the centre die through random faces, then settle on the real roll.
function animateRoll(value, side) {
  clearInterval(rollTimer);
  clearTimeout(settleTimer);
  rolling = true;
  const holder = $('rollDie');
  const show = v => { const d = die(v, side); d.classList.add('tumble'); holder.replaceChildren(d); };
  render(); // lanes stay unlit and the status reads "rolling" until the die settles
  show(1 + Math.floor(Math.random() * 6));
  rollTimer = setInterval(() => show(1 + Math.floor(Math.random() * 6)), 75);
  settleTimer = setTimeout(() => {
    clearInterval(rollTimer);
    rolling = false;
    if (snapshot && snapshot.game.roll === value) {
      render();
      $('rollDie').firstChild?.classList.add('settle');
    } else render();
  }, 800);
}

function laneAt(side, index) {
  const bottom = snapshot.seat === 1 ? 1 : 0;
  return $(side === bottom ? 'columnsBottom' : 'columnsTop').children[index];
}

// Compare the previous and new snapshots and fire the matching animation and sound.
function transition(before, after) {
  if (!after) return;
  // A first snapshot for this match (game start, reconnect) is diffed against a blank state.
  const fresh = !before || before.match !== after.match;
  const was = fresh ? { phase: 0, roll: 0, turn: -1 } : before.game;
  const now = after.game;
  const seated = after.seat === 0 || after.seat === 1;
  if (now.phase === 1 && now.roll > 0 && (was.roll === 0 || was.turn !== now.turn)) {
    sound.roll();
    animateRoll(now.roll, now.turn);
  }
  if (!fresh && was.roll > 0 && now.roll === 0 && was.phase === 1) {
    // A die was placed by the side that was on turn; the lane across may have lost dice.
    const placer = was.turn;
    let placed = null, knocked = [];
    now.sides[placer].columns.forEach((values, index) => {
      const old = was.sides[placer].columns[index];
      for (let i = 0; i < values.length; i += 1) if (values[i] !== 0 && old[i] === 0) placed = { index, row: i };
    });
    now.sides[1 - placer].columns.forEach((values, index) => {
      const old = was.sides[1 - placer].columns[index];
      if (values.filter(v => v).length < old.filter(v => v).length) knocked.push(index);
    });
    if (placed) laneAt(placer, placed.index)?.children[placed.row]?.classList.add('pop');
    const hitter = seated && placer === after.seat; // you did the knocking out
    for (const index of knocked) laneAt(1 - placer, index)?.classList.add(hitter ? 'hit' : 'knock');
    if (!knocked.length) sound.place();
    else if (hitter) sound.hit();
    else sound.knock();
  }
  if (!fresh && now.phase >= 2 && was.phase < 2) {
    if (!seated || now.winner === -1) sound.draw();
    else if (now.winner === after.seat) sound.win();
    else sound.lose();
  } else if (seated && now.phase === 1 && now.turn === after.seat && now.roll === 0 && (was.turn !== after.seat || was.phase !== 1)) {
    sound.turn();
    $('status').classList.remove('pulse');
    void $('status').offsetWidth;
    $('status').classList.add('pulse');
  }
}

async function act(action, column) {
  if (busy || !snapshot) return;
  busy = true;
  $('error').textContent = '';
  render();
  try {
    await post('action', { action, column, match: snapshot.match, revision: snapshot.revision });
  } catch { $('error').textContent = 'No response from the server.'; }
  finally { busy = false; render(); }
}

// Public rooms split into ones with a free seat (Join) and games already running (Watch).
function renderRooms(rooms) {
  const open = rooms.filter(room => room.phase === 0 && !(room.names[0] && room.names[1]));
  const live = rooms.filter(room => !open.includes(room));
  const fill = (list, items, joinable) => {
    list.replaceChildren();
    for (const room of items) {
      const li = document.createElement('li');
      const text = document.createElement('div');
      const host = room.names[0] || room.names[1] || 'Someone';
      text.innerHTML = '<div class="names"></div><div class="meta"></div>';
      text.querySelector('.names').textContent = joinable ? `${host} is waiting` : `${room.names[0] || '?'} vs ${room.names[1] || '?'}`;
      const phase = joinable ? 'Open seat' : (room.phase === 1 ? 'Playing' : 'Finished');
      text.querySelector('.meta').textContent = `${room.code} · ${phase}${room.spectators ? ` · 👁 ${room.spectators}` : ''}`;
      const button = document.createElement('button');
      button.className = joinable ? 'primary' : 'secondary';
      button.textContent = joinable ? 'Join' : 'Watch';
      button.addEventListener('click', () => post(joinable ? 'join' : 'spectate', { code: room.code }));
      li.append(text, button);
      list.append(li);
    }
  };
  fill($('openList'), open, true);
  fill($('liveList'), live, false);
  $('openLabel').hidden = $('openList').hidden = open.length === 0;
  $('liveLabel').hidden = $('liveList').hidden = live.length === 0;
  $('roomsEmpty').hidden = rooms.length > 0;
}

function openHelp(open) {
  $('help').hidden = !open;
  if (open) $('help').querySelector('.scroll').scrollTop = 0;
}

function saveNickname(value) {
  // A quick length check for instant feedback; the server validates everything else.
  const name = value.trim().replace(/\s+/g, ' ');
  if (name && (name.length < profile.min || name.length > profile.max)) { toast(`Nicknames are ${profile.min} to ${profile.max} characters.`); return; }
  savingNickname = true;
  post('nickname', { nickname: name });
}

document.addEventListener('click', event => {
  const choice = event.target.closest('[data-choice]');
  if (choice) {
    privacy = choice.dataset.choice;
    try { localStorage.setItem('kb-privacy', privacy); } catch { /* storage blocked */ }
    renderMenus();
    return;
  }
  const button = event.target.closest('[data-act]');
  if (!button) return;
  const act_ = button.dataset.act;
  switch (act_) {
    case 'create': view = 'create'; render(); break;
    case 'confirmCreate': post('create', { public: privacy === 'public' }); break;
    case 'ai': post('ai'); break;
    case 'join': {
      const code = $('code').value.trim().toUpperCase();
      if (code.length < 4) { toast('Enter the room code.'); return; }
      post('join', { code });
      break;
    }
    case 'browse': view = 'browse'; render(); post('rooms'); break;
    case 'rooms': post('rooms'); break;
    case 'profile': view = 'profile'; $('nickname').value = profile.nickname || ''; render(); break;
    case 'saveNickname': saveNickname($('nickname').value); break;
    case 'clearNickname': saveNickname(''); break;
    case 'lobby': view = 'lobby'; render(); break;
    case 'help': openHelp(true); break;
    case 'closeHelp': openHelp(false); break;
    case 'leave': post('leave'); break;
    case 'stopSpectating': post('stopSpectating'); snapshot = false; view = 'browse'; render(); post('rooms'); break;
    case 'roll': act('roll'); break;
    case 'rematch': act('rematch'); break;
    case 'mute': sound.toggle(); renderMute(); break;
  }
});
// Browsers only start audio after a gesture; the first tap unlocks it.
document.addEventListener('pointerdown', () => sound.warm(), { once: true });
$('code').addEventListener('keydown', event => { if (event.key === 'Enter') document.querySelector('[data-act="join"]').click(); });
$('nickname').addEventListener('keydown', event => { if (event.key === 'Enter') saveNickname($('nickname').value); });
// The guide's example dice are drawn with the same die() as the board.
for (const holder of document.querySelectorAll('.dice[data-dice]')) {
  const dark = holder.classList.contains('dark');
  holder.replaceChildren(...holder.dataset.dice.split(',').map(v => die(Number(v), dark ? 1 : 0)));
}

window.addEventListener('message', event => {
  const { action, data } = event.data || {};
  if (action === 'update') {
    previous = snapshot;
    snapshot = data || false;
    if (snapshot) view = 'lobby'; // leaving a game later lands back on the lobby
    $('error').textContent = '';
    if (!snapshot || !previous || previous.match !== snapshot.match) { clearInterval(rollTimer); clearTimeout(settleTimer); rolling = false; }
    render();
    transition(previous, snapshot);
  }
  else if (action === 'closed') { clearInterval(rollTimer); clearTimeout(settleTimer); rolling = false; snapshot = false; previous = false; view = 'lobby'; render(); if (data?.message) toast(data.message); }
  else if (action === 'rooms') renderRooms(data.rooms || []);
  else if (action === 'profile') {
    profile = { name: data?.name || '', nickname: data?.nickname || '', min: data?.min || 2, max: data?.max || 16 };
    if (savingNickname && view === 'profile') view = 'lobby';
    else if (view === 'profile' && document.activeElement !== $('nickname')) $('nickname').value = profile.nickname;
    savingNickname = false;
    render();
  }
  else if (action === 'error') { savingNickname = false; $('error').textContent = data.message || ''; toast(data.message || 'Something went wrong.'); }
  else if (action === 'notice') toast(data.message || '');
});

async function refresh() {
  try {
    const data = await post('getData');
    if (data && data.snapshot) { snapshot = data.snapshot; render(); }
  } catch { /* outside the game */ }
}

// Any script error shows on the page instead of leaving the phone black.
window.addEventListener('error', event => {
  if (window.name !== '') return;
  app.classList.add('visible');
  const el = $('toast');
  el.textContent = `Knucklebones UI error: ${event.message}`;
  el.hidden = false;
});

// In-game this file loads twice. FiveM frames the resource's own ui_page in an iframe
// named after the resource (that copy must stay invisible); lb-phone's app iframe has no
// name. The phone injects fetchNui after load, so wait for it before asking for data.
const devMode = !window.invokeNative;
const inPhone = window.name === '';
if (devMode || inPhone) {
  app.classList.add('visible');
  renderMute();
  render();
  let tries = 0;
  const waitForPhone = setInterval(() => {
    tries += 1;
    if (typeof fetchNui === 'function' || devMode || tries > 100) {
      clearInterval(waitForPhone);
      refresh();
    }
  }, 100);
  window.addEventListener('message', event => { if (event.data === 'componentsLoaded') refresh(); });
}
