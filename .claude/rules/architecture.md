# Arquitectura — RepoMind

## Capas

```
Vista (SwiftUI)  →  ViewModel  →  Service / SwiftData
```

- Las vistas no llaman a APIs directamente — pasan por `GitHubService` o el ViewModel
- `GitHubService` es el único punto de acceso a la GitHub API
- `SubscriptionManager` es la única fuente de verdad para límites del free tier

## Límites del free tier (CRÍTICO)

Antes de añadir cualquier feature que cree entidades, verificar con `SubscriptionManager`:
- Repos visibles: máx **3** en free
- Cuentas GitHub: máx **1** en free
- Columnas Kanban por proyecto: máx **3** en free
- Pro: desbloquea todo (compra única lifetime)

## Modelos SwiftData

- Todos los campos de un `@Model` deben ser opcionales o tener valor por defecto
- Las relaciones deben declararse con `@Relationship` y la política de borrado correcta
- No usar `UUID` como `@Attribute(.unique)` salvo que SwiftData lo soporte en la versión objetivo
- CloudKit sync: los modelos no pueden tener `@Attribute(.unique)` — usar validación manual

## Autenticación

- El token GitHub se almacena en Keychain via `SecurityManager`
- Multi-cuenta: cada cuenta tiene su propio token en Keychain
- Face ID protege el acceso a tokens — no acceder a Keychain sin pasar por `SecurityManager`

## Notificaciones y navegación

- `NotificationCenter` solo para eventos cross-layer (ej: logout forzado por token expirado)
- Deep linking gestionado desde `RepoMindApp` en el `.onOpenURL` modifier
