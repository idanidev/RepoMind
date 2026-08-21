# Analítica — RepoMind

Decisión: **solo App Analytics de Apple**. Sin SDK de terceros, sin eventos propios, sin enviar
nada a ningún servidor que no sea Apple.

## Por qué

Cualquier alternativa que responda "¿usan la función de voz?" exige mandar eventos de tus usuarios
a un tercero, y eso obliga a tocar la política de privacidad publicada en `docs/privacy.html` y la
ficha de privacidad de la App Store. Para una app de un solo desarrollador con pocas descargas,
ese coste no compensa todavía.

## Qué te da, y dónde

App Store Connect → tu app → pestaña **Analytics**. No hay que instalar nada: los datos ya se
están recogiendo desde el primer día, incluso de versiones anteriores.

| Métrica | Para qué sirve |
|---|---|
| **Impressions** | Cuánta gente ve la ficha. Si sube tras el cambio de nombre, el ASO funcionó. |
| **Product Page Views** | Cuántos entran a la ficha desde esa impresión. |
| **Conversion Rate** | Vistas → descargas. **La métrica que mide capturas, nombre y subtítulo.** |
| **Total Downloads** | Descargas. |
| **Sessions per Active Device** | Cuántas veces al día se abre. Proxy de si la app se usa o se instala y se olvida. |
| **Retention** | Cuántos siguen ahí al día 1, 7 y 28. La métrica más honesta de si la app sirve. |
| **Crashes** | Fallos por versión. |

Los datos tardan **1-2 días** en aparecer, y hay un umbral de privacidad por debajo del cual Apple
no muestra nada: con muy pocos usuarios, algunas métricas salen vacías.

## Qué NO te da

Esto es exactamente lo que pedía la tarea #34 y que esta decisión deja fuera:

- **Uso por funcionalidad.** No sabrás cuántos usan la captura por voz, cuántos crean columnas, ni
  cuántos activan la sincronización con issues.
- **Embudos.** No sabrás en qué paso del onboarding se cae la gente.
- **Errores propios.** Los fallos de sincronización con GitHub o CloudKit no aparecen: no son
  crashes. Para eso están `CloudKitSyncMonitor` y el `lastSyncError` de cada tarea, que solo se ven
  dentro de la app y solo en tu dispositivo.

Si algún día esas preguntas pesan más que evitar un SDK, las opciones descartadas fueron
**TelemetryDeck** y **Aptabase**: las dos sin datos personales, pensadas para apps independientes,
y las dos obligarían a actualizar la privacidad de la ficha.

## Qué mirar tras la 1.5.0

El cambio de nombre a *RepoMind: Kanban for GitHub*, el subtítulo y las capturas nuevas afectan a
la parte alta del embudo. Compara **cuatro semanas antes contra cuatro después**, en este orden:

1. **Impressions** — ¿te encuentra más gente? Mide el nombre y las keywords.
2. **Conversion Rate** — ¿los que llegan se descargan? Mide capturas y subtítulo.
3. **Retention día 7** — ¿se quedan? Eso ya no lo arregla el ASO.

Si suben las impresiones pero no la conversión, el problema está en la ficha, no en el nombre. Si
sube la conversión pero la retención sigue plana, el problema está en el producto.
