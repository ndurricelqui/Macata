# Actualiza tablero.html con las notas de pedido pendientes actuales
# Ejecutar: powershell -File update-tablero.ps1

$BASE       = 'c:\Users\usuario\Documents\Stock\Macata'
$NP_DIR     = "$BASE\data\notas_pedido"
$TABLERO    = "$BASE\tablero.html"   # Nota: NO usar $html como nombre, colisiona con $HTML en PS

# ---- Leer notas pendientes ----
$notasArr = @()
Get-ChildItem $NP_DIR -Filter '*.json' | Where-Object { $_.Name -ne '_indice.json' } |
    Sort-Object Name | ForEach-Object {
    $nota = Get-Content $_.FullName -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($nota.estado -in @('pendiente','recibida_parcial')) { $notasArr += $nota }
}

$notasJson = if ($notasArr.Count -eq 0) { '[]' }
             elseif ($notasArr.Count -eq 1) { '[' + ($notasArr | ConvertTo-Json -Depth 10 -Compress) + ']' }
             else { $notasArr | ConvertTo-Json -Depth 10 -Compress }

$totalUds = 0
$notasArr | ForEach-Object {
    $totalUds += ($_.items | ForEach-Object { $_.cantidad_solicitada } | Measure-Object -Sum).Sum
}

# ---- Parchear tablero.html ----
$contenido = Get-Content $TABLERO -Raw -Encoding UTF8

# Reemplazar var NOTAS
$contenido = [regex]::Replace($contenido, 'var NOTAS = \[.*?\];', "var NOTAS = $notasJson;")

# Reemplazar KPI "En camino"
$totalFmt = $totalUds.ToString('N0').Replace(',','.')
$contenido = [regex]::Replace($contenido,
    '(<div class="label">En camino \(NPs pendientes\)</div>\s*<div class="value">)[^<]*(</div>)',
    ('${1}' + $totalFmt + '${2}'))

# Reemplazar KPI "NPs activas"
$contenido = [regex]::Replace($contenido,
    '(<div class="label">NPs activas</div>\s*<div class="value">)[^<]*(</div>)',
    ('${1}' + $notasArr.Count + '${2}'))

# Escribir resultado
$sw = New-Object System.IO.StreamWriter($TABLERO, $false, [System.Text.Encoding]::UTF8)
$sw.Write($contenido)
$sw.Close()

Write-Host "tablero.html actualizado: $($notasArr.Count) notas, $totalUds uds en camino"