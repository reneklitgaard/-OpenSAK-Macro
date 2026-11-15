-- OpenSAK Macro
-- Name: Leaflet Map
-- Author: OpenSAK Lua port of the supplied GSAK Leaflet Map macro
-- Version: 1.0.0
-- Requires-API: 4
-- Description: Map the active filter with clusters, cache labels, status icons and extra waypoints.
-- Permissions: open
-- The generated page needs internet: Leaflet/MarkerCluster from unpkg.com,
-- map tiles from Esri or OpenTopoMap. Cache data stays in the
-- local HTML file; tile requests reveal the viewed map area to the tile provider.
-- Listing links open only when clicked. No GSAK One Click, DeLorme or helper script.
-- No arg, io, os, database changes or external Lua packages are required.

local opts = opensak.form{
  title = "Leaflet Map", remember = true,
  fields = {
    {type="choice", id="coordinates", label="Coordinates", options={"Corrected when available", "Original / posted"}},
    {type="choice", id="labels", label="Cache labels", options={"None", "Name", "Code", "Name + code"}, default="Code"},
    {type="checkbox", id="children", label="Show extra waypoints", default=false},
    {type="checkbox", id="childlabels", label="Show waypoint labels", default=false},
    {type="checkbox", id="clusters", label="Cluster nearby caches", default=true},
    {type="number", id="clusterzoom", label="Stop clustering at zoom", default=16, min=1, max=19},
    {type="checkbox", id="scroll", label="Scroll-wheel zoom", default=true},
    {type="checkbox", id="range", label="2-mile circle around the selected cache (posted coordinates)", default=false},
    {type="checkbox", id="separation", label="161-metre separation circles (physical locations)", default=false},
  },
}
if not opts then return end

local function coord(lat, lon)
  lat, lon = tonumber(lat), tonumber(lon)
  if not lat or not lon or lat ~= lat or lon ~= lon or lat < -90 or lat > 90 or lon < -180 or lon > 180 then return nil end
  if lat == 0 and lon == 0 then return nil end
  return {lat, lon}
end

-- Embed only JSON values we construct. Escaping < prevents user-entered names
-- containing </script> from terminating the embedded data block.
local function json(value)
  local kind = type(value)
  if kind == "nil" then return "null" end
  if kind == "boolean" then return value and "true" or "false" end
  if kind == "number" then return string.format("%.15g", value) end
  if kind == "string" then
    local escaped = value:gsub('[%z\1-\31\\"<> &]', function(c)
      if c == '\\' then return '\\\\' end
      if c == '"' then return '\\"' end
      return string.format('\\u%04x', string.byte(c))
    end):gsub('\226\128\168', '\\u2028'):gsub('\226\128\169', '\\u2029')
    return '"' .. escaped .. '"'
  end
  local items = {}
  if #value > 0 then
    for _, v in ipairs(value) do items[#items+1] = json(v) end
    return '[' .. table.concat(items, ',') .. ']'
  end
  for k, v in pairs(value) do items[#items+1] = json(tostring(k)) .. ':' .. json(v) end
  table.sort(items)
  return '{' .. table.concat(items, ',') .. '}'
end

local rows, skipped = {}, 0
local current = opensak.current()
local progress = opensak.progress("Leaflet Map", opensak.count())
local n = 0
for c in opensak.caches{fields={"name","type","lat","lon","corrected","found","dnf","owned","archived","available","difficulty","terrain","container","owner","placed_by","favorite_points","waypoint_count"}} do
  n = n + 1
  if not progress:update(n, c.code) then progress:close(); return end
  local posted = coord(c.lat, c.lon)
  local corrected = c.corrected and coord(c.corrected.lat, c.corrected.lon)
  local point = opts.coordinates == "Original / posted" and posted or (corrected or posted)
  -- Avoid Lua's and/or fallback when original coordinates are invalid.
  if opts.coordinates == "Original / posted" then point = posted end
  if point then
    local row = {code=c.code, name=c.name or c.code, type=c.type or "Unknown", point=point,
      posted=posted, corrected=corrected, found=c.found == true, dnf=c.dnf == true,
      owned=c.owned == true, archived=c.archived == true, disabled=c.available == false,
      difficulty=c.difficulty, terrain=c.terrain, container=c.container,
      owner=c.owner or c.placed_by, favorites=c.favorite_points, children={}}
    if opts.children and (c.waypoint_count == nil or c.waypoint_count > 0) then
      for _, w in ipairs(opensak.waypoints(c.code) or {}) do
        local p = coord(w.lat, w.lon)
        if p then row.children[#row.children+1] = {point=p, name=w.name or w.prefix or "Waypoint", code=w.code or w.prefix or "", type=w.type or "Waypoint"} end
      end
    end
    rows[#rows+1] = row
  else skipped = skipped + 1 end
end
progress:close()
if #rows == 0 then opensak.message("No caches with valid coordinates in the active filter."); return end
local data = {
  caches=rows, options={labels=opts.labels, children=opts.children == true, childlabels=opts.childlabels == true,
    clusters=opts.clusters == true, clusterzoom=math.max(1, math.min(19, math.floor(tonumber(opts.clusterzoom) or 16))),
    scroll=opts.scroll == true, range=opts.range == true, separation=opts.separation == true},
  selected=current and current.code, rangeCenter=current and coord(current.lat, current.lon),
  database=opensak.database(), filter=opensak.filter_name(), skipped=skipped,
}

local page = [=[<!doctype html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><meta name="referrer" content="no-referrer">
<title>Leaflet Map · OpenSAK</title>
<link rel="stylesheet" href="https://unpkg.com/leaflet@1.9.4/dist/leaflet.css">
<link rel="stylesheet" href="https://unpkg.com/leaflet.markercluster@1.5.3/dist/MarkerCluster.css">
<link rel="stylesheet" href="https://unpkg.com/leaflet.markercluster@1.5.3/dist/MarkerCluster.Default.css">
<style>
:root{--paper:#fff;--ink:#202c32;--muted:#5c6c75;--line:#d7e0e4;--brand:#176c55;--accent:#d4eddf;--map:#e6eceb;--traditional:#20884a;--multi:#d59d16;--mystery:#2680b9;--earth:#91683b;--event:#ba4261;--virtual:#6c56a5;--other:#556975;--found:#176c55;--dnf:#b52b3b;--own:#29448f;--waypoint:#526575;--ring:#c83948;--separation:#577b97;--shadow:0 3px 14px #202c3222}
*{box-sizing:border-box}html,body{height:100%;margin:0;font:14px/1.45 "Segoe UI",system-ui,sans-serif;color:var(--ink)}
body{display:flex;flex-direction:column;background:var(--paper)}header{display:flex;align-items:center;justify-content:space-between;gap:12px;padding:12px 20px;border-bottom:1px solid var(--line);flex-wrap:wrap}
h1{margin:0;font-size:21px;font-weight:650}#context{font-size:12px;color:var(--muted);overflow-wrap:anywhere}#count{font-weight:650;color:var(--brand)}
.toolbar{display:flex;gap:12px;align-items:center;flex-wrap:wrap;padding:10px 20px;border-bottom:1px solid var(--line)}
button,input,select{font:inherit}button,select,input[type=search]{border:1px solid var(--line);border-radius:5px;background:var(--paper);color:var(--ink);padding:7px 10px}button{cursor:pointer}button:hover{background:var(--accent)}button:disabled{opacity:.45;cursor:default}
input[type=search]{width:220px;max-width:100%}label{display:flex;gap:5px;align-items:center}input[type=checkbox]{accent-color:var(--brand)}#map{flex:1;min-height:300px;background:var(--map);position:relative}footer{display:flex;gap:14px;flex-wrap:wrap;padding:8px 20px;color:var(--muted);font-size:12px}
.legend{display:flex;gap:12px;flex-wrap:wrap}.legend span{white-space:nowrap}.dot{width:10px;height:10px;display:inline-block;border-radius:50%;margin-right:4px}.traditional{--type:var(--traditional)}.multi{--type:var(--multi)}.mystery{--type:var(--mystery)}.earth{--type:var(--earth)}.event{--type:var(--event)}.virtual{--type:var(--virtual)}.other{--type:var(--other)}.dot{background:var(--type)}
.cache-icon{background:none;border:0}.pin{width:30px;height:30px;border:2px solid var(--paper);border-radius:50%;background:var(--type);color:var(--paper);box-shadow:var(--shadow);display:flex;justify-content:center;align-items:center;font-size:17px;font-weight:750;position:relative}.pin.archived{opacity:.55}.pin.disabled{border-style:dashed}.pin.selected{outline:3px solid var(--ink);outline-offset:2px}.status{position:absolute;right:-7px;bottom:-6px;min-width:16px;height:16px;border:1px solid var(--paper);border-radius:50%;font-size:10px;background:var(--found)}.status.dnf{background:var(--dnf)}.status.owned{background:var(--own)}.wp .pin{width:24px;height:24px;border-radius:4px;background:var(--waypoint);font-size:12px}
.leaflet-tooltip.cache-label{border:1px solid var(--line);border-radius:3px;box-shadow:none;color:var(--ink);background:var(--paper);font-size:11px;padding:2px 5px;width:max-content;max-width:190px;white-space:normal;overflow-wrap:anywhere}.popup-title{font-size:16px;margin:3px 0 8px;overflow-wrap:anywhere}.popup-meta{color:var(--muted);margin:7px 0}.popup-code{font-weight:650;color:var(--brand)}.popup-status{font-size:12px;margin:8px 0}.coords{font-family:Consolas,monospace;font-size:11px}.leaflet-popup-content{max-width:260px;overflow-wrap:anywhere}.leaflet-popup-content-wrapper{background:var(--paper);color:var(--ink)}
#error{position:absolute;z-index:2000;top:15px;left:50%;transform:translateX(-50%);width:min(90%,500px);background:var(--paper);padding:15px;border:1px solid var(--line);border-radius:5px;box-shadow:var(--shadow)}[hidden]{display:none!important}
@media(max-width:600px){header,.toolbar{padding:10px 12px}.toolbar{gap:8px}input[type=search]{width:150px}.toolbar label{font-size:12px}footer{padding:8px 12px;gap:5px}.legend{gap:8px}h1{font-size:19px}}
</style></head><body>
<header><div><h1>Leaflet Map <span style="font-size:12px;color:var(--muted)">/ OpenSAK</span></h1><div id="context"></div></div><div id="count"></div></header>
<div class="toolbar"><input id="search" type="search" placeholder="Name or GC code" aria-label="Find cache">
<button id="fit" title="Fit all visible caches">⌖ All caches</button><button id="selected" title="Go to the selected OpenSAK cache">◎ Selected</button>
<label><input type="checkbox" id="cluster">Clusters</label><label>Labels <select id="labels" aria-label="Cache labels"><option>None</option><option>Name</option><option>Code</option><option>Name + code</option></select></label>
<label><input type="checkbox" id="children">Waypoints</label><label><input type="checkbox" id="range">2 miles</label>
</div><div id="map"><div id="error" hidden role="alert"></div></div>
<footer><div class="legend"><span><i class="dot traditional"></i>Traditional</span><span><i class="dot multi"></i>Multi</span><span><i class="dot mystery"></i>Mystery</span><span><i class="dot earth"></i>Earth</span><span><i class="dot event"></i>Event</span><span><i class="dot virtual"></i>Virtual</span></div><span>✓ Found · × DNF · ★ Owned · ◆ Corrected</span><span id="note"></span></footer>
<script id="map-data" type="application/json">]=] .. json(data) .. [=[</script>
<script src="https://unpkg.com/leaflet@1.9.4/dist/leaflet.js"></script>
<script src="https://unpkg.com/leaflet.markercluster@1.5.3/dist/leaflet.markercluster.js"></script>
<script>
(function(){
'use strict';
const data=JSON.parse(document.getElementById('map-data').textContent), opt=data.options;
const $=id=>document.getElementById(id);
const esc=v=>String(v==null?'':v).replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
function error(message){$('error').hidden=false;$('error').textContent=message;}
if(!window.L){error('The map library could not load. Check your internet connection, then reopen this page.');return;}
try{
const map=L.map('map',{scrollWheelZoom:opt.scroll,preferCanvas:true}).setView([55.7,12.5],6);
const street=L.tileLayer('https://server.arcgisonline.com/ArcGIS/rest/services/World_Street_Map/MapServer/tile/{z}/{y}/{x}',{maxZoom:19,referrerPolicy:'no-referrer',attribution:'Tiles &copy; Esri &middot; Source: Esri, DeLorme, NAVTEQ, USGS, Intermap, iPC, NRCAN, Esri Japan, METI, Esri China (Hong Kong), Esri (Thailand), TomTom'}).addTo(map);
const topo=L.tileLayer('https://{s}.tile.opentopomap.org/{z}/{x}/{y}.png',{maxZoom:17,referrerPolicy:'no-referrer',attribution:'Map data &copy; OpenStreetMap | Map style &copy; <a href="https://opentopomap.org">OpenTopoMap</a> (CC-BY-SA)'});
const satellite=L.tileLayer('https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}',{maxZoom:19,referrerPolicy:'no-referrer',attribution:'Tiles &copy; Esri, Maxar, Earthstar Geographics'});
L.control.layers({'Street':street,'Topographic':topo,'Satellite':satellite},null,{collapsed:true}).addTo(map);
L.control.scale({metric:true,imperial:true}).addTo(map);
function type(c){let t=c.type.toLowerCase();if(t.includes('traditional'))return ['traditional','●'];if(t.includes('multi'))return ['multi','◆'];if(t.includes('mystery')||t.includes('unknown'))return ['mystery','?'];if(t.includes('earth'))return ['earth','E'];if(t.includes('event'))return ['event','◷'];if(t.includes('virtual')||t.includes('webcam'))return ['virtual','V'];return ['other','◇'];}
function popup(c){const statuses=[c.found?'✓ Found':'',c.dnf?'× DNF':'',c.owned?'★ Owned':'',c.archived?'Archived':'',c.disabled?'Disabled':'',c.corrected?'◆ Corrected coordinates available':''].filter(Boolean);
return '<div class="popup-title">'+esc(c.name)+'</div><a class="popup-code" href="https://www.geocaching.com/geocache/'+encodeURIComponent(c.code)+'" target="_blank" rel="noopener noreferrer">'+esc(c.code)+' ↗</a><div class="popup-meta">'+esc(c.type)+' · '+esc(c.container||'—')+'<br>D '+esc(c.difficulty||'—')+' / T '+esc(c.terrain||'—')+' · ♥ '+esc(c.favorites==null?'—':c.favorites)+(c.owner?'<br>By '+esc(c.owner):'')+'</div><div class="popup-status">'+esc(statuses.join(' · '))+'</div><div class="coords">Shown: '+c.point.map(v=>v.toFixed(5)).join(', ')+'</div>'+(c.posted?'<div class="coords">Posted: '+c.posted.map(v=>v.toFixed(5)).join(', ')+'</div>':'');}
const items=data.caches.map(c=>{const [kind,symbol]=type(c),status=c.owned?['owned','★']:c.found?['found','✓']:c.dnf?['dnf','×']:null;
const icon=L.divIcon({className:'cache-icon '+kind,html:'<div class="pin'+(c.archived?' archived':'')+(c.disabled?' disabled':'')+(c.code===data.selected?' selected':'')+'">'+symbol+(status?'<span class="status '+status[0]+'">'+status[1]+'</span>':'')+'</div>',iconSize:[30,30],iconAnchor:[15,15],popupAnchor:[0,-16]});
const marker=L.marker(c.point,{icon,title:c.code+' — '+c.name,alt:c.code,keyboard:true}).bindPopup(popup(c));
const children=Array.isArray(c.children)?c.children:[];
const waypoints=children.map(w=>{const m=L.marker(w.point,{icon:L.divIcon({className:'cache-icon wp',html:'<div class="pin">'+(w.type.toLowerCase().includes('parking')?'P':'◇')+'</div>',iconSize:[24,24],iconAnchor:[12,12]}),title:c.code+' · '+w.name}).bindPopup('<div class="popup-title">'+esc(w.name)+'</div>'+esc(w.type)+'<br>'+esc(w.code)+'<br>Parent: '+esc(c.code));if(opt.childlabels)m.bindTooltip(esc(w.name),{permanent:true,direction:'right',className:'cache-label'});return m;});
return {c,marker,waypoints,kind};});
const canCluster=typeof L.markerClusterGroup==='function';
const clusters=canCluster?L.markerClusterGroup({disableClusteringAtZoom:opt.clusterzoom,maxClusterRadius:50,showCoverageOnHover:false}):L.layerGroup();
const plain=L.layerGroup(),children=L.layerGroup(),separation=L.layerGroup();let visible=items;
const range=data.rangeCenter?L.circle(data.rangeCenter,{radius:3218.69,color:getComputedStyle(document.documentElement).getPropertyValue('--ring').trim(),weight:1,fillOpacity:.08,interactive:false}):null;
$('context').textContent=[data.database,data.filter||'All caches'].join(' · ');
$('cluster').checked=opt.clusters&&canCluster;$('cluster').disabled=!canCluster;
$('labels').value=opt.labels||'Code';$('children').checked=opt.children;$('children').disabled=!opt.children;
$('range').checked=opt.range&&!!range;$('range').disabled=!range;
$('selected').disabled=!items.some(i=>i.c.code===data.selected);
$('note').textContent=(data.skipped?data.skipped+' without valid coordinates · ':'')+(!canCluster?'Clustering unavailable · ':'')+'Local cache snapshot';
function labels(){items.forEach(i=>{i.marker.unbindTooltip();const mode=$('labels').value;let text=mode==='Name'?i.c.name:mode==='Code'?i.c.code:mode==='Name + code'?i.c.name+' · '+i.c.code:'';if(text)i.marker.bindTooltip(esc(text),{permanent:true,direction:'right',className:'cache-label',offset:[12,0]});});}
function physical(i){return ['traditional','multi'].includes(i.kind)||/wherigo|letterbox|project ape/i.test(i.c.type)||(i.kind==='mystery'&&!!i.c.corrected);}
function render(){clusters.clearLayers();plain.clearLayers();children.clearLayers();separation.clearLayers();map.removeLayer(clusters);map.removeLayer(plain);
const q=$('search').value.toLowerCase().trim();visible=items.filter(i=>(i.c.code+' '+i.c.name).toLowerCase().includes(q));
const target=$('cluster').checked?clusters:plain;target.addLayers?target.addLayers(visible.map(i=>i.marker)):visible.forEach(i=>target.addLayer(i.marker));map.addLayer(target);
visible.forEach(i=>{i.waypoints.forEach(w=>children.addLayer(w));if(opt.separation&&physical(i))separation.addLayer(L.circle(i.c.point,{radius:160.9,color:getComputedStyle(document.documentElement).getPropertyValue('--separation').trim(),weight:1,fillOpacity:.06,interactive:false}));});
if($('children').checked)children.addTo(map);else map.removeLayer(children);separation.addTo(map);
$('count').textContent=visible.length+' / '+items.length+' caches';}
function fit(){const points=visible.flatMap(i=>$('children').checked?[i.c.point,...i.waypoints.map(w=>w.getLatLng())]:[i.c.point]);if(points.length)map.fitBounds(L.latLngBounds(points),{padding:[35,35],maxZoom:16});}
function setRange(){if(range){if($('range').checked)range.addTo(map);else map.removeLayer(range);}}
$('search').addEventListener('input',render);$('search').addEventListener('keydown',e=>{if(e.key==='Enter'){fit();if(visible.length===1)open(visible[0]);}});
$('cluster').addEventListener('change',render);$('children').addEventListener('change',render);$('labels').addEventListener('change',labels);$('range').addEventListener('change',setRange);$('fit').addEventListener('click',fit);
function open(i){if($('cluster').checked&&canCluster)clusters.zoomToShowLayer(i.marker,()=>i.marker.openPopup());else{map.setView(i.c.point,Math.max(map.getZoom(),16));i.marker.openPopup();}}
$('selected').addEventListener('click',()=>{const i=items.find(i=>i.c.code===data.selected);if(!i)return;$('search').value='';render();open(i);});
labels();render();setRange();fit();
}catch(e){error('The map could not be created: '+e.message);}
})();
</script></body></html>]=]
local path = opensak.write_text(opensak.temp_dir() .. "/LeafletMap.html", page)
print("Leaflet Map: " .. #rows .. " caches; " .. skipped .. " without valid coordinates.")
if opts.range and not data.rangeCenter then print("No valid posted coordinates for the selected cache: range circle omitted.") end
opensak.open(path)
