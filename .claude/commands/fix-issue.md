---
description: Investiga y arregla un issue de GitHub
argument-hint: [número-de-issue]
---

## Issue #$ARGUMENTS

!`gh issue view $ARGUMENTS`

## Archivos relacionados con el área del bug

!`git log --oneline -20`

---

Estudia el issue anterior en detalle:

1. Reproduce mentalmente el bug leyendo el código relevante
2. Identifica la causa raíz — no el síntoma
3. Implementa el fix mínimo necesario (no refactorices código no relacionado)
4. Escribe o actualiza el test que habría detectado este bug
5. Verifica que el fix respeta las convenciones del proyecto (localización, SubscriptionManager, etc.)

Al terminar, muestra un resumen: causa raíz, fix aplicado, test añadido.
