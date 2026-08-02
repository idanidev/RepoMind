# RepoMind — Mejoras de diseño Mac

Plan de rediseño Mac Catalyst. Estado: pendiente. Orden sugerido: fase 1 (base) → fase 2 (polish visual) → fase 3 (interactivo).

---

## Fase 1 — Base Mac (sidebar, toolbar, tipografía)

### 1. Sidebar nativo macOS
- `.listStyle(.sidebar)` en lugar de `.insetGrouped`
- Iconos SF Symbols pequeños alineados izquierda (Todos / Favoritos / Archivados)
- Background `.ultraThinMaterial` traslúcido detrás sidebar

### 2. Toolbar Mac-first
- Toolbar items con `.primaryAction` / `.confirmationAction` (no `.topBarTrailing`)
- Botones con texto + icono (`labelStyle(.titleAndIcon)`) — Mac users esperan labels
- Search field nativo `.searchable(placement: .toolbar)` arriba derecha
- Title centrado tipo Finder

### 5. Densidad y tipografía
- Headers más pequeños (`.title3` en vez `.title`)
- Body `.callout` (13pt) en lugar `.subheadline` (15pt)
- Monospaced numbers en counters (`.monospacedDigit()`)

---

## Fase 2 — Polish visual

### 6. Liquid Glass auténtico
- `KanbanColumnView` headers con `.ultraThinMaterial` + bordes 0.5pt
- Inspectors panel (cmd+opt+0) lateral derecho para detalle de tarea en lugar de sheet modal

### 9. Context menus completos
- Right-click en repo → Open / Favorite / Archive / Delete / Copy URL / Reveal in GitHub
- Right-click en task → Move to → [columnas]

### 10. Paywall Mac
- Layout 2-column horizontal (features izq, precio der)
- Window size fijo no sheet

### 11. Onboarding Mac
- Pantalla split: izquierda gradient + logo, derecha login form

---

## Fase 3 — Interactivo

### 3. Espaciado generoso
- `minWidth: 1200` ventana inicial (actual 900)
- `padding(.horizontal, 24)` en columnas Kanban (actual ~12)
- Cards con `cornerRadius: 10` (actual 16), `shadow(.small)` en hover

### 4. Hover states
- `.onHover { ... }` en cards/repos: leve background highlight + cursor pointing
- Modifier custom `.hoverable()` para reuso

### 7. Menu Bar commands enriquecidos
- File → New Repo / New Task / New Column (cmd+N variantes)
- View → Toggle Sidebar (cmd+0), Switch Board/List (cmd+1/2)
- Window → tamaños predefinidos

### 8. Drag & Drop visual
- Indicadores drop con animación spring
- Insertion line entre columnas/cards estilo Trello desktop
