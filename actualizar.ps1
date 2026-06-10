# actualizar.ps1 — Actualiza stock.json y parchea tablero.html desde Google Sheets

$BASE          = Split-Path -Parent $MyInvocation.MyCommand.Path
$SHEETS_URL    = "https://docs.google.com/spreadsheets/d/1P7nx8LWnT9eb4VoIAAIMtlC58qHjaedGYGborsjU1uI/export?format=csv&gid=1493271108"
$NP_DIR        = Join-Path $BASE "data\notas_pedido"
$MAPEO_FILE    = Join-Path $BASE "data\mapeo_descripciones.json"
$FAMILIAS_FILE = Join-Path $BASE "data\familias.json"
$STOCK_JSON    = Join-Path $BASE "data\stock.json"
$TABLERO       = Join-Path $BASE "tablero.html"

# ── 1. Descargar desde Google Sheets ──────────────────────────────────────────
$response = Invoke-WebRequest -Uri $SHEETS_URL -UseBasicParsing
$csvRows  = $response.Content | ConvertFrom-Csv | Where-Object { $_.'Artículo' -match '\S' }

# ── 2. Leer mapeo y familias ───────────────────────────────────────────────────
$mapeo    = Get-Content $MAPEO_FILE    -Raw -Encoding UTF8 | ConvertFrom-Json
$familias = Get-Content $FAMILIAS_FILE -Raw -Encoding UTF8 | ConvertFrom-Json

$reverseMapeo = @{}
foreach ($prop in $mapeo.PSObject.Properties) {
    foreach ($csvDesc in @($prop.Value)) { $reverseMapeo[$csvDesc] = $prop.Name }
}

$familiaMap = @{}
foreach ($prop in $familias.PSObject.Properties) {
    foreach ($cod in @($prop.Value)) { $familiaMap[$cod] = $prop.Name }
}

# ── 3. Detectar columnas ───────────────────────────────────────────────────────
$sampleRow    = $csvRows | Select-Object -First 1
$colNames     = $sampleRow.PSObject.Properties.Name
$colCodigo    = $colNames | Where-Object { $_ -match '^Art' -and $_ -notmatch 'desc' } | Select-Object -First 1
$colDesc      = $colNames | Where-Object { $_ -match 'desc' -and $_ -notmatch 'Color' } | Select-Object -First 1
$colColorD    = $colNames | Where-Object { $_ -match 'Color' -and $_ -match 'desc' } | Select-Object -First 1
$fixedCols    = @('Grupo','Artículo','Artículo Descripción','Color','Color Descripción','Talle','Talle Descripción')
$locationCols = $colNames | Where-Object { $_ -notin $fixedCols -and $_ -ne '' }

# ── 4. Construir productos ─────────────────────────────────────────────────────
$productos = $csvRows | ForEach-Object {
    $row  = $_
    $desc = $row.$colDesc.Trim()
    $cod  = $row.$colCodigo.Trim()
    $qty  = ($locationCols | ForEach-Object {
        $v = ($row.$_ -replace '[^\d,\.\-]','').Trim() -replace ',','.'
        if ($v -match '^\-?\d') { [double]$v } else { 0 }
    } | Measure-Object -Sum).Sum
    [pscustomobject]@{
        codigo          = $cod
        descripcion     = $desc
        descripcion_np  = if ($desc -and $reverseMapeo.ContainsKey($desc)) { $reverseMapeo[$desc] } else { $null }
        familia         = if ($cod  -and $familiaMap.ContainsKey($cod))  { $familiaMap[$cod]    } else { $null }
        cantidad        = $qty
        comprometido    = 0
        disponible      = $qty
        unidad          = $null
        precio_unitario = $null
        ubicacion       = $null
        categoria       = $null
        color_codigo    = $row.Color.Trim()
        color           = $row.$colColorD.Trim()
        talle           = $row.Talle.Trim()
    }
}

# ── 5. Guardar stock.json ──────────────────────────────────────────────────────
$stockData = [pscustomobject]@{
    ultima_actualizacion = (Get-Date -Format "yyyy-MM-ddTHH:mm:ss")
    archivo_fuente       = "Google Sheets"
    proveedor            = "MACATA"
    productos            = $productos
}
$stockData | ConvertTo-Json -Depth 5 | Out-File -FilePath $STOCK_JSON -Encoding UTF8
$sinMapear = @($productos | Where-Object { $null -eq $_.descripcion_np })
Write-Host "stock.json: $($productos.Count) productos ($($sinMapear.Count) sin mapear)"

# ── 6. Leer notas de pedido ────────────────────────────────────────────────────
$notasArr = @()
Get-ChildItem "$NP_DIR\*.json" | Where-Object { $_.Name -ne '_indice.json' } | ForEach-Object {
    $np = Get-Content $_.FullName -Raw | ConvertFrom-Json
    if ($np.estado -in @('pendiente','recibida_parcial')) { $notasArr += $np }
}
$notasArr = $notasArr | Sort-Object fecha_emision

# ── 7. Construir PROY simplificado {familia, color, talle, real} ──────────────
$proyMap = @{}
foreach ($p in $productos) {
    if (-not $p.familia) { continue }
    $key = "$($p.familia)|$($p.color)|$($p.talle)"
    if ($proyMap.ContainsKey($key)) { $proyMap[$key] += $p.cantidad }
    else { $proyMap[$key] = $p.cantidad }
}
$proyArray = @($proyMap.GetEnumerator() | ForEach-Object {
    $parts = $_.Key -split '\|'
    [pscustomobject]@{ familia=$parts[0]; color=$parts[1]; talle=$parts[2]; real=$_.Value }
} | Sort-Object familia, color, talle)

# ── 8. Serializar JSON ─────────────────────────────────────────────────────────
$fechaActual = (Get-Date -Format "yyyy-MM-ddTHH:mm:ss")

$notasJson = if ($notasArr.Count -eq 0) { '[]' }
             elseif ($notasArr.Count -eq 1) { '[' + ($notasArr[0] | ConvertTo-Json -Depth 10 -Compress) + ']' }
             else { $notasArr | ConvertTo-Json -Depth 10 -Compress }

$proyJson  = if ($proyArray.Count -eq 0) { '[]' }
             elseif ($proyArray.Count -eq 1) { '[' + ($proyArray[0] | ConvertTo-Json -Depth 3 -Compress) + ']' }
             else { $proyArray | ConvertTo-Json -Depth 3 -Compress }

$totalStockFisico = [int]($productos | Measure-Object cantidad -Sum).Sum
$totalNPPedido    = [int](($notasArr | ForEach-Object {
    ($_.items | ForEach-Object { $_.cantidad_solicitada } | Measure-Object -Sum).Sum
}) | Measure-Object -Sum).Sum
$npActivas        = $notasArr.Count
$totalProy        = $totalStockFisico + $totalNPPedido

# ── 9. Parchar tablero.html ────────────────────────────────────────────────────
$contenido = Get-Content $TABLERO -Raw -Encoding UTF8

$contenido = [regex]::Replace($contenido,
    'Stock al: [^<]+</span>',
    "Stock al: $fechaActual</span>")

$contenido = [regex]::Replace($contenido,
    'var NOTAS = \[.*?\];',
    "var NOTAS = $notasJson;")

$contenido = [regex]::Replace($contenido,
    'var PROY = \[.*?\];',
    "var PROY = $proyJson;")

$enCaminoFmt = $totalNPPedido.ToString('N0').Replace(',','.')
$proyFmt     = $totalProy.ToString('N0').Replace(',','.')

$contenido = [regex]::Replace($contenido,
    '(?<=id="kpi-en-camino">)[^<]*', $enCaminoFmt)
$contenido = [regex]::Replace($contenido,
    '(?<=id="kpi-np-activas">)[^<]*', $npActivas)
$contenido = [regex]::Replace($contenido,
    '(?<=id="kpi-proy">)[^<]*', $proyFmt)

$sw = New-Object System.IO.StreamWriter($TABLERO, $false, [System.Text.Encoding]::UTF8)
$sw.Write($contenido)
$sw.Close()

Write-Host "tablero.html actualizado: $npActivas NPs | Stock: $totalStockFisico | En camino: $totalNPPedido | Proy: $totalProy"
Start-Process $TABLERO