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

## Cuidado con

- `settings.local.json` contiene credenciales de App Store Connect — **nunca commitear**
- Los tests requieren simulador real: correr `xcodebuild` con destino correcto
- CloudKit en desarrollo requiere entitlements firmados — build directo en simulador puede fallar el sync
- `match` gestiona los certificados desde un repo privado de GitHub — no regenerar manualmente
