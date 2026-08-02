---
description: Audita las strings sin localizar en el proyecto y añade las que faltan
---

## Strings en código Swift (posiblemente sin localizar)

!`grep -r '"[A-Z][a-z]' RepoMind/ --include="*.swift" -n | grep -v "//\|Localizable\|#if\|import\|case \|let \|var \|func \|class \|struct \|enum \|print\|Logger" | head -40`

## Strings en Localizable.strings (EN)

!`cat RepoMind/en.lproj/Localizable.strings`

## Strings en Localizable.strings (ES)

!`cat RepoMind/es.lproj/Localizable.strings`

---

Audita los resultados anteriores:

1. Identifica strings hardcodeadas visibles al usuario que no estén localizadas
2. Para cada una, propón la key en formato `seccion_descripcion`
3. Añade las entradas en ambos archivos `Localizable.strings` (en + es)
4. Actualiza el código Swift para usar `String(localized: "key")` o `Text("key")`

Prioriza las strings de la UI principal (botones, títulos, mensajes de error).
