---
description: Prepara y ejecuta el release de una nueva versión a App Store
argument-hint: [ios|mac|both]
---

## Estado actual del repo

!`git status`

## Versión actual

!`grep -h "MARKETING_VERSION" RepoMind.xcodeproj/project.pbxproj | sort -u`

## Último envío a revisión

Este repo no pone tags: el último envío es el commit "chore(release): X.Y.Z submitted for review".

!`git log --grep='submitted for review' -1 --format='%h %ad %s' --date=short`

## Cambios desde el último envío

!`git log $(git log --grep='submitted for review' -1 --format=%h)..HEAD --oneline 2>/dev/null | head -60`

## ¿Cambió algún @Model desde entonces?

!`git diff --stat $(git log --grep='submitted for review' -1 --format=%h)..HEAD -- RepoMind/Models.swift`

---

Plataforma objetivo: **$ARGUMENTS**

El orden completo está en CLAUDE.md → "Publicar una versión". Sigue estos pasos:

1. Verifica que no hay cambios sin commitear (git status debe estar limpio)
2. Resume los cambios desde el último envío para las notas de la versión
3. Sugiere el número de versión siguiente (semver: MAJOR.MINOR.PATCH)
4. **Si el diff de `Models.swift` toca un `@Model` (un campo o una clase), para aquí**: antes de enviar hay
   que desplegar el esquema de CloudKit (CLAUDE.md, paso 3). Sin eso, la sincronización de esa entidad se
   rompe en silencio para todos los usuarios
5. Comprueba que `fastlane/metadata/en-US/release_notes.txt` y `es-ES/release_notes.txt` hablan de esta versión
6. Indica cómo publicar, según haya Mac o no:
   - Con Mac: `ios` → `bundle exec fastlane ios release` y luego `submit`; `mac` →
     `bundle exec fastlane mac release`; `both` → ambos, ios primero
   - Sin Mac: la rama con la versión tiene que estar en main; Actions → Release con el número de build
     y "Enviar a revisión". Vale una build firmada con match, o una de la nube posterior al 27-oct (sin la
     marca «solo TestFlight interno»; sin probar)
7. Recuerda verificar en App Store Connect después del upload y actualizar el historial de CLAUDE.md

**No ejecutes fastlane directamente** — muestra el comando y espera confirmación.
