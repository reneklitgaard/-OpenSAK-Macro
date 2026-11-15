-- OpenSAK Macro
-- Name: Placed PQ
-- Author: Lil Devil, Kai Team, lignumaqua, Clyde (Lua port)
-- Version: 3.0.2-lua
-- Requires-API: 3
-- Description: Generate Pocket Query date ranges by placed date for the caches in the current filter.
-- Permissions: open

local MAXPQ = 1000
local MONTHS = {"January","February","March","April","May","June",
  "July","August","September","October","November","December"}

local function addDay(iso)
  local y, m, d = iso:match("(%d+)-(%d+)-(%d+)")
  y, m, d = tonumber(y), tonumber(m), tonumber(d) + 1
  local dim = {31,28,31,30,31,30,31,31,30,31,30,31}
  if (y % 4 == 0 and y % 100 ~= 0) or y % 400 == 0 then dim[2] = 29 end
  if d > dim[m] then d = 1; m = m + 1 end
  if m > 12 then m = 1; y = y + 1 end
  return string.format("%04d-%02d-%02d", y, m, d)
end

local function fmt(iso, gc, edge)
  if not iso then return edge == "min" and "Minimum date" or "Maximum date" end
  local y, m, d = iso:match("(%d+)-(%d+)-(%d+)")
  if gc then return MONTHS[tonumber(m)] .. " " .. d .. ", " .. y end
  return d .. "-" .. m .. "-" .. y
end

local function maxCaption(buffer)
  return "Maximum number of caches per Pocket Query: " .. (MAXPQ - (tonumber(buffer) or 0))
end

-- Form
local v = opensak.form{
  title = "Placed PQ",
  remember = true,
  fields = {
    { type = "label", label = "Number of caches to subtract from the maximum, as a buffer for caches that are reactivated:" },
    { type = "number", id = "buffer", label = "Buffer", default = 10, min = 0, max = 20,
      on_change = function(f, value) f:set_label("maxlabel", maxCaption(value)) end },
    { type = "label", id = "maxlabel", label = maxCaption(10) },
    { type = "checkbox", id = "gc", label = "Show dates in geocaching.com format (Month dd, yyyy)", default = true },
  },
}
if not v then return end
local buffer = tonumber(v.buffer) or 10
local gc = v.gc and true or false
local maxCaches = MAXPQ - buffer

-- Count caches per placed date in the active filter (archived skipped)
local counts, keys, total = {}, {}, 0
for c in opensak.caches{ fields = {"hidden", "archived"} } do
  local d = c.hidden and tostring(c.hidden):sub(1, 10)
  if not c.archived and d and d:match("^%d%d%d%d%-%d%d%-%d%d$") then
    if not counts[d] then counts[d] = 0; keys[#keys + 1] = d end
    counts[d] = counts[d] + 1
    total = total + 1
  end
end
if total == 0 then
  opensak.message("No unarchived caches in current filter. Aborting.")
  return
end
table.sort(keys)

-- Split into PQs
local raw, from, to, group = {}, nil, keys[1], 0
for _, date in ipairs(keys) do
  local qty = counts[date]
  if group + qty <= maxCaches then
    group = group + qty; to = date
  else
    raw[#raw + 1] = { from = from, to = to, count = group }
    group = qty; from = addDay(to); to = date
  end
end
raw[#raw + 1] = { from = from, to = nil, count = group }

local digits = #tostring(math.floor(total / (maxCaches * 0.85) + 0.5))
local rows = {}
for i, r in ipairs(raw) do
  rows[i] = {
    pq = string.format("%0" .. digits .. "d", i),
    from = fmt(r.from, gc, "min"),
    to = fmt(r.to, gc, "max"),
    count = r.count,
    done = "☐",
  }
  print(rows[i].pq, rows[i].from, rows[i].to, rows[i].count)
end

-- HTML report
local esc = opensak.html.escape
local filter = opensak.filter_name and opensak.filter_name() or ""
if filter == "" then filter = "No filter" end
local today = (os and os.date) and os.date("%Y-%m-%d") or ""

local trs = {}
for _, r in ipairs(rows) do
  local pct = math.floor(r.count / maxCaches * 100 + 0.5)
  trs[#trs + 1] = string.format(
    '<tr><td class="num">%s</td><td>%s</td><td>%s</td>' ..
    '<td><div class="bar"><span style="width:%d%%"></span></div><b>%d</b></td>' ..
    '<td class="chk"><input type="checkbox"></td></tr>',
    esc(r.pq), esc(r.from), esc(r.to), pct, r.count)
end

local css = [[
:root{--g:#2f6b45;--g2:#e7f1ea;--sand:#fbf7ee;--ink:#1f2a24;--mute:#6b7a70}
body{background:var(--sand);color:var(--ink);font-family:system-ui,"Segoe UI",sans-serif;max-width:860px;margin:40px auto;padding:0 20px}
.pq-head{display:flex;gap:12px;flex-wrap:wrap;margin:18px 0 24px}
.pq-tile{flex:1;min-width:140px;background:#fff;border:1px solid #dfe7e1;border-radius:12px;padding:14px 16px}
.pq-tile small{display:block;color:var(--mute);font-size:12px;text-transform:uppercase;letter-spacing:.08em}
.pq-tile b{font-size:24px;color:var(--g)}
table.pq{width:100%;border-collapse:separate;border-spacing:0;background:#fff;border:1px solid #dfe7e1;border-radius:12px;overflow:hidden}
table.pq th{background:var(--g);color:#fff;font-weight:600;text-align:left;padding:10px 14px}
table.pq td{padding:10px 14px;border-top:1px solid #eef2ef}
table.pq tr:nth-child(even) td{background:#f7faf8}
table.pq tr.done td{opacity:.45;text-decoration:line-through}
table.pq tbody tr{cursor:pointer}table.pq tbody tr:hover td{background:var(--g2)}
.num{font-family:ui-monospace,Consolas,monospace;color:var(--mute);width:40px}
.chk{text-align:center;width:60px}.chk input{width:18px;height:18px;accent-color:var(--g)}
.bar{display:inline-block;width:90px;height:8px;background:#eef2ef;border-radius:4px;margin-right:10px;vertical-align:middle}
.bar span{display:block;height:100%;background:var(--g);border-radius:4px}
.progress{color:var(--mute);margin-top:12px;font-size:14px}
]]

local script = [[
<script>
document.querySelectorAll('table.pq tbody tr').forEach(function(tr){
  var cb=tr.querySelector('input');
  function upd(){tr.classList.toggle('done',cb.checked);
    var n=document.querySelectorAll('table.pq input:checked').length;
    document.getElementById('prog').textContent=n+' of '+document.querySelectorAll('table.pq tbody tr').length+' PQs done';}
  tr.addEventListener('click',function(e){if(e.target!==cb)cb.checked=!cb.checked;upd();});
  upd();
});
</script>]]

local page = opensak.html.page{
  title = "Placed by Date PQ",
  subtitle = esc(opensak.database()) .. " · " .. esc(filter) .. (today ~= "" and (" · " .. today) or ""),
  css = css,
  '<div class="pq-head">' ..
    '<div class="pq-tile"><small>Caches</small><b>' .. total .. '</b></div>' ..
    '<div class="pq-tile"><small>Pocket Queries</small><b>' .. #rows .. '</b></div>' ..
    '<div class="pq-tile"><small>Max per PQ</small><b>' .. maxCaches .. '</b></div>' ..
  '</div>',
  '<table class="pq"><thead><tr><th>PQ</th><th>From</th><th>To</th><th>Count</th><th>Done</th></tr></thead><tbody>' ..
    table.concat(trs) .. '</tbody></table>',
  '<p class="progress" id="prog"></p>',
  script,
}
local path = opensak.write_text(opensak.temp_dir() .. "/PlacedPQ.htm", page)
opensak.open(path)
