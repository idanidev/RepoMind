---
description: Revisa los cambios del branch actual antes de hacer merge o PR
---

## Archivos modificados

!`git diff --name-only main...HEAD`

## Diff completo

!`git diff main...HEAD`

## Lint actual

!`swiftlint lint --config .swiftlint.yml --quiet 2>&1 | head -50`

---

Revisa los cambios anteriores con foco en:

1. **Corrección** — bugs, edge cases, manejo de errores
2. **SwiftUI** — uso correcto de state, evitar re-renders innecesarios
3. **SwiftData / CloudKit** — modelos con campos opcionales, relaciones correctas
4. **Localización** — toda string visible al usuario localizada en en + es
5. **Límites de suscripción** — respeta los límites del free tier de `SubscriptionManager`
6. **Mac Catalyst** — APIs envueltos en `#if targetEnvironment(macCatalyst)` donde aplique
7. **Tests** — ¿los cambios necesitan tests nuevos o actualizar existentes?

Da feedback específico por archivo, con línea concreta y sugerencia de fix.
