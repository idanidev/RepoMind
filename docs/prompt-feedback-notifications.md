# Prompt: Notificaciones de feedback de usuarios en RepoMind

Copia y pega esto en Claude Code dentro del proyecto RepoMind.

---

## Prompt

Necesito una nueva funcionalidad en RepoMind: **notificaciones de feedback de usuarios**.

### Contexto

Tengo una app publicada (iTurn) cuyo repo es `idanidev/iturn`. Una rutina automatizada crea GitHub Issues con el label `user-feedback` cada vez que un usuario reporta un error, pide una mejora o deja una review en el App Store. Los issues usan estos labels:

- `bug:critical` + `user-feedback` — crash, perdida de datos, app inutilizable
- `bug:minor` + `user-feedback` — bug visual o no bloqueante
- `enhancement` + `user-feedback` — peticion de feature
- `user-feedback` (solo) — queja general

### Lo que quiero

1. **Seccion "Feedback" en RepoMind** — una vista nueva (tab o seccion dentro del repo) que muestre los issues con label `user-feedback` del repo seleccionado, agrupados por categoria (critico, menor, mejora, general). Cada issue muestra: titulo, fecha, fuente (email/review), rating si aplica, y estado (open/closed).

2. **Notificaciones push** — cuando se crea un nuevo issue con label `user-feedback`, enviar una notificacion local al dispositivo. El titulo debe indicar la severidad:
   - Bug critico: "🔴 [repo] Error critico reportado"
   - Bug menor: "🟡 [repo] Bug menor reportado"  
   - Mejora: "🟢 [repo] Nueva mejora solicitada"
   - General: "💬 [repo] Nuevo feedback de usuario"

3. **Polling** — como no tenemos servidor, hacer polling cada 15 minutos via `BGAppRefreshTask` (igual que ya se hace para otras cosas si existe). Consultar la GitHub API: `GET /repos/{owner}/{repo}/issues?labels=user-feedback&since={last_check}&state=open`. Guardar timestamp del ultimo check en UserDefaults.

4. **Badge** — mostrar badge numerico en la tab/seccion de Feedback con el conteo de issues sin leer. Marcar como leido al abrir el issue.

### Restricciones

- Usar la autenticacion GitHub OAuth que ya existe en `GitHubService.swift`
- Modelos SwiftData `@Model` para persistir issues de feedback localmente (cache + estado leido/no leido)
- Respetar la arquitectura existente: SwiftUI, async/await, sin Combine
- Localizar strings en ingles y espanol (en.lproj + es.lproj)
- Free tier: esta funcionalidad disponible para todos los repos conectados (no restringir por suscripcion)
- Notificaciones locales con `UNUserNotificationCenter`, pedir permiso si no se tiene
- Compilar y verificar que pasan los tests antes de dar la tarea por terminada
