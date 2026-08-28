import { apiF, fmt } from '/web/app.js';
import { lineChart } from '/web/charts.js';

const SORTS = [
  { key: 'cost',   label: 'Most expensive' },
  { key: 'turns',  label: 'Most turns' },
  { key: 'tokens', label: 'Most tokens' },
  { key: 'recent', label: 'Most recent' },
];

function readSort() {
  const q = (location.hash.split('?')[1] || '');
  const m = /(?:^|&)sort=([^&]+)/.exec(q);
  const k = m && decodeURIComponent(m[1]);
  return SORTS.find(s => s.key === k) || SORTS[0];
}

function writeSort(key) {
  const base = (location.hash.replace(/^#/, '').split('?')[0]) || '/prompts';
  location.hash = '#' + base + '?sort=' + encodeURIComponent(key);
}

const pct = n => n == null ? '—' : n.toFixed(0) + '%';

export default async function (root) {
  const sort = readSort();
  const [rows, trend] = await Promise.all([
    apiF('/api/prompts?limit=100&sort=' + encodeURIComponent(sort.key)),
    apiF('/api/prompt-trend'),
  ]);

  const last = trend[trend.length - 1];
  const prev = trend[trend.length - 2];
  let delta = '';
  if (last && prev && prev.median_cost_usd > 0) {
    const d = (last.median_cost_usd - prev.median_cost_usd) / prev.median_cost_usd * 100;
    const arrow = d > 0 ? '▲' : '▼';
    delta = ` · ${arrow} ${Math.abs(d).toFixed(0)}% vs previous week`;
  }

  const sortTabs = `
    <div class="range-tabs" role="tablist">
      ${SORTS.map(s => `<button data-sort="${s.key}" class="${s.key === sort.key ? 'active' : ''}">${s.label}</button>`).join('')}
    </div>`;

  root.innerHTML = `
    <div class="flex" style="margin-bottom:14px">
      <h2 style="margin:0;font-size:16px;letter-spacing:-0.01em">Prompts</h2>
      <div class="spacer"></div>
      ${sortTabs}
    </div>

    <div class="card">
      <h3 style="margin:0 0 4px">Median cost per prompt, by week</h3>
      <p class="muted" style="margin:0 0 12px">
        Each prompt is charged the full span of work it triggered — every assistant turn,
        subagent and tool call until your next prompt.
        ${last ? `Latest week: ${fmt.usd4(last.median_cost_usd)} median across ${last.prompts} prompts, ${last.median_turns} turns each${delta}.` : ''}
      </p>
      <div id="trend" style="height:220px"></div>
    </div>

    <div class="card">
      <p class="muted" style="margin:0 0 14px">
        Top 100 by ${sort.label.toLowerCase()}. High turns on a small ask usually means the
        prompt was underspecified. Click a row for the full text.
      </p>
      <table id="prompts">
        <thead><tr>
          <th>prompt</th>
          <th>model</th>
          <th class="num">turns</th>
          <th class="num">tools</th>
          <th class="num">cost</th>
          <th class="num">cache</th>
          <th>when</th>
          <th>session</th>
        </tr></thead>
        <tbody>
          ${rows.map((r, i) => `
            <tr data-i="${i}" style="cursor:pointer">
              <td class="blur-sensitive">${fmt.htmlSafe(fmt.short(r.prompt_text, 90))}</td>
              <td><span class="badge ${fmt.modelClass(r.model)}">${fmt.htmlSafe(fmt.modelShort(r.model) || '—')}</span></td>
              <td class="num">${fmt.int(r.turns)}</td>
              <td class="num">${fmt.int(r.tool_calls)}</td>
              <td class="num mono">${fmt.usd4(r.cost_usd)}</td>
              <td class="num">${pct(r.cache_hit_pct)}</td>
              <td class="mono">${fmt.ts(r.timestamp)}</td>
              <td><a href="#/sessions/${encodeURIComponent(r.session_id)}" class="mono" onclick="event.stopPropagation()">${fmt.htmlSafe(r.session_id.slice(0, 8))}…</a></td>
            </tr>`).join('') || '<tr><td colspan="8" class="muted">no prompts yet</td></tr>'}
        </tbody>
      </table>
    </div>
    <div id="drawer"></div>
  `;

  if (trend.length) {
    lineChart(document.getElementById('trend'), {
      x: trend.map(t => t.week),
      series: [{ name: 'median $/prompt', data: trend.map(t => t.median_cost_usd) }],
    });
  }

  root.querySelectorAll('.range-tabs button').forEach(btn => {
    btn.addEventListener('click', () => writeSort(btn.dataset.sort));
  });

  root.querySelectorAll('#prompts tbody tr').forEach(tr => {
    tr.addEventListener('click', () => {
      const r = rows[Number(tr.dataset.i)];
      const drawer = document.getElementById('drawer');
      drawer.innerHTML = `
        <div class="card">
          <h3 style="display:flex;align-items:center">
            <span>Prompt detail</span>
            <span class="spacer"></span>
            <span class="badge ${fmt.modelClass(r.model)}">${fmt.htmlSafe(fmt.modelShort(r.model) || '—')}</span>
          </h3>
          <pre class="blur-sensitive">${fmt.htmlSafe(r.prompt_text || '')}</pre>
          <div class="flex" style="margin-top:12px;flex-wrap:wrap;gap:14px">
            <span class="muted">${fmt.ts(r.timestamp)}</span>
            <span class="muted">${fmt.int(r.turns)} turns · ${fmt.int(r.tool_calls)} tool calls · ${fmt.usd4(r.cost_usd)}${r.cost_estimated ? ' (est.)' : ''}</span>
            <span class="muted">${fmt.int(r.billable_tokens)} billable · ${fmt.int(r.cache_read_tokens)} cache rd · ${pct(r.cache_hit_pct)} cache hit</span>
            <span class="spacer"></span>
            <a href="#/sessions/${encodeURIComponent(r.session_id)}">Open session →</a>
          </div>
        </div>`;
      drawer.scrollIntoView({ behavior: 'smooth', block: 'nearest' });
    });
  });
}
