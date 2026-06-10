# Sistema de Gestión de Stock — Macata

## Skills disponibles

| Comando              | Descripción                                                  |
|----------------------|--------------------------------------------------------------|
| `/stock-cargar`      | Carga el stock desde un archivo Excel o CSV                  |
| `/stock-nota-pedido` | Registra una nota de pedido a proveedor (con foto opcional)  |
| `/stock-pedido`      | Registra un pedido de cliente y verifica disponibilidad      |
| `/stock-reconciliar` | Confronta mercadería recibida contra la nota de pedido       |
| `/stock-estado`      | Muestra el panel de estado general del sistema               |

## Flujo de trabajo

```
1. CARGA INICIAL
   /stock-cargar → Ingresá tu Excel de inventario actual

2. CUANDO HACÉS UN PEDIDO A PROVEEDOR
   /stock-nota-pedido → Cargá la nota/OC (podés sacar una foto)

3. CUANDO RECIBÍS UN PEDIDO DE CLIENTE
   /stock-pedido → Registrá qué necesita el cliente
                 → Verifica si hay stock disponible

4. CUANDO LLEGA MERCADERÍA DEL PROVEEDOR
   /stock-reconciliar → Confrontá lo recibido vs lo pedido
                      → Actualiza el stock automáticamente

5. ESTADO GENERAL
   /stock-estado → Ver resumen de todo el sistema
```

## Estructura de archivos

```
Macata/
├── data/
│   ├── stock.json              ← Inventario actual
│   ├── notas_pedido/
│   │   ├── _indice.json        ← Índice de todas las notas
│   │   └── NP-YYYYMMDD-NNN.json
│   └── pedidos/
│       ├── _indice.json        ← Índice de todos los pedidos
│       └── PED-YYYYMMDD-NNN.json
├── reportes/                   ← Reportes de recepción generados
└── .claude/commands/           ← Skills de Claude Code
```

## Lógica de stock comprometido

La mercadería siempre tiene prioridad hacia los pedidos de clientes:

| Campo | Significado |
|---|---|
| `cantidad` | Stock físico total en depósito |
| `comprometido` | Reservado para pedidos de clientes pendientes |
| `disponible` | `cantidad - comprometido` → libre para nuevos pedidos |

Cuando llega mercadería (`/stock-reconciliar`):
1. Se asigna primero a cubrir pedidos de clientes con `cantidad_pendiente_ingreso > 0` (orden: urgentes → fecha más próxima)
2. El sobrante recién queda como stock libre (`disponible`)

Un pedido de cliente nunca compite con el stock general — lo que está comprometido está separado.

## Formato del Excel de stock

El Excel puede tener cualquier nombre de columna. Al cargarlo, Claude identificará automáticamente:
- Código/SKU del producto
- Descripción
- Cantidad en stock
- Unidad de medida
- Precio unitario (opcional)
- Depósito/Ubicación (opcional)
- Categoría (opcional)

Se recomienda guardarlo como **CSV UTF-8** para mejor compatibilidad.
