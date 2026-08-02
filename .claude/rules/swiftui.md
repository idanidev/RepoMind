---
paths:
  - "RepoMind/**/*.swift"
  - "RepoMind/Components/**/*.swift"
---

# Reglas SwiftUI — RepoMind

## Estado y datos
- Usar `@State` solo para estado local de la vista
- `@Environment(\.modelContext)` para acceso a SwiftData
- `@Query` para consultas reactivas a SwiftData
- No pasar `ModelContext` como parámetro — usar `@Environment`
- El único ViewModel del proyecto es `KanbanViewModel` — no crear nuevos salvo necesidad justificada

## Composición de vistas
- Extraer subvistas cuando una vista supere ~100 líneas
- Preferir `ViewBuilder` sobre condicionales complejos inline
- Usar `Group` para aplicar modificadores a múltiples vistas
- Nombres de vistas en PascalCase con sufijo `View` (ej: `TaskCardView`)

## Navegación
- Usar `NavigationStack` (no `NavigationView`)
- Pasar solo los datos necesarios a cada vista hija, no el ViewModel completo

## Rendimiento
- `LazyVStack` / `LazyHStack` para listas largas
- `.id()` solo cuando sea estrictamente necesario para forzar redraw
- Evitar cálculos pesados dentro del body — moverlos a computed properties o al ViewModel

## Concurrencia
- `async/await` con `.task {}` para cargas de datos al aparecer una vista
- No usar `DispatchQueue.main.async` — usar `@MainActor` o `await MainActor.run`
- Marcar funciones que actualizan UI con `@MainActor`

## Mac Catalyst
- Envolver APIs exclusivos de iOS en `#if !targetEnvironment(macCatalyst)`
- Comprobar disponibilidad con `#available(macCatalyst 17, *)` cuando aplique
- Usar `.toolbar` posicionado correctamente para macOS (`.primaryAction`, `.confirmationAction`)
