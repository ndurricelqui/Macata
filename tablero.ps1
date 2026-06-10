# tablero.ps1 — Genera tablero.html con stock real de MACATA SA, notas de pedido y stock proyectado

$BASE     = Split-Path -Parent $MyInvocation.MyCommand.Path
$CSV_FILE = Join-Path $BASE "Reporte Stock.csv"
$NP_DIR   = Join-Path $BASE "data\notas_pedido"
$OUTPUT   = Join-Path $BASE "tablero.html"

# ── 6 familias y sus descripciones en el CSV ──────────────────────────────────
$ORDEN_FAMILIAS = @(
    "Cargo Ripstop",
    "Cargo Cazador",
    "Bombacha lisa",
    "Cargo elastizado fit",
    "Pantalón de trabajo",
    "Camisa de trabajo"
)

$famCSV = @{
    "Cargo Ripstop"        = @(
        "PANTALON CARGO RIPSTOP CH (38-54) PAMPERO",
        "PANTALON CARGO RIPSTOP GR (56-60) PAMPERO"
    )
    "Cargo Cazador"        = @(
        "PANTALON CAZ. CARGO II H. PAMPERO AZUL CH (36-54)",
        "PANTALON CAZADOR CARGO II H. PAMPERO CHICO (36-54)",
        "PANTALON CAZ. CARGO II H. PAMPER AZUL GD (56-70)",
        "PANTALON CAZADOR CARGO II H. PAMPERO GRANDE (56-70)"
    )
    "Bombacha lisa"        = @(
        "BOMBACHA LISA MUJER PAMPERO",
        "BOMBACHA LISA HOMBRE PAMPERO (38-54)",
        "BOMBACHA LISA H. PAMPERO AZUL (38-54)",
        "BOMBACHA LISA HOMBRE PAMPERO (56-60)",
        "BOMBACHA LISA H.PAMPERO AZUL (56-60)",
        "BOMBACHA LISA NIÑO PAMPERO"
    )
    "Cargo elastizado fit" = @(
        "PANTALON CARGO ELASTIZADO PAMPERO FIT"
    )
    "Pantalón de trabajo"  = @(
        "PANTALON DE TRAB. H. PAMPERO AZUL CH(36-60)",
        "PANTALON DE TRABAJO HOMBRE PAMPERO CH(36-60)"
    )
    "Camisa de trabajo"    = @(
        "CAMISA DE TRAB H.M/L PAMPERO AZUL CH(38-48)",
        "CAMISA DE TRAB H.M/L PAMPERO AZUL G(58-70)",
        "CAMISA DE TRAB H.M/L PAMPERO AZUL M(50-56)",
        "CAMISA DE TRABAJO H. M/L PAMPERO CH (36-48)",
        "CAMISA DE TRABAJO H.M/L PAMPERO GRANDE(58-70)",
        "CAMISA DE TRABAJO H.M/L PAMPERO MED.(50-56)"
    )
}

# ── Reverse: CSV desc → familia ────────────────────────────────────────────────
$csvToFam = @{}
foreach ($fam in $famCSV.Keys) {
    foreach ($desc in $famCSV[$fam]) { $csvToFam[$desc] = $fam }
}

# ── Normalizar descripción de NP → familia (por keywords) ─────────────────────
function Get-Familia([string]$desc) {
    $d = $desc.ToLower()
    if ($d -match 'ripstop')                        { return 'Cargo Ripstop' }
    if ($d -match 'cazador')                        { return 'Cargo Cazador' }
    if ($d -match 'bombacha.*lisa')                 { return 'Bombacha lisa' }
    if ($d -match 'cargo.*fit|elastizado')          { return 'Cargo elastizado fit' }
    if ($d -match 'camisa.{0,10}(trabajo|trab\b)')  { return 'Camisa de trabajo' }
    if ($d -match 'pant.*trabajo')                  { return 'Pantalón de trabajo' }
    return $null
}

# ── Leer CSV filtrado por MACATA SA ───────────────────────────────────────────
# Usamos -Header explícito para evitar problemas de encoding con nombres de columna acentuados
$csvRows = Get-Content $CSV_FILE -Encoding UTF8 | Select-Object -Skip 1 |
    ConvertFrom-Csv -Delimiter ';' -Header 'art_cod','art_desc','color_cod','color_desc','talle','nombre','cantidad'
$productos = $csvRows | Where-Object { $_.nombre -eq 'MACATA SA' } | ForEach-Object {
    $qty = [double]($_.cantidad -replace ',','.')
    [pscustomobject]@{
        codigo      = $_.art_cod
        descripcion = $_.art_desc
        color       = $_.color_desc
        talle       = $_.talle
        cantidad    = $qty
    }
}
$fechaActual = (Get-Date -Format "yyyy-MM-ddTHH:mm:ss")

# ── Stock real por (familia|color|talle) ──────────────────────────────────────
$realMap = @{}
foreach ($p in $productos) {
    if (-not $p.descripcion) { continue }
    $fam = $csvToFam[$p.descripcion]
    if (-not $fam) { continue }
    $k = "$fam|$($p.color)|$($p.talle)"
    if ($realMap.ContainsKey($k)) { $realMap[$k] += $p.cantidad }
    else                          { $realMap[$k]  = $p.cantidad }
}

# ── Leer notas de pedido ──────────────────────────────────────────────────────
$notas = @()
Get-ChildItem "$NP_DIR\*.json" | Where-Object { $_.Name -ne '_indice.json' } | ForEach-Object {
    $np = Get-Content $_.FullName -Raw | ConvertFrom-Json
    $notas += $np
}
$notas = $notas | Sort-Object fecha_emision

# ── NP pendientes por (familia|color|talle) ───────────────────────────────────
# Solo suma si la NP no está recibida; descuenta lo ya recibido por ítem
$npMap = @{}
foreach ($np in $notas) {
    if ($np.estado -eq "recibido") { continue }
    foreach ($item in $np.items) {
        $fam = Get-Familia $item.descripcion
        if (-not $fam) { continue }
        $recibido  = if ($item.cantidad_recibida) { [int]$item.cantidad_recibida } else { 0 }
        $pendiente = [int]$item.cantidad_solicitada - $recibido
        if ($pendiente -le 0) { continue }
        $k = "$fam|$($item.color)|$($item.talle)"
        if ($npMap.ContainsKey($k)) { $npMap[$k] += $pendiente }
        else                        { $npMap[$k]  = $pendiente }
    }
}

# ── Union de claves → array proyectado ────────────────────────────────────────
$allKeys = [System.Collections.Generic.HashSet[string]]::new()
foreach ($k in $realMap.Keys) { $allKeys.Add($k) | Out-Null }
foreach ($k in $npMap.Keys)   { $allKeys.Add($k) | Out-Null }

$proyList = foreach ($k in $allKeys) {
    $parts  = $k -split '\|', 3
    $fam    = $parts[0]
    $color  = $parts[1]
    $talle  = $parts[2]
    $real   = if ($realMap.ContainsKey($k)) { $realMap[$k] } else { 0 }
    $np     = if ($npMap.ContainsKey($k))   { $npMap[$k]   } else { 0 }
    [pscustomobject]@{
        familia      = $fam
        color        = $color
        talle        = $talle
        real         = [int]$real
        np_pendiente = [int]$np
        proyectado   = [int]($real + $np)
    }
}
$proyArray = @($proyList | Sort-Object familia, color, talle)

# ── KPIs ───────────────────────────────────────────────────────────────────────
$totalStockFisico  = [int](($proyArray | Measure-Object real        -Sum).Sum)
$totalNPPendiente  = [int](($proyArray | Measure-Object np_pendiente -Sum).Sum)
$totalProyectado   = [int](($proyArray | Measure-Object proyectado  -Sum).Sum)
$npActivasCount    = ($notas | Where-Object { $_.estado -ne "recibido" }).Count

# ── Serializar ─────────────────────────────────────────────────────────────────
$notasJson = $notas     | ConvertTo-Json -Depth 6 -Compress
$proyJson  = $proyArray | ConvertTo-Json -Depth 3 -Compress
if (-not $proyJson) { $proyJson = '[]' }

# ── Plantilla HTML ─────────────────────────────────────────────────────────────
$template = @'
<!DOCTYPE html>
<html lang="es">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>Tablero de Stock — Macata</title>
<style>
  *, *::before, *::after { box-sizing: border-box; margin: 0; padding: 0; }
  body { font-family: system-ui, -apple-system, sans-serif; background: #f1f5f9; color: #1e293b; }
  header { background: #1e3a5f; color: #fff; padding: 18px 28px; display: flex; align-items: center; gap: 16px; }
  header h1 { font-size: 1.3rem; font-weight: 700; letter-spacing: .02em; }
  header span { font-size: .82rem; opacity: .7; margin-left: auto; }
  .cards { display: flex; gap: 14px; padding: 20px 28px 0; flex-wrap: wrap; }
  .card { background: #fff; border-radius: 10px; padding: 16px 22px; flex: 1; min-width: 160px;
          box-shadow: 0 1px 4px rgba(0,0,0,.08); }
  .card .label { font-size: .75rem; color: #64748b; text-transform: uppercase; letter-spacing: .05em; }
  .card .value { font-size: 1.9rem; font-weight: 700; color: #1e3a5f; margin-top: 4px; }
  .card.ok   .value { color: #16a34a; }
  .card.warn .value { color: #d97706; }
  .tabs { display: flex; gap: 4px; padding: 20px 28px 0; }
  .tab-btn { padding: 8px 18px; border: none; border-radius: 8px 8px 0 0; cursor: pointer;
             font-size: .88rem; font-weight: 600; background: #cbd5e1; color: #475569; transition: .15s; }
  .tab-btn.active { background: #fff; color: #1e3a5f; box-shadow: 0 -2px 0 #1e3a5f inset; }
  .tab-btn:hover:not(.active) { background: #e2e8f0; }
  .tab-content { display: none; background: #fff; margin: 0 28px 28px;
                 border-radius: 0 10px 10px 10px; box-shadow: 0 1px 6px rgba(0,0,0,.08); padding: 16px; }
  .tab-content.active { display: block; }

  /* Notas de pedido */
  .badge { display: inline-block; padding: 2px 8px; border-radius: 20px; font-size: .73rem; font-weight: 600; }
  .badge-pendiente { background: #fef3c7; color: #b45309; }
  .badge-recibido  { background: #dcfce7; color: #15803d; }
  .badge-parcial   { background: #dbeafe; color: #1d4ed8; }
  .np-card { border: 1px solid #e2e8f0; border-radius: 8px; margin-bottom: 14px; overflow: hidden; }
  .np-header { background: #f8fafc; padding: 12px 16px; display: flex; gap: 16px;
               align-items: center; cursor: pointer; flex-wrap: wrap; }
  .np-header:hover { background: #f1f5f9; }
  .np-title { font-weight: 700; color: #1e3a5f; font-size: .95rem; }
  .np-meta  { font-size: .78rem; color: #64748b; }
  .np-body  { display: none; padding: 0 16px 12px; }
  .np-body.open { display: block; }
  table.np-table { width: 100%; border-collapse: collapse; font-size: .83rem; margin-top: 8px; }
  table.np-table th { padding: 7px 10px; text-align: left; font-weight: 600; color: #475569;
                      border-bottom: 2px solid #e2e8f0; background: #f8fafc; }
  table.np-table td { padding: 6px 10px; border-bottom: 1px solid #f1f5f9; }
  .grp-item-hdr td { background: #f8fafc; font-weight: 600; color: #334155;
                     border-top: 1px solid #e2e8f0; cursor: pointer; }
  .grp-item-hdr:hover td { background: #f1f5f9; }
  .grp-row.hidden { display: none; }
  .grp-arr { font-size: .7rem; color: #64748b; }

  /* Bloques de familia */
  .fam-block { border: 1px solid #e2e8f0; border-radius: 8px; margin-bottom: 14px; overflow: hidden; }
  .fam-hdr { background: #1e3a5f; color: #fff; padding: 11px 18px;
             display: flex; align-items: center; gap: 14px; cursor: pointer; }
  .fam-hdr:hover { background: #25487a; }
  .fam-title { font-size: .95rem; font-weight: 700; flex: 1; }
  .fam-total { font-size: .88rem; font-weight: 600; opacity: .85; }
  .fam-arr { font-size: .8rem; opacity: .6; }
  .fam-body { padding: 12px 14px 14px; overflow-x: auto; }
  .fam-body.closed { display: none; }

  /* Matriz color × talle */
  table.matrix-table { border-collapse: collapse; font-size: .82rem; min-width: 100%; }
  table.matrix-table th { padding: 7px 10px; background: #f0f4f8; color: #475569;
                           font-weight: 600; border: 1px solid #e2e8f0;
                           text-align: center; white-space: nowrap; }
  table.matrix-table th.col-color { text-align: left; }
  table.matrix-table td { padding: 6px 10px; border: 1px solid #f1f5f9;
                          text-align: center; white-space: nowrap; }
  table.matrix-table td.color-cell { text-align: left; font-weight: 500; background: #fafbfc; }
  table.matrix-table tr.total-row td { background: #f0f4f8; font-weight: 700; border-top: 2px solid #cbd5e1; }
  table.matrix-table td.total-col, table.matrix-table th.total-col {
    background: #e8f0fe; font-weight: 700; border-left: 2px solid #c7d7f5; }
  .ok   { color: #16a34a; }
  .zero { color: #cbd5e1; }
  .neg  { color: #dc2626; font-weight: 600; }
</style>
</head>
<body>

<header>
  <h1>Tablero de Stock — Macata</h1>
  <span>Stock al: %%FECHA%%</span>
</header>

<div class="cards">
  <div class="card">
    <div class="label">Stock físico total</div>
    <div class="value" id="kpi-stock-fisico">%%TOTAL_STOCK_FISICO%%</div>
  </div>
  <div class="card ok">
    <div class="label">En camino (NPs pendientes)</div>
    <div class="value">%%TOTAL_NP_PENDIENTE%%</div>
  </div>
  <div class="card">
    <div class="label">Stock proyectado total</div>
    <div class="value">%%TOTAL_PROYECTADO%%</div>
  </div>
  <div class="card warn">
    <div class="label">NPs activas</div>
    <div class="value">%%NP_ACTIVAS%%</div>
  </div>
</div>

<div class="tabs" style="margin-top:20px;">
  <button class="tab-btn active" onclick="showTab('notas',this)">Notas de Pedido</button>
  <button class="tab-btn" onclick="showTab('stock',this)">Stock Real</button>
  <button class="tab-btn" onclick="showTab('proyectado',this)">Stock Proyectado</button>
</div>

<div id="tab-notas" class="tab-content active">
  <div id="np-list"></div>
</div>

<div id="tab-stock" class="tab-content">
  <div id="stock-list"></div>
</div>

<div id="tab-proyectado" class="tab-content">
  <div id="proy-list"></div>
</div>

<script>
var NOTAS = %%NOTAS_JSON%%;
var PROY  = %%PROY_JSON%%;
if (!Array.isArray(NOTAS)) NOTAS = NOTAS ? [NOTAS] : [];
if (!Array.isArray(PROY))  PROY  = PROY  ? [PROY]  : [];

var ORDEN_FAMILIAS = [
  "Cargo Ripstop",
  "Cargo Cazador",
  "Bombacha lisa",
  "Cargo elastizado fit",
  "Pantalón de trabajo",
  "Camisa de trabajo"
];

// ── Google Sheets — Stock Real (mismo método que dashboard-compras) ────────────
var SHEETS_ID_STOCK  = '1P7nx8LWnT9eb4VoIAAIMtlC58qHjaedGYGborsjU1uI';
var SHEETS_GID_STOCK = '1493271108';

var FAM_DESC_MAP = [
  { fam: 'Cargo Ripstop',        descs: ['PANTALON CARGO RIPSTOP CH (38-54) PAMPERO','PANTALON CARGO RIPSTOP GR (56-60) PAMPERO'] },
  { fam: 'Cargo Cazador',        descs: ['PANTALON CAZ. CARGO II H. PAMPERO AZUL CH (36-54)','PANTALON CAZADOR CARGO II H. PAMPERO CHICO (36-54)','PANTALON CAZ. CARGO II H. PAMPER AZUL GD (56-70)','PANTALON CAZADOR CARGO II H. PAMPERO GRANDE (56-70)'] },
  { fam: 'Bombacha lisa',        descs: ['BOMBACHA LISA MUJER PAMPERO','BOMBACHA LISA HOMBRE PAMPERO (38-54)','BOMBACHA LISA H. PAMPERO AZUL (38-54)','BOMBACHA LISA HOMBRE PAMPERO (56-60)','BOMBACHA LISA H.PAMPERO AZUL (56-60)','BOMBACHA LISA NIÑO PAMPERO'] },
  { fam: 'Cargo elastizado fit', descs: ['PANTALON CARGO ELASTIZADO PAMPERO FIT'] },
  { fam: 'Pantalón de trabajo',  descs: ['PANTALON DE TRAB. H. PAMPERO AZUL CH(36-60)','PANTALON DE TRABAJO HOMBRE PAMPERO CH(36-60)'] },
  { fam: 'Camisa de trabajo',    descs: ['CAMISA DE TRAB H.M/L PAMPERO AZUL CH(38-48)','CAMISA DE TRAB H.M/L PAMPERO AZUL G(58-70)','CAMISA DE TRAB H.M/L PAMPERO AZUL M(50-56)','CAMISA DE TRABAJO H. M/L PAMPERO CH (36-48)','CAMISA DE TRABAJO H.M/L PAMPERO GRANDE(58-70)','CAMISA DE TRABAJO H.M/L PAMPERO MED.(50-56)'] }
];
var _descToFam = {};
FAM_DESC_MAP.forEach(function(entry) {
  entry.descs.forEach(function(d) { _descToFam[d] = entry.fam; });
});

function normCol(s) { return (s||'').toLowerCase().normalize('NFD').replace(/[̀-ͯ]/g,''); }

function loadStockFromSheets() {
  var container = document.getElementById('stock-list');
  container.innerHTML = '<p style="padding:16px;color:#94a3b8">Cargando stock desde Google Sheets…</p>';
  var cb = '__gviz_sr_' + Date.now();
  var script = document.createElement('script');
  var timer = setTimeout(function() {
    delete window[cb]; script.remove();
    container.innerHTML = '<p style="padding:16px;color:#dc2626">Timeout al cargar stock desde Sheets.</p>';
  }, 10000);
  window[cb] = function(data) {
    clearTimeout(timer); delete window[cb]; script.remove();
    try { applyStockGviz(data); }
    catch(e) { container.innerHTML = '<p style="padding:16px;color:#dc2626">Error: ' + esc(e.message) + '</p>'; }
  };
  script.onerror = function() {
    clearTimeout(timer); delete window[cb];
    container.innerHTML = '<p style="padding:16px;color:#dc2626">Error al cargar Sheets.</p>';
  };
  script.src = 'https://docs.google.com/spreadsheets/d/' + SHEETS_ID_STOCK +
    '/gviz/tq?tqx=out:json;responseHandler:' + cb + '&gid=' + SHEETS_GID_STOCK;
  document.head.appendChild(script);
}

function applyStockGviz(data) {
  if (data.status === 'error') throw new Error('Sheets: ' + (data.errors||[]).map(function(e){return e.message;}).join(', '));
  var allRows = data.table.rows || [];
  if (!allRows.length) throw new Error('Hoja vacía');
  var KNOWN = ['articulo descripcion','color descripcion','talle descripcion','articulo','color','talle','cordoba2','cordoba','grupo'];
  function extractCol(lbl) {
    var n = normCol(lbl);
    for (var i = 0; i < KNOWN.length; i++) { if (n === KNOWN[i] || n.startsWith(KNOWN[i]+' ')) return KNOWN[i]; }
    return null;
  }
  var gvizCols = data.table.cols || [];
  var colLabels = gvizCols.map(function(c){ return (c.label||c.id||'').trim(); });
  var labelMap = {}, dataRows;
  if (colLabels.some(function(l){ return extractCol(l)!==null; })) {
    colLabels.forEach(function(lbl,i){ var k=extractCol(lbl); if(k&&!(k in labelMap)) labelMap[k]=i; });
    dataRows = allRows;
  } else {
    var firstRow = allRows[0];
    var firstVals = (firstRow.c||[]).map(function(c){ return c&&c.v!=null?normCol(String(c.v)):''; });
    if (firstVals.some(function(v){ return extractCol(v)!==null; })) {
      (firstRow.c||[]).forEach(function(cell,i){
        if (cell&&cell.v!=null){ var k=extractCol(String(cell.v))||normCol(String(cell.v)); if(!(k in labelMap)) labelMap[k]=i; }
      });
      dataRows = allRows.slice(1);
    } else {
      ['articulo','articulo descripcion','color','color descripcion','talle','talle descripcion','cordoba2','cordoba'].forEach(function(k,i){ labelMap[k]=i; });
      dataRows = allRows;
    }
  }
  function getCell(row, label) {
    var i = labelMap[normCol(label)];
    if (i===undefined) return null;
    var cell = row.c ? row.c[i] : null;
    return cell ? (cell.v!==undefined ? cell.v : null) : null;
  }
  var stockMap = {}, total = 0;
  dataRows.filter(function(row){ return row&&row.c; }).forEach(function(row){
    var desc = String(getCell(row,'Artículo Descripción')||getCell(row,'articulo descripcion')||'').trim().toUpperCase();
    var fam = _descToFam[desc];
    if (!fam) return;
    var color = String(getCell(row,'Color')||getCell(row,'color')||'').trim();
    var tv = getCell(row,'Talle'); if (tv==null) tv=getCell(row,'talle');
    var talle = String(tv!=null?tv:'').trim();
    var qty = (parseFloat(getCell(row,'CORDOBA'))||0) + (parseFloat(getCell(row,'CORDOBA2'))||0);
    var k = fam+'|'+color+'|'+talle;
    stockMap[k] = (stockMap[k]||0)+qty;
    total += qty;
  });
  renderStockReal(stockMap);
  var kpi = document.getElementById('kpi-stock-fisico');
  if (kpi) kpi.textContent = Math.round(total).toLocaleString('es-AR');
}

function renderStockReal(stockMap) {
  var html = '';
  FAM_DESC_MAP.forEach(function(entry, idx) {
    var fam = entry.fam;
    var famTotal=0, colorSet={}, talleSet={}, lookup={};
    Object.keys(stockMap).forEach(function(k){
      var parts=k.split('|');
      if (parts[0]!==fam) return;
      var color=parts[1], talle=parts[2], qty=stockMap[k];
      colorSet[color]=1; talleSet[talle]=1;
      lookup[color+'|'+talle]=(lookup[color+'|'+talle]||0)+qty;
      famTotal+=qty;
    });
    var gkey='sreal_'+idx;
    html+='<div class="fam-block">';
    html+='<div class="fam-hdr" onclick="toggleFam(\''+gkey+'\')">';
    html+='<span class="fam-title">'+esc(fam)+'</span>';
    html+='<span class="fam-total">'+fmt(Math.round(famTotal))+' uds</span>';
    html+='<span class="fam-arr" id="farr-'+gkey+'">▼</span>';
    html+='</div>';
    html+='<div class="fam-body" id="fbody-'+gkey+'">';
    var colors=Object.keys(colorSet).sort();
    var talles=Object.keys(talleSet).sort(function(a,b){return talleSortKey(a)<talleSortKey(b)?-1:talleSortKey(a)>talleSortKey(b)?1:0;});
    if (!colors.length) {
      html+='<p style="padding:10px;color:#94a3b8;font-size:.82rem">Sin datos para esta familia.</p>';
    } else {
      var tbl='<table class="matrix-table"><thead><tr><th class="col-color">Color</th>';
      talles.forEach(function(t){tbl+='<th>'+esc(t)+'</th>';});
      tbl+='<th class="total-col">Total</th></tr></thead><tbody>';
      var colTotals={}, grandTotal=0;
      talles.forEach(function(t){colTotals[t]=0;});
      colors.forEach(function(color){
        var rowTotal=0;
        var cells=talles.map(function(t){var v=lookup[color+'|'+t]||0;colTotals[t]+=v;rowTotal+=v;return v;});
        grandTotal+=rowTotal;
        tbl+='<tr><td class="color-cell">'+esc(color)+'</td>';
        cells.forEach(function(v){var cls=v>0?'ok':v<0?'neg':'zero';tbl+='<td class="'+cls+'">'+(v!==0?fmt(Math.round(v)):'—')+'</td>';});
        tbl+='<td class="total-col '+(rowTotal>0?'ok':rowTotal<0?'neg':'zero')+'"><strong>'+fmt(Math.round(rowTotal))+'</strong></td></tr>';
      });
      tbl+='<tr class="total-row"><td><strong>TOTAL</strong></td>';
      talles.forEach(function(t){var v=colTotals[t]||0;tbl+='<td><strong>'+(v!==0?fmt(Math.round(v)):'—')+'</strong></td>';});
      tbl+='<td class="total-col"><strong>'+fmt(Math.round(grandTotal))+'</strong></td></tr></tbody></table>';
      html+=tbl;
    }
    html+='</div></div>';
  });
  document.getElementById('stock-list').innerHTML = html||'<p style="padding:16px;color:#94a3b8">Sin datos.</p>';
}

// ── Tabs ──────────────────────────────────────────────────────────────────────
function showTab(name, btn) {
  document.querySelectorAll('.tab-content').forEach(function(t){ t.classList.remove('active'); });
  document.querySelectorAll('.tab-btn').forEach(function(b){ b.classList.remove('active'); });
  document.getElementById('tab-' + name).classList.add('active');
  btn.classList.add('active');
}

// ── Helpers ───────────────────────────────────────────────────────────────────
function esc(s) { return String(s||'').replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;'); }
function fmt(n) { return n == null ? '—' : Number(n).toLocaleString('es-AR'); }
function badge(estado) {
  var cls = estado === 'pendiente' ? 'badge-pendiente' : estado === 'recibido' ? 'badge-recibido' : 'badge-parcial';
  return '<span class="badge ' + cls + '">' + esc(estado) + '</span>';
}
function talleSortKey(t) {
  var n = parseFloat(t);
  return isNaN(n) ? t : String(n).padStart(6, '0');
}

// ── Matriz color × talle ──────────────────────────────────────────────────────
function renderMatriz(famName, valueField) {
  var items = PROY.filter(function(r) { return r.familia === famName; });
  if (!items.length) return '<p style="padding:10px;color:#94a3b8;font-size:.82rem">Sin datos para esta familia.</p>';

  var colorSet = {}, talleSet = {};
  items.forEach(function(r) { colorSet[r.color] = 1; talleSet[r.talle] = 1; });
  var colors = Object.keys(colorSet).sort();
  var talles = Object.keys(talleSet).sort(function(a, b) {
    return talleSortKey(a) < talleSortKey(b) ? -1 : talleSortKey(a) > talleSortKey(b) ? 1 : 0;
  });

  var lookup = {};
  items.forEach(function(r) { lookup[r.color + '|' + r.talle] = r[valueField] || 0; });

  var html = '<table class="matrix-table"><thead><tr>';
  html += '<th class="col-color">Color</th>';
  talles.forEach(function(t) { html += '<th>' + esc(t) + '</th>'; });
  html += '<th class="total-col">Total</th></tr></thead><tbody>';

  var colTotals = {}; talles.forEach(function(t) { colTotals[t] = 0; });
  var grandTotal = 0;

  colors.forEach(function(color) {
    var rowTotal = 0;
    var cells = talles.map(function(t) {
      var v = lookup[color + '|' + t] || 0;
      colTotals[t] += v;
      rowTotal += v;
      return v;
    });
    grandTotal += rowTotal;
    html += '<tr><td class="color-cell">' + esc(color) + '</td>';
    cells.forEach(function(v) {
      var cls = v > 0 ? 'ok' : v < 0 ? 'neg' : 'zero';
      html += '<td class="' + cls + '">' + (v !== 0 ? fmt(v) : '—') + '</td>';
    });
    html += '<td class="total-col ' + (rowTotal > 0 ? 'ok' : rowTotal < 0 ? 'neg' : 'zero') + '">';
    html += '<strong>' + fmt(rowTotal) + '</strong></td></tr>';
  });

  html += '<tr class="total-row"><td><strong>TOTAL</strong></td>';
  talles.forEach(function(t) {
    var v = colTotals[t] || 0;
    html += '<td><strong>' + (v !== 0 ? fmt(v) : '—') + '</strong></td>';
  });
  html += '<td class="total-col"><strong>' + fmt(grandTotal) + '</strong></td></tr>';
  html += '</tbody></table>';
  return html;
}

// ── Renderizar bloques de familia ─────────────────────────────────────────────
function renderFamilias(containerId, valueField) {
  var html = '';
  ORDEN_FAMILIAS.forEach(function(fam, idx) {
    var items = PROY.filter(function(r) { return r.familia === fam; });
    var total = items.reduce(function(s, r) { return s + (r[valueField] || 0); }, 0);
    var gkey  = containerId + '_' + idx;
    html += '<div class="fam-block">';
    html += '<div class="fam-hdr" onclick="toggleFam(\'' + gkey + '\')">';
    html += '<span class="fam-title">' + esc(fam) + '</span>';
    html += '<span class="fam-total">' + fmt(total) + ' uds</span>';
    html += '<span class="fam-arr" id="farr-' + gkey + '">▼</span>';
    html += '</div>';
    html += '<div class="fam-body" id="fbody-' + gkey + '">';
    html += renderMatriz(fam, valueField);
    html += '</div></div>';
  });
  document.getElementById(containerId).innerHTML = html || '<p style="padding:16px;color:#94a3b8">Sin datos.</p>';
}

function toggleFam(id) {
  var body = document.getElementById('fbody-' + id);
  var arr  = document.getElementById('farr-' + id);
  body.classList.toggle('closed');
  if (arr) arr.textContent = body.classList.contains('closed') ? '▶' : '▼';
}

// ── Notas de Pedido ───────────────────────────────────────────────────────────
function renderNotas() {
  var container = document.getElementById('np-list');
  if (!NOTAS.length) { container.innerHTML = '<p style="padding:16px;color:#94a3b8">Sin notas de pedido.</p>'; return; }
  var html = '';
  for (var i = 0; i < NOTAS.length; i++) {
    var np = NOTAS[i];
    var items = np.items || [];
    var totalSol = 0, totalRec = 0;
    for (var j = 0; j < items.length; j++) {
      totalSol += (items[j].cantidad_solicitada || 0);
      totalRec += (items[j].cantidad_recibida  || 0);
    }
    var grpMapNP = {}, grpOrdNP = [];
    for (var j = 0; j < items.length; j++) {
      var it = items[j];
      var d = it.descripcion || '—';
      if (!grpMapNP[d]) { grpMapNP[d] = []; grpOrdNP.push(d); }
      grpMapNP[d].push(it);
    }
    var rowsHtml = '';
    for (var gi = 0; gi < grpOrdNP.length; gi++) {
      var desc   = grpOrdNP[gi];
      var gitems = grpMapNP[desc];
      var gSol   = 0;
      for (var k = 0; k < gitems.length; k++) gSol += (gitems[k].cantidad_solicitada || 0);
      var gkey = 'np' + i + 'g' + gi;
      rowsHtml += '<tr class="grp-item-hdr" onclick="toggleGrp(\'' + gkey + '\')">' +
        '<td colspan="3"><strong>' + esc(desc) + '</strong> <span style="font-weight:400;color:#64748b;font-size:.78rem">· ' + gitems.length + ' talles · ' + gSol + ' uds</span> <span class="grp-arr" id="arr-' + gkey + '">▼</span></td>' +
        '<td style="text-align:right;font-weight:700">' + fmt(gSol) + '</td><td></td><td></td></tr>';
      for (var k = 0; k < gitems.length; k++) {
        var it = gitems[k];
        rowsHtml += '<tr class="grp-row" data-grp="' + gkey + '">' +
          '<td style="padding-left:20px;color:#94a3b8;font-size:.78rem"></td>' +
          '<td>' + esc(it.color) + '</td>' +
          '<td>' + esc(it.talle) + '</td>' +
          '<td style="text-align:right">' + fmt(it.cantidad_solicitada) + '</td>' +
          '<td style="text-align:right">' + (it.cantidad_recibida != null ? fmt(it.cantidad_recibida) : '<span style="color:#cbd5e1">—</span>') + '</td>' +
          '<td style="text-align:right">' + fmt(it.precio_unitario || 0) + '</td></tr>';
      }
    }
    var meta = '';
    if (totalRec) meta += ' · <strong>' + totalRec + '</strong> recibidas';
    if (items.length) meta += ' · ' + items.length + ' renglones';
    var obs = np.observaciones ? '<p style="font-size:.8rem;color:#64748b;margin:8px 0">' + esc(np.observaciones) + '</p>' : '';
    html += '<div class="np-card">' +
      '<div class="np-header" onclick="toggleNP(' + i + ')">' +
        '<div><div class="np-title">' + esc(np.id) + '</div>' +
        '<div class="np-meta">' + esc(np.cliente||'') + ' · ' + esc(np.fecha_emision||'') + '</div></div>' +
        '<div>' + badge(np.estado) + '</div>' +
        '<div class="np-meta" style="margin-left:auto"><strong>' + totalSol + '</strong> uds solicitadas' + meta + '</div>' +
        '<div style="font-size:1.2rem;color:#94a3b8" id="arrow-' + i + '">▼</div>' +
      '</div>' +
      '<div class="np-body" id="npbody-' + i + '">' + obs +
        '<table class="np-table"><thead><tr>' +
          '<th>Descripción</th><th>Color</th><th>Talle</th>' +
          '<th style="text-align:right">Solicitado</th>' +
          '<th style="text-align:right">Recibido</th>' +
          '<th style="text-align:right">Precio U.</th>' +
        '</tr></thead><tbody>' + rowsHtml + '</tbody></table>' +
      '</div></div>';
  }
  container.innerHTML = html;
}

function toggleNP(i) {
  var body  = document.getElementById('npbody-' + i);
  var arrow = document.getElementById('arrow-' + i);
  body.classList.toggle('open');
  arrow.textContent = body.classList.contains('open') ? '▲' : '▼';
}

function toggleGrp(id) {
  document.querySelectorAll('.grp-row[data-grp="' + id + '"]').forEach(function(r){ r.classList.toggle('hidden'); });
  var arr = document.getElementById('arr-' + id);
  if (arr) arr.textContent = arr.textContent.trim() === '▼' ? ' ▲' : ' ▼';
}

// ── Init ──────────────────────────────────────────────────────────────────────
renderNotas();
loadStockFromSheets();
renderFamilias('proy-list',  'proyectado');
</script>
</body>
</html>
'@

# ── Inyectar valores dinámicos ────────────────────────────────────────────────
$html = $template `
    -replace '%%FECHA%%',             $fechaActual `
    -replace '%%TOTAL_STOCK_FISICO%%', $totalStockFisico `
    -replace '%%TOTAL_NP_PENDIENTE%%', $totalNPPendiente `
    -replace '%%TOTAL_PROYECTADO%%',   $totalProyectado `
    -replace '%%NP_ACTIVAS%%',         $npActivasCount `
    -replace '%%NOTAS_JSON%%',         $notasJson `
    -replace '%%PROY_JSON%%',          $proyJson

$html | Out-File -FilePath $OUTPUT -Encoding UTF8
Write-Host "Tablero generado: $OUTPUT"
Write-Host "  Stock fisico: $totalStockFisico uds | En camino: $totalNPPendiente uds | Proyectado: $totalProyectado uds | NPs activas: $npActivasCount"
Start-Process $OUTPUT
