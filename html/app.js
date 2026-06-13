/* lf_elevatore — NUI admin panel */
(() => {
  const RES = (() => {
    if (typeof GetParentResourceName === 'function') return GetParentResourceName();
    const m = (window.location.hostname || '').match(/(?:cfx-nui-)?(.+)/);
    return (m && m[1]) || 'lf_elevatore';
  })();

  async function post(name, data = {}) {
    try {
      const r = await fetch(`https://${RES}/${name}`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json; charset=UTF-8' },
        body: JSON.stringify(data),
      });
      return await r.json();
    } catch (e) {
      return null;
    }
  }

  const $ = (id) => document.getElementById(id);
  const app = $('app');

  const state = {
    elevators: {},
    settings: {},
    framework: '-',
    editing: null,       // working copy of an elevator
    floorIndex: null,    // index being edited in the modal
    floorDraft: null,    // working copy of a floor
  };

  const SETTINGS_SCHEMA = [
    { key: 'waitTime', type: 'number', label: 'Travel time', desc: 'Seconds spent travelling between floors' },
    { key: 'fadeTime', type: 'number', label: 'Fade time', desc: 'Screen fade in/out duration (ms)' },
    { key: 'interactDistance', type: 'number', label: 'Interact distance', desc: 'Range of the [E] prompt (m)' },
    { key: 'useTextUI', type: 'bool', label: 'TextUI prompt', desc: 'Show the [E] prompt near elevators' },
    { key: 'shake', type: 'bool', label: 'Arrival shake', desc: 'Subtle camera shake on arrival' },
    { key: 'debug', type: 'bool', label: 'Debug zones', desc: 'Draw target/zone outlines' },
    { key: 'groupTravelEnabled', type: 'bool', label: 'Group travel', desc: 'Nearby players ride along' },
    { key: 'groupTravelRadius', type: 'number', label: 'Group radius', desc: 'Distance for group travel (m)' },
    { key: 'loggingEnabled', type: 'bool', label: 'Usage logging', desc: 'Log restricted floor usage' },
    { key: 'logAllMoves', type: 'bool', label: 'Log every move', desc: 'Also log public floors' },
    { key: 'webhook', type: 'text', label: 'Discord webhook', desc: 'Webhook URL for logs' },
  ];

  const REASONS = {
    no_perm: 'You are not allowed to do that.',
    api_readonly: 'This elevator is managed by another resource.',
    need_floors: 'An elevator needs at least 2 floors.',
    invalid: 'Invalid data.',
    name_taken: 'That name is already in use.',
  };

  /* ---------- toast ---------- */
  let toastTimer;
  function toast(msg, kind = 'ok') {
    let t = $('toast');
    if (!t) {
      t = document.createElement('div');
      t.id = 'toast';
      t.style.cssText =
        'position:fixed;bottom:24px;left:50%;transform:translateX(-50%);padding:11px 18px;' +
        'border-radius:9px;font-size:13px;font-weight:600;z-index:50;box-shadow:0 8px 30px rgba(0,0,0,.5);';
      app.appendChild(t);
    }
    t.textContent = msg;
    t.style.background = kind === 'err' ? '#e25555' : kind === 'warn' ? '#e8b84b' : '#3ecf8e';
    t.style.color = '#0c0f14';
    t.style.opacity = '1';
    clearTimeout(toastTimer);
    toastTimer = setTimeout(() => { t.style.opacity = '0'; }, 2600);
  }

  /* ---------- conversions ---------- */
  const objToRows = (o) => (o ? Object.entries(o).map(([k, v]) => ({ k, v })) : []);
  const rowsToObj = (rows) => {
    const out = {};
    rows.forEach((r) => { if (r.k && r.k.trim() !== '') out[r.k.trim()] = Number(r.v) || 0; });
    return Object.keys(out).length ? out : null;
  };
  const cleanList = (arr) => {
    const out = (arr || []).map((s) => (s || '').trim()).filter((s) => s !== '');
    return out.length ? out : null;
  };

  /* ---------- list view ---------- */
  function renderList() {
    const grid = $('grid');
    const q = ($('search').value || '').toLowerCase();
    const names = Object.keys(state.elevators).filter((n) => n.toLowerCase().includes(q)).sort();
    grid.innerHTML = '';
    $('empty').classList.toggle('hidden', names.length > 0);

    names.forEach((name) => {
      const el = state.elevators[name];
      const card = document.createElement('div');
      card.className = 'card' + (el.locked ? ' locked' : '');
      card.innerHTML = `
        <div class="card-top">
          <div>
            <h3>${escapeHtml(name)}</h3>
            <div class="meta">${el.floors.length} floor${el.floors.length === 1 ? '' : 's'}${el.label && el.label !== name ? ' · ' + escapeHtml(el.label) : ''}</div>
          </div>
          <span class="badge ${el.source}">${el.source}</span>
        </div>
        ${el.locked ? '<span class="badge lock">🔒 out of service</span>' : ''}
        <div class="card-actions">
          <button class="btn small" data-act="edit">✏️ Edit</button>
          <button class="btn small" data-act="lock">${el.locked ? '🔓' : '🔒'}</button>
          <button class="btn small danger" data-act="del">🗑️</button>
        </div>`;
      card.querySelector('[data-act=edit]').onclick = () => openEditor(name);
      card.querySelector('[data-act=lock]').onclick = () => toggleLock(name, !el.locked);
      card.querySelector('[data-act=del]').onclick = () => deleteElevator(name, el.source);
      grid.appendChild(card);
    });
  }

  async function toggleLock(name, lockState) {
    const res = await post('setLocked', { name, state: lockState });
    if (res && res.ok) { await refresh(); toast(lockState ? 'Elevator locked' : 'Elevator unlocked'); }
    else toast(REASONS[res && res.reason] || 'Failed', 'err');
  }

  // FiveM's NUI runtime has no native window.confirm(), so use our own modal.
  function confirmBox(message) {
    return new Promise((resolve) => {
      const ov = document.createElement('div');
      ov.className = 'modal';
      ov.innerHTML =
        `<div class="modal-box" style="width:380px">
          <div class="modal-head"><h3>Confirm</h3></div>
          <div class="modal-body">${escapeHtml(message)}</div>
          <div class="modal-actions">
            <button class="btn ghost" data-no>Cancel</button>
            <button class="btn danger" data-yes>Delete</button>
          </div>
        </div>`;
      app.appendChild(ov);
      ov.querySelector('[data-no]').onclick = () => { ov.remove(); resolve(false); };
      ov.querySelector('[data-yes]').onclick = () => { ov.remove(); resolve(true); };
    });
  }

  async function deleteElevator(name, source) {
    if (source === 'api') return toast(REASONS.api_readonly, 'warn');
    if (!(await confirmBox(`Delete elevator "${name}"? This cannot be undone.`))) return;
    const res = await post('deleteElevator', { name });
    if (res && res.ok) { await refresh(); toast('Elevator deleted'); }
    else toast(REASONS[res && res.reason] || 'Failed', 'err');
  }

  /* ---------- editor ---------- */
  function openEditor(name) {
    const src = state.elevators[name];
    state.editing = {
      name,
      label: src.label || name,
      groupTravel: src.groupTravel !== false,
      source: src.source,
      isNew: false,
      floors: JSON.parse(JSON.stringify(src.floors)),
    };
    showEditor();
  }

  function newElevator() {
    state.editing = { name: '', label: '', groupTravel: true, source: 'saved', isNew: true, floors: [] };
    showEditor();
  }

  function showEditor() {
    const e = state.editing;
    switchView('editor');
    $('editorTitle').textContent = e.isNew ? 'New elevator' : 'Edit elevator';
    const badge = $('editorSource');
    badge.textContent = e.source;
    badge.className = 'badge ' + e.source;
    $('elName').value = e.name;
    $('elName').disabled = !e.isNew;
    $('elLabel').value = e.label;
    $('elGroupTravel').checked = e.groupTravel;
    renderFloorRows();
  }

  function renderFloorRows() {
    const list = $('floorList');
    const floors = state.editing.floors;
    list.innerHTML = '';
    floors.forEach((f, i) => {
      const tags = [];
      if (f.pin) tags.push('<span class="tag pin">PIN</span>');
      if (f.jobs || f.gangs) tags.push('<span class="tag job">JOB</span>');
      if (f.items) tags.push('<span class="tag item">ITEM' + (f.consumeItem ? '✗' : '') + '</span>');
      if (f.owners) tags.push('<span class="tag owner">OWNER</span>');
      if (f.hours) tags.push(`<span class="tag hours">${pad(f.hours.open)}-${pad(f.hours.close)}</span>`);
      if (f.bucket !== undefined && f.bucket !== null) tags.push(`<span class="tag">B${f.bucket}</span>`);

      const row = document.createElement('div');
      row.className = 'floor-row';
      row.innerHTML = `
        <div class="fnum">${i + 1}</div>
        <div class="finfo">
          <b>${escapeHtml(f.level || 'Floor')}</b>
          <span>${f.coords.x.toFixed(1)}, ${f.coords.y.toFixed(1)}, ${f.coords.z.toFixed(1)}${f.label ? ' · ' + escapeHtml(f.label) : ''}</span>
        </div>
        <div class="ftags">${tags.join('')}</div>
        <div class="fbtns">
          <button class="mini" data-act="go" title="Teleport here">📍</button>
          <button class="mini" data-act="up" title="Move up">▲</button>
          <button class="mini" data-act="down" title="Move down">▼</button>
          <button class="mini" data-act="edit" title="Edit">✏️</button>
          <button class="mini" data-act="del" title="Remove">✕</button>
        </div>`;
      row.querySelector('[data-act=go]').onclick = () => teleport(i);
      row.querySelector('[data-act=up]').onclick = () => moveFloor(i, -1);
      row.querySelector('[data-act=down]').onclick = () => moveFloor(i, 1);
      row.querySelector('[data-act=edit]').onclick = () => openFloorModal(i);
      row.querySelector('[data-act=del]').onclick = () => { state.editing.floors.splice(i, 1); renderFloorRows(); };
      list.appendChild(row);
    });
  }

  function moveFloor(i, dir) {
    const f = state.editing.floors;
    const j = i + dir;
    if (j < 0 || j >= f.length) return;
    [f[i], f[j]] = [f[j], f[i]];
    renderFloorRows();
  }

  async function teleport(i) {
    if (state.editing.isNew) return toast('Save the elevator first', 'warn');
    await post('teleport', { name: state.editing.name, index: i + 1 });
  }

  async function addFloor(usePicker) {
    const pos = await post(usePicker ? 'pickPosition' : 'currentPosition');
    if (!pos) { if (usePicker) toast('Position pick cancelled', 'warn'); return; }
    const f = { coords: pos.coords, heading: pos.heading, level: 'Floor ' + (state.editing.floors.length + 1) };
    state.editing.floors.push(f);
    openFloorModal(state.editing.floors.length - 1);
  }

  async function saveElevator() {
    const e = state.editing;
    const name = $('elName').value.trim();
    if (!name) return toast('Enter a name', 'err');
    if (e.isNew && state.elevators[name]) return toast(REASONS.name_taken, 'err');
    if (e.floors.length < 2) return toast(REASONS.need_floors, 'err');

    const res = await post('saveElevator', {
      name,
      label: $('elLabel').value.trim() || name,
      groupTravel: $('elGroupTravel').checked,
      floors: e.floors,
    });
    if (res && res.ok) {
      await refresh();
      switchView('elevators');
      toast('Elevator saved');
    } else {
      toast(REASONS[res && res.reason] || 'Failed to save', 'err');
    }
  }

  /* ---------- floor modal ---------- */
  function openFloorModal(index) {
    state.floorIndex = index;
    state.floorDraft = JSON.parse(JSON.stringify(state.editing.floors[index]));
    $('floorModalTitle').textContent = 'Floor ' + (index + 1);
    renderFloorForm();
    $('floorModal').classList.remove('hidden');
  }

  function closeFloorModal() {
    $('floorModal').classList.add('hidden');
    state.floorDraft = null;
    state.floorIndex = null;
  }

  function renderFloorForm() {
    const f = state.floorDraft;
    const c = f.coords;
    const jobRows = objToRows(f.jobs);
    const gangRows = objToRows(f.gangs);
    const itemRows = (f.items || []).slice();
    const ownerRows = (f.owners || []).slice();

    const body = $('floorForm');
    body.innerHTML = `
      <div class="form-row two">
        <label>Floor name<input id="f_level" type="text" value="${attr(f.level)}" /></label>
        <label>Description<input id="f_label" type="text" value="${attr(f.label)}" /></label>
      </div>

      <label>Position</label>
      <div class="coords-box">
        <code id="f_coords">${c.x.toFixed(2)}, ${c.y.toFixed(2)}, ${c.z.toFixed(2)} · ${Number(f.heading || 0).toFixed(1)}°</code>
        <button class="btn small" id="f_here">At my position</button>
        <button class="btn small" id="f_pick">📍 Pick</button>
      </div>

      <div class="form-row two" style="margin-top:14px">
        <label>PIN code<input id="f_pin" type="text" value="${attr(f.pin)}" placeholder="optional" /></label>
        <label>Routing bucket<input id="f_bucket" type="number" value="${f.bucket ?? ''}" placeholder="optional" /></label>
      </div>

      <div class="section-label">Access</div>
      <label class="check"><input id="f_requireAll" type="checkbox" ${f.requireAll ? 'checked' : ''}/> Require ALL conditions below (default: any one)</label>

      <div class="section-label">Jobs (name : min grade)</div>
      <div class="kv-list" id="f_jobs"></div>
      <button class="add-link" data-add="job">＋ add job</button>

      <div class="section-label">Gangs (name : min grade)</div>
      <div class="kv-list" id="f_gangs"></div>
      <button class="add-link" data-add="gang">＋ add gang</button>

      <div class="section-label">Items</div>
      <div class="str-list" id="f_items"></div>
      <button class="add-link" data-add="item">＋ add item</button>
      <label class="check" style="margin-top:8px"><input id="f_consume" type="checkbox" ${f.consumeItem ? 'checked' : ''}/> Consume the item on use (one-time pass)</label>

      <div class="section-label">Owners (citizenid / identifier)</div>
      <div class="str-list" id="f_owners"></div>
      <button class="add-link" data-add="owner">＋ add owner</button>

      <div class="section-label">Opening hours</div>
      <div class="form-row two">
        <label>Open hour (0-23)<input id="f_open" type="number" min="0" max="23" value="${f.hours ? f.hours.open : ''}" placeholder="always" /></label>
        <label>Close hour (0-23)<input id="f_close" type="number" min="0" max="23" value="${f.hours ? f.hours.close : ''}" placeholder="always" /></label>
      </div>`;

    renderKv('f_jobs', jobRows);
    renderKv('f_gangs', gangRows);
    renderStr('f_items', itemRows);
    renderStr('f_owners', ownerRows);

    body.querySelectorAll('[data-add]').forEach((b) => {
      b.onclick = () => {
        const t = b.dataset.add;
        if (t === 'job') appendKv('f_jobs');
        else if (t === 'gang') appendKv('f_gangs');
        else if (t === 'item') appendStr('f_items');
        else if (t === 'owner') appendStr('f_owners');
      };
    });
    $('f_here').onclick = () => recapture(false);
    $('f_pick').onclick = () => recapture(true);
  }

  async function recapture(usePicker) {
    const pos = await post(usePicker ? 'pickPosition' : 'currentPosition');
    if (!pos) return;
    state.floorDraft.coords = pos.coords;
    state.floorDraft.heading = pos.heading;
    $('f_coords').textContent =
      `${pos.coords.x.toFixed(2)}, ${pos.coords.y.toFixed(2)}, ${pos.coords.z.toFixed(2)} · ${Number(pos.heading).toFixed(1)}°`;
  }

  function renderKv(containerId, rows) {
    const el = $(containerId);
    el.innerHTML = '';
    rows.forEach((r) => addKvRow(el, r.k, r.v));
  }
  function appendKv(containerId) { addKvRow($(containerId), '', 0); }
  function addKvRow(container, k, v) {
    const row = document.createElement('div');
    row.className = 'kv-row';
    row.innerHTML = `<input type="text" placeholder="name" value="${attr(k)}" />
      <input class="grade" type="number" placeholder="grade" value="${v ?? 0}" />
      <button class="mini">✕</button>`;
    row.querySelector('.mini').onclick = () => row.remove();
    container.appendChild(row);
  }

  function renderStr(containerId, arr) {
    const el = $(containerId);
    el.innerHTML = '';
    arr.forEach((v) => addStrRow(el, v));
  }
  function appendStr(containerId) { addStrRow($(containerId), ''); }
  function addStrRow(container, v) {
    const row = document.createElement('div');
    row.className = 'str-row';
    row.innerHTML = `<input type="text" placeholder="value" value="${attr(v)}" /><button class="mini">✕</button>`;
    row.querySelector('.mini').onclick = () => row.remove();
    container.appendChild(row);
  }

  function collectKv(containerId) {
    const rows = [];
    $(containerId).querySelectorAll('.kv-row').forEach((r) => {
      const inputs = r.querySelectorAll('input');
      rows.push({ k: inputs[0].value, v: inputs[1].value });
    });
    return rowsToObj(rows);
  }
  function collectStr(containerId) {
    const arr = [];
    $(containerId).querySelectorAll('.str-row input').forEach((i) => arr.push(i.value));
    return cleanList(arr);
  }

  function saveFloor() {
    const f = state.floorDraft;
    f.level = $('f_level').value.trim() || 'Floor';
    f.label = $('f_label').value.trim() || undefined;
    f.pin = $('f_pin').value.trim() || undefined;
    const bucket = $('f_bucket').value;
    f.bucket = bucket === '' ? undefined : Number(bucket);
    f.requireAll = $('f_requireAll').checked || undefined;
    f.jobs = collectKv('f_jobs') || undefined;
    f.gangs = collectKv('f_gangs') || undefined;
    f.items = collectStr('f_items') || undefined;
    f.consumeItem = ($('f_consume').checked && f.items) ? true : undefined;
    f.owners = collectStr('f_owners') || undefined;
    const open = $('f_open').value, close = $('f_close').value;
    f.hours = (open !== '' && close !== '') ? { open: Number(open), close: Number(close) } : undefined;

    state.editing.floors[state.floorIndex] = f;
    closeFloorModal();
    renderFloorRows();
  }

  /* ---------- settings ---------- */
  function renderSettings() {
    const form = $('settingsForm');
    form.innerHTML = '';
    SETTINGS_SCHEMA.forEach((s) => {
      const v = state.settings[s.key];
      const row = document.createElement('div');
      row.className = 'set-row';
      let control;
      if (s.type === 'bool') {
        control = `<label class="switch"><input type="checkbox" data-key="${s.key}" ${v ? 'checked' : ''}/><span class="slider"></span></label>`;
      } else if (s.type === 'number') {
        control = `<input type="number" data-key="${s.key}" value="${v ?? ''}" />`;
      } else {
        control = `<input type="text" data-key="${s.key}" value="${attr(v)}" placeholder="empty" />`;
      }
      row.innerHTML = `<div class="label"><b>${s.label}</b><span>${s.desc}</span></div>${control}`;
      form.appendChild(row);
    });
  }

  async function saveSettings() {
    const overrides = {};
    $('settingsForm').querySelectorAll('[data-key]').forEach((inp) => {
      const key = inp.dataset.key;
      const schema = SETTINGS_SCHEMA.find((s) => s.key === key);
      if (schema.type === 'bool') overrides[key] = inp.checked;
      else if (schema.type === 'number') { if (inp.value !== '') overrides[key] = Number(inp.value); }
      else overrides[key] = inp.value;
    });
    const res = await post('saveSettings', overrides);
    if (res && res.ok) { if (res.settings) state.settings = res.settings; toast('Settings saved'); }
    else toast('Failed to save settings', 'err');
  }

  /* ---------- view + refresh ---------- */
  function switchView(view) {
    $('tab-elevators').classList.toggle('hidden', view !== 'elevators');
    $('editor').classList.toggle('hidden', view !== 'editor');
    $('tab-settings').classList.toggle('hidden', view !== 'settings');
    document.querySelectorAll('.tab').forEach((t) => {
      t.classList.toggle('active', (view === 'settings' && t.dataset.tab === 'settings') || (view !== 'settings' && t.dataset.tab === 'elevators'));
    });
    if (view === 'elevators') renderList();
    if (view === 'settings') renderSettings();
  }

  async function refresh() {
    const data = await post('refresh');
    if (data) applyData(data);
  }
  function applyData(data) {
    state.elevators = data.elevators || {};
    state.settings = data.settings || {};
    state.framework = data.framework || '-';
    $('fw').textContent = state.framework;
    renderList();
  }

  /* ---------- helpers ---------- */
  function escapeHtml(s) { return String(s ?? '').replace(/[&<>"]/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c])); }
  function attr(s) { return escapeHtml(s ?? ''); }
  function pad(n) { return String(n).padStart(2, '0'); }

  /* ---------- wiring ---------- */
  function close() { post('close'); app.classList.add('hidden'); }

  document.querySelectorAll('.tab').forEach((t) => {
    t.onclick = () => switchView(t.dataset.tab);
  });
  $('closeBtn').onclick = close;
  $('newBtn').onclick = newElevator;
  $('search').oninput = renderList;
  $('backBtn').onclick = () => switchView('elevators');
  $('cancelEdit').onclick = () => switchView('elevators');
  $('saveEl').onclick = saveElevator;
  $('addHere').onclick = () => addFloor(false);
  $('addPick').onclick = () => addFloor(true);
  $('floorClose').onclick = closeFloorModal;
  $('floorCancel').onclick = closeFloorModal;
  $('floorSave').onclick = saveFloor;
  $('saveSettings').onclick = saveSettings;

  window.addEventListener('keydown', (e) => {
    if (e.key === 'Escape') {
      if (!$('floorModal').classList.contains('hidden')) closeFloorModal();
      else close();
    }
  });

  window.addEventListener('message', (ev) => {
    const m = ev.data || {};
    if (m.action === 'open') {
      applyData(m.payload || {});
      switchView('elevators');
      app.classList.remove('hidden');
      app.style.display = 'flex';
    } else if (m.action === 'close') {
      app.classList.add('hidden');
    } else if (m.action === 'hide') {
      app.style.display = 'none';
    } else if (m.action === 'show') {
      app.style.display = 'flex';
    }
  });
})();
