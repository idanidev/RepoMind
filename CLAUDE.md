# RepoMind

App iOS/macOS de gestión de proyectos GitHub con tableros Kanban, voice-to-text e iCloud sync.
Plataformas: iOS 17+ y macOS via Mac Catalyst. Localización: inglés y español. La interfaz nueva (Inicio,
Tareas, tablero por columnas, captura) es de iPhone; iPad y Mac siguen con la clásica (`KanbanView`,
`AdaptiveRepoListView`).

## Comandos

```bash
# Build (simulador; el nombre ha de existir: `xcrun simctl list devices available`)
xcodebuild -scheme RepoMind -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build

# Tests
xcodebuild test -scheme RepoMind -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:RepoMindTests

# Comprobaciones que no necesitan Mac (las mismas que checks.yml)
pip install -r scripts/checks/requirements.txt
python3 scripts/checks/strings.py && python3 scripts/checks/viewbuilder_arity.py

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

Sin Mac, casi lo mismo desde GitHub Actions (`.github/workflows`), con los secretos `ASC_KEY_ID`,
`ASC_ISSUER_ID` y `ASC_KEY_P8` (clave de rol Admin de la API de App Store Connect) y, para firmar,
`MATCH_GIT_URL`, `MATCH_GIT_TOKEN` (token de GitHub con lectura del repo de certificados) y
`MATCH_PASSWORD`. No tienen workflow: subir screenshots, los lanes `mac *` y `certificates`, y la siembra
del esquema de CloudKit. Un minuto de runner macOS gasta diez de la cuota gratuita y uno de Linux gasta
uno, así que lo que puede ir en Linux va en Linux, y los de macOS solo arrancan si cambia algo que compila:

- `checks.yml` — en Linux, con cada push y PR: `scripts/checks/strings.py` (en y es con las mismas claves y
  formatos, plurales de `Localizable.stringsdict`, claves que existen), `scripts/checks/viewbuilder_arity.py`
  (bloques de SwiftUI con más de 10 vistas, que no compilan), las pruebas del script de la App Store y las
  de `bridge/`. SwiftLint y actionlint solo informan, hasta que sus avisos estén a cero
- `tests.yml` — tests unitarios en simulador, con cada push a las ramas de trabajo y cada PR a main que
  toque `RepoMind/`, `RepoMindWidget/`, `RepoMindTests/` o el proyecto. Un push nuevo cancela el run
  anterior de la rama; corta a los 25 minutos y adjunta registro y xcresult solo si falla
- `testflight.yml` — build y subida a TestFlight con cada push a las ramas de trabajo, salvo que solo
  toque docs, tests, scripts, `bridge/` o `.claude/`. Con los secretos `MATCH_*` firma con match
  (`fastlane ios beta`); sin ellos, firma en la nube con `-allowProvisioningUpdates`, que crea un
  certificado "Apple Development" por run: a los siete la cuenta llegó al máximo ("Choose a
  certificate to revoke") y hay que revocar los recientes en el portal de desarrollador antes de
  relanzar. Hasta el 27-oct las builds firmadas en la nube salían marcadas «solo TestFlight interno»
  (`testFlightInternalTestingOnly` en `.github/ExportOptions.plist`) y no se podían enviar a revisión; sin
  esa clave deberían poder (sin probar: si App Store Connect las sigue rechazando, hay que firmar con match)
- `store-status.yml` — cada día, en Linux, lee App Store Connect con la clave de los secretos y publica
  `store.json` en la rama `store-data`. Opcional `ASC_VENDOR_NUMBER` para las descargas. **El cron solo
  corre cuando el fichero está en `main`** (hasta entonces, solo con un push que toque `scripts/store-status/`);
  la app marca el dato como viejo pasadas 36 horas
- `release.yml` — a mano, desde main: comprueba que la versión pedida es la `MARKETING_VERSION` del árbol
  y que hay notas en en-US y es-ES, sube metadatos y notas de `fastlane/metadata` y, si se marca, envía a
  revisión (con `build` se fija cuál; sin él, la más nueva que haya procesado Apple). Valen las builds
  firmadas con match y, sin probar, las de la nube posteriores al 27-oct (sin la marca «solo TestFlight
  interno»). Como todo `workflow_dispatch`, solo aparece en Actions cuando el fichero está en main
- `docs.yml` — con un push a main que toque `docs/index.html`, `privacy.html` o `terms.html`, publica
  esas tres páginas en GitHub Pages: son la dirección de soporte, la privacidad y las condiciones que enlazan
  la ficha y la app. El resto de `docs/` es de trabajo y no se publica

## Arquitectura

- **UI**: SwiftUI puro (sin UIKit salvo Mac Catalyst helpers)
- **Datos**: SwiftData con CloudKit sync automático
- **Auth**: GitHub OAuth → `GitHubService.swift`
- **IAP**: StoreKit 2 → `SubscriptionManager.swift`
- **Biometría**: Face ID → `SecurityManager.swift`
- **Tokens**: `KeychainManager` (en `SecurityManager.swift`) los guarda en el Llavero, sincronizables y
  `AfterFirstUnlock`, porque el refresco en segundo plano los lee con el móvil bloqueado
  (`migrateAccessibility` sube los antiguos una vez). **Cerrar sesión pasa siempre por `SessionReset.run`**:
  borra tokens, reportes y todas las cachés (`RepoActivityStore`, `RepoStatsStore`, `StoreStatusStore`,
  `RepoAlertCenter`, `TaskLabelStore`, los puntos de control de `FeedbackService`). Una caché o un token
  nuevos se apuntan ahí; si no, el siguiente usuario del móvil los hereda
- **Lo que viene de fuera**: `SafeLink.web` solo deja abrir https sin credenciales (una URL de un backend
  o de un issue nunca va directa a `openURL`); `LossyDecoding` hace que un elemento malo de una lista de
  un contrato (estadísticas, App Store) se descarte en vez de tirar la lista entera
- **Voz**: Speech framework → `VoiceManager.swift`. Al parar, `KanbanViewModel.prepareCapture` abre
  `VoiceCaptureSheet` (revisar, editar, seguir dictando, guardar) en vez de guardar el dictado tal
  cual; en iOS 26 con Apple Intelligence, `VoiceComposer` (`VoiceCapture.swift`, Foundation Models,
  todo en el dispositivo) le da forma: título, detalles, tipo, columna, y varias tareas si hay
  varios asuntos. Se apaga en Ajustes → Voz
- **ViewModel**: `KanbanViewModel.swift` (único ViewModel del proyecto)
- **Tareas ↔ Issues**: `TaskIssueSyncService.swift` publica cada tarea como issue de GitHub
- **Salud de iCloud**: `CloudKitSyncMonitor.swift` observa `eventChangedNotification` y desglosa
  los `partialFailure` — sin esto un fallo de sync es indistinguible del éxito
- **Reparación**: `OrphanTaskRepair.swift` reengancha tareas que perdieron su columna
- **Actividad de GitHub**: `RepoActivityStore.swift` cachea una hora en `UserDefaults` lo que solo
  sabe GitHub de cada repo (PRs abiertas, último release, estado de CI, último push, visibilidad),
  obtenido en una sola consulta GraphQL con `GitHubService.fetchRepoActivity`. A propósito no es
  SwiftData: es volátil, y así no toca el esquema de CloudKit
- **Estadísticas de cada app**: RepoMind no las recoge, las lee. Cada app sirve un JSON con el
  contrato de `docs/stats-contract.md`; `RepoStatsStore.swift` guarda la URL en `UserDefaults`, el
  token en el Keychain y la última respuesta en caché una hora, y `BoardStatsView` la pinta desde el
  menú del tablero. La primera app que lo sirve es InSync (`supabase/functions/repomind-stats`)
- **Alertas (Pro)**: `RepoAlertCenter.swift` vuelve a preguntar a GitHub y a los backends de las apps
  en el refresco en segundo plano de `FeedbackNotificationManager` y al abrir, compara con lo visto
  (`repoAlertsSeen` en `UserDefaults`) y notifica en local: build en rojo, release nueva, alertas de
  seguridad (`vulnerabilityAlerts` en la query de actividad) y cierres nuevos. Las reglas son puras
  (`RepoAlertRules`) y la primera vez que ve algo solo lo apunta. Interruptores en Ajustes → Alertas
- **Panel de apps (Pro)**: `HomeAppsPanelView` junta todas las apps con estadísticas; desde Inicio
- **Etiquetas y agente**: `TaskLabels.swift`. La captura detecta el tipo (bug, enhancement, idea, chore)
  y si la tarea va al agente; `TaskLabelStore` lo guarda en `UserDefaults` por id de tarea, porque un
  campo nuevo en `TaskItem` exige desplegar el esquema de CloudKit y hoy no hay Mac para sembrarlo
  (pasarlo al modelo con el siguiente despliegue). `TaskIssueSyncService.createIssue` añade esas
  etiquetas; `agent` dispara en el repo el workflow de Claude Code (en InSync, `agent.yml`)
- **Captura desde cualquier sitio**: `Capture/`. `GlobalCaptureSheet` se abre con el micrófono ya
  encendido desde `repomind://capture`, el atajo "Añade una tarea en RepoMind" (`CaptureTaskIntent`,
  App Intents: Siri, botón de acción, Spotlight, control de Atajos) y el widget. Se dice la app y la
  tarea ("en InSync, arreglar el login"); `CaptureRepoResolver` (puro, probado) encuentra la app aunque
  el reconocedor escriba "in sync", y quita la frase que la nombra solo si va al principio o al final;
  en iOS 26 `VoiceComposer.composeGlobal` lee mejor el dictado, y la hoja pide la app si nadie la dijo
  en vez de adivinarla. Las tarjetas de revisión (`CaptureDraftCard`) son las mismas que las del tablero.
  `GlobalCaptureRouter` guarda la petición hasta que haya interfaz (arranque en frío desde Siri)
- **Widget**: `RepoMindWidget/`, una extensión de WidgetKit (bundle `idanidev.RepoMind.Widget`) con un
  solo widget, "Dictar una tarea": pequeño y mediano en la pantalla de inicio, y circular, rectangular
  y en línea en la de bloqueo. Es un botón: un widget no puede grabar audio, así que su `widgetURL`
  (`repomind://capture`) abre la app ya escuchando. No guarda datos, por eso no hay App Group ni
  entitlements. Comparte versión y número de build con la app (los dos en el proyecto). Con la firma
  en la nube (`testflight.yml` sin secretos de match) Xcode crea solo el App ID y el perfil del widget;
  con match, el App ID y el perfil del widget tienen que estar ya en el repo de certificados
  (`fastlane ios certificates`), y ningún workflow ejecuta ese lane: sin Mac es lo que falta para firmar
  con match
- **Estado de la App Store**: `Store/`. RepoMind no habla con Apple, porque la clave de la API (rol
  Admin) no puede vivir en un móvil: el workflow `store-status.yml` (`scripts/store-status/store_status.rb`,
  con pruebas en Ruby) la usa cada día y escribe el JSON de `docs/store-contract.md` en la rama `store-data`;
  `StoreStatusStore` lo lee con el token de GitHub de la cuenta dueña del repo (solo se manda a
  `raw.githubusercontent.com`), lo guarda en `UserDefaults` y `HomeStoreCard` lo pinta en Inicio:
  versión publicada y pendiente por plataforma (`StoreStatus.releases`), build de TestFlight, aviso de
  "build sin enviar a revisión" y descargas por día. Las reglas están en Swift, no en el script, que solo
  vuelca lo de Apple. Las alertas (Pro, `RepoAlertRules.storeAlert`) avisan al entrar en revisión, aprobarse,
  rechazarse o publicarse. La dirección del `store.json` se pone en Ajustes → App Store
- **Notificaciones**: `Notifications/`. Toda notificación local lleva en su `userInfo` un
  `NotificationTarget` (ids y una URL, nunca modelos: un toque puede arrancar la app en frío antes de que
  exista el store). `NotificationDelegate`, puesto en `AppDelegate` antes de terminar el arranque, lo recoge
  y lo deja en `NotificationRouter`; `HomeLiveView` (iPhone) y `AdaptiveRepoListView` (iPad/Mac) lo
  resuelven contra el store (`destination(repos:feedback:)`) y abren el tablero en la tarea, la columna o el
  reporte (`BoardFocus`), o la página de GitHub en las alertas. Sin delegado un toque solo abre la app y las
  notificaciones con la app abierta no se ven. Una notificación nueva sin target no lleva a ningún sitio:
  ponerle uno, y agrupar con `threadIdentifier`
- **Bridge MCP**: `bridge/` (TypeScript) expone las tareas a agentes de código vía GitHub Issues

## Estructura de carpetas

```
RepoMind/              # La app. Grupo sincronizado (objectVersion 77): un fichero nuevo entra solo en el target
├── *.swift            # Servicios y vistas clásicas (iPad/Mac): GitHubService, TaskIssueSyncService,
│                      # SubscriptionManager, SecurityManager, SessionReset, SafeLink, LossyDecoding…
│                      # Models.swift tiene todos los @Model
├── Components/        # Vistas reutilizables (Kanban*, TaskCard, VoiceFAB)
├── Home/              # La home en iPhone: HomeLiveView con las pestañas Inicio, Repos, Tareas y Ajustes
│                      # (Perfil va dentro de Ajustes). Inicio = HomeDashboardView sobre HomeDashboardData: hoy,
│                      # el resumen (HomeDigest: abandonadas, sin publicar, builds, PRs, repos dormidos, apps),
│                      # ritmo de captura, últimas capturas, dónde se acumula, GitHub, apps, cuenta y sync.
│                      # Repos = HomeView con las tarjetas. HomeTheme: colores, `onAccent`, `homeHitArea`
├── Board/             # Tablero rediseñado para iPhone (BoardView sobre KanbanViewModel); iPad/Mac usan KanbanView
├── Capture/           # Dictar una tarea fuera de un tablero: hoja, modelo, quién es la app, atajo de Siri
├── Notifications/     # Adónde lleva cada notificación: target, router, delegado y resolución contra el store
├── Store/             # Estado de la App Store: modelo, almacén y la sección de Ajustes (el script va en scripts/store-status)
├── ViewModels/        # KanbanViewModel.swift
├── Assets.xcassets/   # Colores `Home*` (claro y oscuro), icono, logo
├── en.lproj/          # Strings inglés: Localizable.strings y .stringsdict (plurales)
└── es.lproj/          # Strings español
RepoMindWidget/        # Extensión de WidgetKit: "Dictar una tarea"
RepoMindTests/         # Tests unitarios (XCTest); los de RepoMindUITests/ no corren en CI
bridge/                # Servidor MCP (TypeScript, vitest)
docs/                  # index/privacy/terms.html se publican (docs.yml); el resto es de trabajo
fastlane/              # Fastfile, metadatos de la App Store, capturas
scripts/               # checks/ (Linux, checks.yml) y store-status/ (Ruby, store-status.yml)
```

## Convenciones

- Usar `async/await` — no Combine, no callbacks
- Toda string visible al usuario → `Localizable.strings` (en + es ambos archivos). Un texto con un número
  y un sustantivo ("1 cierre", "2 cierres") va además en `Localizable.stringsdict` (en y es) y se pide con
  interpolación, `String(localized: "clave \(n)")` o `Text("clave \(n)")`, no con `String(format:)`; la
  entrada de `.strings` queda de respaldo. Si hay varios números, redactarlo sin plural ("Pendientes: 3")
- SwiftUI: como mucho 10 vistas por bloque (`VStack`, `body`, `@ViewBuilder`; un `#if` cuenta). Pasarse es
  un error de compilación que en esta cuenta cuesta un run de macOS; `viewbuilder_arity.py` lo ve en Linux
- Accesibilidad: un control pequeño se queda como se ve y gana zona de toque con `homeHitArea` (44 pt); el
  texto sobre un relleno de acento, peligro o aviso lleva `HomeTheme.onAccent`, no `.white` (en oscuro el
  blanco queda a 2,5–3,4:1); algo que no se pulsa no es un `Button` desactivado
- Una lista de cosas por usuario (repos, tareas) que una pantalla de Inicio pinta respeta el tier gratis:
  `SubscriptionManager.repoLimit` y `SubscriptionManager.visible`
- Free tier: máx 3 repos, 1 cuenta GitHub, 3 columnas Kanban — respetar `SubscriptionManager`
- Modelos `@Model` SwiftData: todos los campos opcionales o con valor por defecto
- Mac Catalyst: comprobar `#if targetEnvironment(macCatalyst)` antes de APIs exclusivos de iOS
- SwiftLint activo: no dejar warnings, no imports sin usar
- Clase `@MainActor` (o con la aislación por defecto del módulo) que se crea y se destruye, y no
  solo un `shared`: ponerle `nonisolated deinit {}`. El `deinit` sintetizado queda aislado al main
  actor y pasa por `swift_task_deinitOnExecutor`, que en el runtime de iOS 26 aborta con "pointer
  being freed was not allocated" cuando el objeto muere fuera de una tarea. Mató el host de tests
  en `RepoActivityStoreTests` y antes la app en `BiometricAuthManager` (swiftlang/swift#85663)

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
5. `bundle exec fastlane ios release` y después `submit` — o, sin Mac, con la build que ya subió
   `testflight.yml`: merge a main y Actions → Release con "Enviar a revisión" marcado y el número de
   build. Vale una firmada con match o, sin probar, una de la nube posterior al 27-oct
6. **Actualizar este CLAUDE.md**: historial de versiones abajo, y arquitectura/convenciones si el
   release ha añadido servicios o reglas nuevas

## Historial de versiones

- **1.5.3** *(en TestFlight; sin enviar a revisión)* — Inicio nuevo, Tareas, tablero por columnas en
  iPhone, estadísticas de cada app, voz con revisión, captura desde el widget, Siri y el botón de acción,
  etiquetas y agente, notificaciones que llevan a la tarea, estado de la App Store y alertas Pro. Sin
  `@Model` nuevos desde la 1.5.2: no hace falta desplegar el esquema de CloudKit.
- **1.5.2** *(aprobada)* — Proyectos duplicados (cuenta registrada dos veces) e iconos que desaparecían,
  columna de ideas, aviso de issues abiertos fuera de la app.
- **1.5.0** *(enviada a revisión el 21/08/2026, build 202608211225)* — Onboarding, carpetas de proyectos, sincronización selectiva a issues, reautenticación
  sin cerrar sesión al caducar el token, reparación de tareas huérfanas y diagnóstico real de los
  errores de CloudKit. Modelos nuevos: `RepoFolder`, `TaskItem.lastSyncError`.
- **1.4.2** — Correcciones de sincronización y caché de iconos.

## Cuidado con

- `.claude/settings.local.json` contiene credenciales de App Store Connect — **nunca commitear** (está en
  `.gitignore`)
- Los tests requieren simulador real: correr `xcodebuild` con destino correcto
- CloudKit en desarrollo requiere entitlements firmados — build directo en simulador puede fallar el sync
- `match` gestiona los certificados desde un repo privado de GitHub — no regenerar manualmente
- **Entitlements separados por configuración**: Debug usa `RepoMindDebug.entitlements`
  (CloudKit `Development`, `aps-environment` `development`) y Release usa `RepoMind.entitlements`
  (`Production`). Durante meses ambos apuntaron a Production: las builds de desarrollo escribían
  en los datos reales, el esquema de Development nunca se actualizaba al probar, y CloudKit
  rechazaba en silencio cada tipo nuevo. `aps-environment` importa igual — CloudKit avisa de los
  cambios por push silencioso, y una build de desarrollo que declara `production` no los recibe.
