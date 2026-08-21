# RepoMind

App iOS/macOS de gestión de proyectos GitHub con tableros Kanban, voice-to-text e iCloud sync.
Plataformas: iOS 17+ y macOS via Mac Catalyst. Localización: inglés y español.

## Comandos

```bash
# Build (simulador)
xcodebuild -scheme RepoMind -destination 'platform=iOS Simulator,name=iPhone 16 Pro' build

# Tests
xcodebuild test -scheme RepoMind -destination 'platform=iOS Simulator,name=iPhone 16 Pro'

# Lint
swiftlint lint --config .swiftlint.yml

# Release iOS → TestFlight
bundle exec fastlane ios beta

# Release iOS → App Store
bundle exec fastlane ios release

# Release macOS → App Store
bundle exec fastlane mac release

# Subir screenshots
bundle exec fastlane ios upload_screenshots

# Subir metadata
bundle exec fastlane ios upload_metadata
```

## Arquitectura

- **UI**: SwiftUI puro (sin UIKit salvo Mac Catalyst helpers)
- **Datos**: SwiftData con CloudKit sync automático
- **Auth**: GitHub OAuth → `GitHubService.swift`
- **IAP**: StoreKit 2 → `SubscriptionManager.swift`
- **Biometría**: Face ID → `SecurityManager.swift`
- **Voz**: Speech framework → `VoiceManager.swift`
- **ViewModel**: `KanbanViewModel.swift` (único ViewModel del proyecto)
- **Tareas ↔ Issues**: `TaskIssueSyncService.swift` publica cada tarea como issue de GitHub
- **Salud de iCloud**: `CloudKitSyncMonitor.swift` observa `eventChangedNotification` y desglosa
  los `partialFailure` — sin esto un fallo de sync es indistinguible del éxito
- **Reparación**: `OrphanTaskRepair.swift` reengancha tareas que perdieron su columna
- **Bridge MCP**: `bridge/` (TypeScript) expone las tareas a agentes de código vía GitHub Issues

## Estructura de carpetas

```
RepoMind/
├── Components/        # Vistas reutilizables (Kanban*, TaskCard, VoiceFAB)
├── ViewModels/        # KanbanViewModel.swift
├── Models/            # Modelos SwiftData (@Model)
├── en.lproj/          # Strings inglés
└── es.lproj/          # Strings español
```

## Convenciones

- Usar `async/await` — no Combine, no callbacks
- Toda string visible al usuario → `Localizable.strings` (en + es ambos archivos)
- Free tier: máx 3 repos, 1 cuenta GitHub, 3 columnas Kanban — respetar `SubscriptionManager`
- Modelos `@Model` SwiftData: todos los campos opcionales o con valor por defecto
- Mac Catalyst: comprobar `#if targetEnvironment(macCatalyst)` antes de APIs exclusivos de iOS
- SwiftLint activo: no dejar warnings, no imports sin usar

## Publicar una versión

Seguir este orden. El paso 3 no es opcional: los campos nuevos de un `@Model` no existen en el
CloudKit de Production hasta desplegarlos, y publicar sin hacerlo rompe la sincronización de todos
los usuarios en silencio. Ya pasó una vez y estuvo meses sin detectarse.

1. Tests en verde (`xcodebuild test`) y build de Release limpio
2. `bundle exec fastlane ios bump_version version:X.Y.Z`
3. **Desplegar el esquema de CloudKit**, si se ha tocado cualquier `@Model`:
   1. Ejecutar una build **Debug** (que apunta a Development) con el argumento `-seedCloudKitSchema`.
      El esquema de Development solo nace cuando la app **escribe** un registro de ese tipo.
   2. CloudKit Console → **Development** → comprobar que el tipo/campo nuevo aparece.
   3. Pulsar **"Deploy Schema Changes…"** — solo está activo en Development; en Production
      aparece en gris porque ese entorno es de solo lectura.
   4. Verificar en **Production** que el tipo/campo ya está.
   5. Limpiar los registros de siembra con `-cleanSchemaSeed`.
   En Production un tipo de registro desconocido **se rechaza**, no se crea: publicar sin este
   paso rompe la sincronización de esa entidad para todos los usuarios, en silencio.
4. Escribir `fastlane/metadata/*/release_notes.txt` en **en-US y es-ES**
5. `bundle exec fastlane ios release` y después `submit`
6. **Actualizar este CLAUDE.md**: historial de versiones abajo, y arquitectura/convenciones si el
   release ha añadido servicios o reglas nuevas

## Historial de versiones

- **1.5.0** *(enviada a revisión el 21/08/2026, build 202608211225)* — Onboarding, carpetas de proyectos, sincronización selectiva a issues, reautenticación
  sin cerrar sesión al caducar el token, reparación de tareas huérfanas y diagnóstico real de los
  errores de CloudKit. Modelos nuevos: `RepoFolder`, `TaskItem.lastSyncError`.
- **1.4.2** — Correcciones de sincronización y caché de iconos.

## Cuidado con

- `settings.local.json` contiene credenciales de App Store Connect — **nunca commitear**
- Los tests requieren simulador real: correr `xcodebuild` con destino correcto
- CloudKit en desarrollo requiere entitlements firmados — build directo en simulador puede fallar el sync
- `match` gestiona los certificados desde un repo privado de GitHub — no regenerar manualmente
- **Entitlements separados por configuración**: Debug usa `RepoMindDebug.entitlements`
  (CloudKit `Development`, `aps-environment` `development`) y Release usa `RepoMind.entitlements`
  (`Production`). Durante meses ambos apuntaron a Production: las builds de desarrollo escribían
  en los datos reales, el esquema de Development nunca se actualizaba al probar, y CloudKit
  rechazaba en silencio cada tipo nuevo. `aps-environment` importa igual — CloudKit avisa de los
  cambios por push silencioso, y una build de desarrollo que declara `production` no los recibe.
