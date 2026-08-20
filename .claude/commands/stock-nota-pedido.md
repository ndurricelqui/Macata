# Stock Nota de Pedido — Carga una nota de pedido

Este skill registra una nota de pedido al proveedor a partir de texto pegado o ingreso manual.

## Instrucciones

El usuario quiere registrar una nota de pedido (orden de compra a proveedor).

### Paso 1 — Determinar el modo de carga

Revisá `$ARGUMENTS`:
- Si contiene líneas con `×` o `Total unidades` → ir a **Modo Texto**
- Si no → ir a **Modo Manual**

---

## Modo Texto (texto pegado del pedido)

Usá este modo cuando el usuario pegó el contenido del pedido como texto. Formato esperado:

```
Producto    Unidades
Nombre producto - Color, Talle
Color: ...
Talle: ...
× N
...
Total unidades N
```

### Paso T0 — Extraer encabezado

Antes de procesar los ítems, buscá en el texto una línea con el número y fecha del pedido. Ejemplo:
```
El pedido #37433 se realizó el 26 marzo, 2026 y está actualmente Esperando para Armar.
```
- `numero_pedido`: el número tras `#` (ej: `37433`)
- `fecha_emision`: la fecha en formato `DD.MM.AA` (ej: `26.03.26`)
- El estado ("Esperando para Armar", etc.) **ignorarlo**.

Si no aparece esta línea, pedí al usuario el número de pedido y la fecha antes de continuar.

### Paso T1 — Extraer bloques

Por cada bloque (agrupado por artículo), extraé:
- `descripcion`: parte antes del primer ` - ` en la línea de nombre (ej: `"Cargo ripstop PAMPERO"`)
- `color`: valor en línea `Color:`, o tras el ` - ` en el nombre si no hay línea explícita
- `talle`: valor en línea `Talle:`, o del nombre si no hay línea explícita
- `cantidad_solicitada`: número después de `×`

**Reglas:**
- No inventés campos ausentes en el texto.
- Si `color` o `talle` no se pueden determinar, usá `null`.

### Paso T2 — Validar total

Si el texto incluye `Total unidades N`:
- Sumá todas las `cantidad_solicitada`.
- Si la suma ≠ N → mostrá la discrepancia y **no guardes** hasta que el usuario confirme o corrija.
- Si coincide → continuá.

### Paso T3 — Guardar directamente

Guardá directamente sin pedir confirmación. Si el total coincide, procedé al Paso Final de inmediato.

---

## Modo Manual (sin imagen)

### Paso M1 — Solicitar datos del encabezado

Pedí al usuario los siguientes datos (podés hacerlo en un solo mensaje listando todo):

```
📋 DATOS DE LA NOTA DE PEDIDO

- Número de nota/OC:
- Fecha de emisión: (DD/MM/AAAA)
- Proveedor:
- CUIT del proveedor: (opcional)
- Condición de pago: (contado / 30 días / etc.)
- Fecha de entrega esperada: (DD/MM/AAAA)
- Depósito/destino:
- Observaciones: (opcional)
```

### Paso M2 — Solicitar detalle de artículos

Pedí al usuario que liste los artículos. Sugerí este formato:
```
Código | Descripción | Cantidad | Unidad | Precio Unit.
```
O bien ingresarlos uno por uno.

---

## Paso Final — Guardar la nota de pedido

### Generar ID

Armá el ID con el número de pedido y la fecha extraídos en T0:
- Formato: `Pedido #NNNNN - DD.MM.AA`
- Ejemplo: `Pedido #37433 - 26.03.26`

### Guardar JSON de la nota

Guardá el archivo en:
`c:\Users\usuario\Documents\Stock\Macata\data\notas_pedido\{ID}.json`

Con este formato:
```json
{
  "id": "Pedido #37433 - 26.03.26",
  "numero_pedido": "37433",
  "fecha_emision": "2026-03-26",
  "proveedor": {
    "nombre": "...",
    "cuit": "..."
  },
  "estado": "pendiente",
  "items": [
    {
      "codigo": null,
      "descripcion": "...",
      "color": "...",
      "talle": "...",
      "cantidad_solicitada": 0,
    }
  ],
  "totales": {
    "subtotal": 0,
    "iva": 0,
    "total": 0
  },
  "creado_en": "FECHA_ISO_AHORA"
}
```

### Actualizar índice

Leé el archivo `c:\Users\usuario\Documents\Stock\Macata\data\notas_pedido\_indice.json` (creálo si no existe) y agregá esta nota:

```json
{
  "notas": [
    {
      "id": "Pedido #37433 - 26.03.26",
      "proveedor": "...",
      "fecha_emision": "...",
      "fecha_entrega_esperada": "...",
      "total": 0,
      "estado": "pendiente"
    }
  ]
}
```

### Confirmación final

Mostrá al usuario:
- ID asignado a la nota
- Resumen de la nota (proveedor, fecha, total, cantidad de artículos)
- Ruta donde fue guardada
- Estado: **pendiente** (aún no recibida)

Indicá que cuando llegue la mercadería, puede usar `/stock-reconciliar` para confrontar lo recibido con esta nota.

---

## Paso Tablero — Actualizar tablero.html

Después de guardar la nota, ejecutá este comando para actualizar el tablero automáticamente:

```
powershell -ExecutionPolicy Bypass -File "c:\Users\usuario\Documents\Stock\Macata\update-tablero.ps1"
```

Esto inyecta las notas actualizadas en `tablero-macata-stock-fixed-v2.html` e `index.html` (la pestaña "Notas de Pedido") y actualiza los contadores del encabezado.

---

## Paso Git — Pushear la nota al repositorio

Después de actualizar el tablero, subí los cambios al repositorio de GitHub (`https://github.com/ndurricelqui/Macata`) para que la nota quede disponible en todas las PCs:

```
git add data/notas_pedido/ tablero-macata-stock-fixed-v2.html index.html
git commit -m "Agregar nota de pedido {ID}"
git push
```

Hacé esto sin pedir confirmación. Si el push falla (ej: conflicto con el remoto), avisá al usuario con el error en vez de forzar el push.

---

## Paso Resumen — Tabla consolidada de stock pedido

Después de la confirmación, leé todos los archivos JSON de notas en `c:\Users\usuario\Documents\Stock\Macata\data\notas_pedido\` (excluyendo `_indice.json`) cuyo estado sea `"pendiente"` o `"recibida_parcial"`.

### Construir la tabla

Consolidá todos los ítems de todas esas notas en una sola estructura:
- Clave: `descripcion` (normalizada: quitá el sufijo ` (t. XX-XX)` para unificar gamas del mismo producto) + `color`
- Acumulá `cantidad_solicitada` por talle

Determinar columnas de talles:
- Reuní todos los talles distintos que aparezcan en los datos
- Ordenalos numéricamente de menor a mayor
- Estos son las columnas de la tabla

### Formato de la tabla

```
STOCK PEDIDO CONSOLIDADO (notas pendientes)
──────────────────────────────────────────────────────────────────────────────
PRODUCTO                    | COLOR       | 36 | 38 | 40 | 42 | 44 | ... | TOTAL
──────────────────────────────────────────────────────────────────────────────
Cargo cazador PAMPERO       | Azul marino |    |    |  3 |  8 | 10 | ... |    XX
                            | Beige       |    |    |  5 | 10 |    | ... |    XX
                            | Negro       |    |  3 |  3 |  5 | 10 | ... |    XX
                            | Verde       |    |    |    |  5 | 10 | ... |    XX
Cargo ripstop PAMPERO       | Azul marino |  2 |  5 |    | 15 | 10 | ... |    XX
...
──────────────────────────────────────────────────────────────────────────────
TOTAL GENERAL               |             | XX | XX | XX | XX | XX | ... |   XXX
```

**Reglas:**
- Las columnas de talles son dinámicas: reuní todos los talles distintos que aparezcan en los datos y ordenalos numéricamente de menor a mayor.
- Si un talle no aplica a esa fila, dejá la celda vacía (no poner 0).
- La fila `TOTAL GENERAL` suma todas las cantidades por talle y el total absoluto.
- Ordená los productos alfabéticamente, y los colores alfabéticamente dentro de cada producto.
- **Normalización de colores:** mostrá los colores en Title Case (primera letra mayúscula, resto minúscula). Ejemplo: `AZUL MARINO` → `Azul marino`, `NEGRO` → `Negro`, `BEIGE` → `Beige`.
- Mostrá también cuántas notas de pedido están incluidas en el resumen (ej: "Incluye 5 notas pendientes").
- Si no hay notas pendientes, omitir esta sección.
