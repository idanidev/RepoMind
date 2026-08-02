---
paths:
  - "RepoMind/**/*.swift"
  - "RepoMind/en.lproj/*"
  - "RepoMind/es.lproj/*"
---

# Localización — RepoMind

## Regla fundamental

**Toda string visible al usuario debe estar localizada.** Sin excepciones.

## Cómo añadir una string nueva

1. Usar `String(localized: "key")` o `Text("key")` en SwiftUI
2. Añadir la entrada en `RepoMind/en.lproj/Localizable.strings`
3. Añadir la traducción en `RepoMind/es.lproj/Localizable.strings`
4. Ambos archivos deben mantenerse sincronizados — si añades una key en uno, añádela en el otro

## Formato de keys

- Snake_case descriptivo: `kanban_add_column_button`, `repo_list_empty_state`
- Prefijo por sección: `kanban_`, `repo_`, `settings_`, `paywall_`, `login_`, `voice_`
- No usar la string en inglés como key (evita `"Add column"` como key)

## Interpolación

```swift
// Correcto
String(localized: "kanban_column_task_count \(count)")

// En Localizable.strings
"kanban_column_task_count %lld" = "%lld tasks";  // en
"kanban_column_task_count %lld" = "%lld tareas"; // es
```

## No localizar

- Nombres de repos (vienen de GitHub)
- Fechas — usar `Date.formatted()` con `.locale(Locale.current)`
- Nombres de usuario GitHub
- Logs de debug
