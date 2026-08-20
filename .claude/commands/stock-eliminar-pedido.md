# Stock Eliminar Pedido — Elimina una nota de pedido

Este skill elimina una nota de pedido del sistema a partir de su número.

## Instrucciones

El número de pedido viene en `$ARGUMENTS` (ej: `37433`). Extraé solo los dígitos.

### Paso 1 — Localizar el archivo

Buscá en `c:\Users\usuario\Documents\Stock\Macata\data\notas_pedido\` un archivo cuyo nombre contenga el número de pedido.

Formato esperado: `Pedido #NNNNN - DD.MM.AA.json`

Si no existe ningún archivo con ese número → informá al usuario y terminá.

### Paso 2 — Eliminar el archivo

Eliminá el archivo JSON correspondiente.

### Paso 4 — Actualizar el índice

Leé `c:\Users\usuario\Documents\Stock\Macata\data\notas_pedido\_indice.json`, remové la entrada cuyo `id` corresponde a la nota eliminada, y guardá el índice actualizado.

### Paso 5 — Confirmación final

Informá:
- Qué nota fue eliminada
- Cuántas notas quedan en el índice

### Paso 6 — Actualizar tablero.html

Ejecutá este comando para actualizar el tablero automáticamente:

```
powershell -File "c:\Users\usuario\Documents\Stock\Macata\update-tablero.ps1"
```

### Paso 7 — Pushear el cambio al repositorio

Subí los cambios al repositorio de GitHub (`https://github.com/ndurricelqui/Macata`) para que la eliminación quede reflejada en todas las PCs:

```
git add -A data/notas_pedido/ tablero-macata-stock-fixed-v2.html index.html
git commit -m "Eliminar nota de pedido #{numero}"
git push
```

Hacé esto sin pedir confirmación. Si el push falla (ej: conflicto con el remoto), avisá al usuario con el error en vez de forzar el push.
