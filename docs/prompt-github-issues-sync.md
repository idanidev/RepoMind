# PROMPT: Sincronización de tareas Kanban → GitHub Issues (RepoMind v1.5)

Copia y pega todo este documento como prompt. Es autocontenido.

---

## Contexto del proyecto

RepoMind es una app iOS 17+ / macOS (Mac Catalyst) en `/Volumes/SSDani/XcodeWorkspace/RepoMind`. Gestiona proyectos GitHub con tableros Kanban por repo, entrada por voz y sync iCloud.

**Stack y convenciones OBLIGATORIAS (leer CLAUDE.md y .claude/rules/ del repo antes de escribir código):**
- SwiftUI puro, Swift 6 strict concurrency, `@MainActor` en ViewModels
- `@Observable` macro — NUNCA `ObservableObject`
- `async/await` — NUNCA Combine ni callbacks
- SwiftData con CloudKit: TODOS los campos de un `@Model` opcionales o con valor por defecto; NUNCA `@Attribute(.unique)`
- Toda string visible → `Localizable.strings` en `en.lproj` Y `es.lproj`, keys snake_case con prefijo de sección
- Vistas no llaman APIs directamente — pasan por servicios o el ViewModel
- `GitHubService.swift` es el único punto de acceso a la GitHub API (extenderlo, no duplicarlo)
- Token GitHub en Keychain vía `KeychainManager` (actor en `SecurityManager.swift`) — `retrieveToken(for: account.tokenKey)`
- SwiftLint activo: sin warnings, sin imports sin usar
- Verificar que compila antes de terminar: `xcodebuild -scheme RepoMind -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.4.1' build`

**Archivos clave existentes:**
- `RepoMind/Models.swift` — `@Model`: `GitHubAccount`, `ProjectRepo`, `KanbanColumn`, `TaskItem`, `FeedbackIssue`
- `RepoMind/ViewModels/KanbanViewModel.swift` — ÚNICO ViewModel; contiene `createTask`, `moveTask`, `deleteTask`, `moveTaskToDoneColumn`, `doneColumn(from:)`
- `RepoMind/GitHubService.swift` — actor con `performRequestWithRetry`, manejo 401 → `GitHubError.invalidToken`
- `RepoMind/FeedbackService.swift` — referencia de estilo: servicio `@MainActor` con URLSession propia (timeouts 15s/30s), PATCH/POST a GitHub Issues API, patrón batch-fetch para evitar N+1
- `RepoMind/KanbanView.swift` — contiene `RepoSettingsSheet` (ajustes por repo) donde irá el toggle
- `RepoMind/RepoMindApp.swift` — Schema de SwiftData: añadir campos nuevos NO requiere migración si son opcionales/default

**Contexto de producto:** ya existe el flujo inverso (issues GitHub con label `user-feedback` → sección Feedback de la app). Esta feature completa el círculo: las tareas del Kanban se publican como issues para que herramientas externas (Claude Code, agentes IA, GitHub web/mobile) las lean y trabajen con ellas.

---

## Objetivo

Cuando el usuario active "Sincronizar tareas con GitHub Issues" en un repo:

1. **Crear tarea** en el Kanban → se crea un issue en el repo GitHub con:
   - Título: primera línea del contenido de la tarea (máx 250 chars)
   - Body: contenido completo + marcador oculto `<!-- repomind-task:<UUID de la tarea> -->`
   - Labels: `repomind-task` + `col:<slug-de-columna>` (ej. `col:pendiente`)
2. **Mover tarea** a otra columna → se reemplaza el label `col:*` por el de la nueva columna
3. **Mover a la última columna** (Hecho/Done, la de mayor `orderIndex`) → además se **cierra** el issue (`state: closed`, `state_reason: completed`)
4. **Sacar tarea de la columna final** → se **reabre** el issue
5. **Editar contenido** de la tarea → se actualiza título y body del issue
6. **Borrar tarea** → se cierra el issue con `state_reason: not_planned` y un comentario "Task deleted in RepoMind"
7. **Desactivar el toggle** → las tareas dejan de sincronizarse; los issues existentes NO se tocan (no borrar nada)

## Modelo de datos

En `Models.swift` (campos opcionales/default por CloudKit):

```swift
// En TaskItem añadir:
var issueNumber: Int?          // número del issue en GitHub, nil = no sincronizada
var needsIssueSync: Bool = false  // pendiente de sincronizar (offline / fallo de red)

// En ProjectRepo añadir:
var syncTasksToGitHub: Bool = false  // toggle de la feature, por repo
```

## Servicio nuevo: `TaskIssueSyncService.swift`

`@MainActor final class TaskIssueSyncService` (singleton `shared`), estilo `FeedbackService`:

```
createIssue(for task: TaskItem, repo: ProjectRepo, token: String) async throws
updateIssueColumn(for task: TaskItem, repo: ProjectRepo, token: String) async throws
closeIssue(for task: TaskItem, repo: ProjectRepo, reason: String, token: String) async throws
reopenIssue(for task: TaskItem, repo: ProjectRepo, token: String) async throws
updateIssueContent(for task: TaskItem, repo: ProjectRepo, token: String) async throws
reconcile(repo: ProjectRepo, context: ModelContext, token: String) async  // ver abajo
ensureLabels(repo: ProjectRepo, columns: [KanbanColumn], token: String) async  // crea labels si faltan
```

Detalles:
- URLSession propia con timeouts (copiar patrón de `FeedbackService`)
- Owner del repo: parsearlo de `repo.htmlURL` (patrón existente en `FeedbackService.parseOwner`)
- Slug de columna: nombre lowercased, espacios→`-`, sin diacríticos, prefijo `col:` (ej. "En progreso" → `col:en-progreso`)
- `ensureLabels`: GET `/labels`, crear las que falten (`repomind-task` color `7C3AED`; `col:*` color `EDEDED`). Llamar al activar el toggle y al crear columna nueva con el toggle activo
- Errores: NUNCA romper la operación local. Si la llamada a GitHub falla, la tarea se guarda igual en SwiftData y se marca `needsIssueSync = true`. El usuario no debe perder trabajo por estar offline

## Reconciliación (`reconcile`)

Se ejecuta al abrir el board de un repo con el toggle activo (en el `.task` de `KanbanView`, tras `initializeViewModel`):

1. Para cada `TaskItem` del repo con `needsIssueSync == true` o (`issueNumber == nil` y toggle activo): intentar crear/actualizar su issue; si OK, limpiar el flag
2. Rate limit friendly: si hay >20 pendientes, procesar 20 y dejar el resto para la próxima apertura
3. No bloquear la UI: fire-and-forget en `Task {}` con `Task.isCancelled` checks

## Puntos de integración en `KanbanViewModel`

Localizar los métodos existentes y añadir el hook DESPUÉS de la mutación local + save (la operación local nunca espera a la red):

- `createTask(...)` → si `project.syncTasksToGitHub`, disparar `createIssue`
- `moveTask(...)` → `updateIssueColumn`; si la columna destino es la final → `closeIssue`; si sale de la final → `reopenIssue`
- `moveTaskToDoneColumn(...)` → `closeIssue`
- `deleteTask(...)` → `closeIssue(reason: not_planned)` — capturar el `issueNumber` ANTES de borrar el objeto
- Edición de tarea (buscar dónde se guarda el `editingTask` en `TaskSheets.swift` / ViewModel) → `updateIssueContent`

Patrón para cada hook (no bloquear, no romper):
```swift
if project.syncTasksToGitHub {
    Task { [weak self] in
        await self?.syncTaskToGitHub(task)  // helper que consigue token y llama al servicio, marca needsIssueSync en fallo
    }
}
```

## UI

En `RepoSettingsSheet` (dentro de `KanbanView.swift`), nueva sección:

- Toggle "sync_tasks_github_toggle" ("Sincronizar tareas con GitHub Issues" / "Sync tasks to GitHub Issues")
- Footer explicativo "sync_tasks_github_footer" ("Cada tarea se publicará como issue en <owner/repo>. Al completarla, el issue se cierra." / EN equivalente)
- Solo visible si `!repo.isLocal` y `repo.account != nil` (repos locales no tienen GitHub)
- Al activarlo: llamar `ensureLabels` + `reconcile` (sincroniza las tareas ya existentes → pedir confirmación con alert si hay más de 10 tareas: "Se crearán N issues en GitHub. ¿Continuar?" key `sync_tasks_confirm_bulk %lld`)
- Indicador discreto en las cards NO — no ensuciar la UI. El estado de sync no se muestra por tarea en v1

## Edge cases (implementar TODOS)

1. **Offline / fallo de red** → `needsIssueSync = true`, reconcile lo arregla después. Local NUNCA falla
2. **Token expirado (401)** → igual que offline + no reintentar en bucle (max 1 intento por operación)
3. **Repo archivado o sin permiso de escritura (403/410)** → desactivar el toggle automáticamente y marcar un flag para mostrar alert la próxima vez que se abra el board ("sync_tasks_disabled_no_permission")
4. **Issue cerrado/borrado manualmente en GitHub** → en reconcile, si un PATCH devuelve 404/410, poner `issueNumber = nil` y recrear solo si la tarea NO está en la columna final
5. **Demo mode** (`isDemoMode` en `AppStorage`) → sync SIEMPRE desactivado, ni mostrar el toggle
6. **Tareas creadas por voz** → mismo flujo que `createTask` (verificar que `createTaskFromVoice` pasa por el hook)
7. **Renombrar columna** con toggle activo → crear el label nuevo; NO migrar issues existentes en v1 (documentar como limitación conocida en un comentario)
8. **Contenido multilínea** → título = primera línea truncada a 250, body = contenido completo
9. **Free tier** → la feature está disponible para TODOS (no gatearlo con `SubscriptionManager`)

## Localización

Añadir TODAS las keys nuevas en `en.lproj/Localizable.strings` Y `es.lproj/Localizable.strings`. Prefijo `sync_tasks_`. Revisar que ninguna string visible quede hardcodeada.

## Criterios de aceptación

1. `xcodebuild build` sin errores ni warnings nuevos de SwiftLint
2. Toggle visible solo en repos GitHub (no locales, no demo)
3. Crear tarea con toggle ON → issue aparece en GitHub con labels correctos en <5s (probar con `gh issue list --repo <owner>/<repo> --label repomind-task`)
4. Mover a Hecho → issue se cierra. Sacar de Hecho → se reabre
5. Borrar tarea → issue cerrado como not_planned con comentario
6. Modo avión: crear/mover/borrar tareas funciona sin errores visibles; al recuperar red y reabrir el board, los issues se ponen al día
7. Tests existentes siguen pasando (los fallos preexistentes en `KanbanTests.testDeleteTask`, `testMoveTask` y `MultiAccountIsolationTests.testDeletingAccountCascadesCorrectly` NO son culpa tuya — no los arregles, no los rompas más)

## Qué NO hacer

- NO usar Combine, ObservableObject, DispatchQueue
- NO añadir `@Attribute(.unique)` ni campos no-opcionales sin default
- NO bloquear ninguna operación local esperando a la red
- NO crear un segundo ViewModel — los hooks van en `KanbanViewModel`
- NO tocar el sistema de Feedback existente (`FeedbackService`, `FeedbackView`) más allá de leerlo como referencia
- NO subir la versión ni tocar fastlane — eso se hace aparte
- NO commitear — deja los cambios en working tree
