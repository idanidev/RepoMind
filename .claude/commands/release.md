---
description: Prepara y ejecuta el release de una nueva versión a App Store
argument-hint: [ios|mac|both]
---

## Estado actual del repo

!`git status`

## Versión actual

!`plutil -p RepoMind/Info.plist 2>/dev/null || grep -r "MARKETING_VERSION" RepoMind.xcodeproj/project.pbxproj | head -3`

## Último tag de versión

!`git tag --sort=-version:refname | head -5`

## Cambios desde el último release

!`git log $(git describe --tags --abbrev=0)..HEAD --oneline 2>/dev/null || git log --oneline -20`

---

Plataforma objetivo: **$ARGUMENTS**

Sigue estos pasos para el release:

1. Verifica que no hay cambios sin commitear (git status debe estar limpio)
2. Resume los cambios desde el último release para el changelog
3. Sugiere el número de versión siguiente (semver: MAJOR.MINOR.PATCH)
4. Indica el comando exacto de fastlane a ejecutar según la plataforma:
   - `ios` → `bundle exec fastlane ios release`
   - `mac` → `bundle exec fastlane mac release`
   - `both` → ambos en orden (ios primero)
5. Recuerda verificar en App Store Connect después del upload

**No ejecutes fastlane directamente** — muestra el comando y espera confirmación.
