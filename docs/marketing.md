# Posicionamiento y crecimiento — RepoMind

Cubre las tareas #32 (ASO: nombre invisible y expectativas de nicho) y #33 (auditoría de
crecimiento). Escrito tras mirar la competencia real en la App Store, no de memoria.

## 1. El problema no es el nombre. Es contra quién compites.

La descripción actual abre así:

> RepoMind mantiene todos tus repositorios de GitHub organizados en un solo lugar — con tableros
> Kanban, tareas por voz y sincronización iCloud entre iPhone y Mac.

Eso te coloca en la categoría **"cliente de GitHub para iPhone"**. Y en esa categoría pierdes,
porque el líder es **la app oficial de GitHub**: gratis, primera parte, y ya hace triaje de issues
desde el móvil. Nadie instala tu app para hacer peor lo que la oficial ya hace gratis.

El resto de la categoría, además, está muerto o hace otra cosa:

| App | Estado |
|---|---|
| **GitHub** (oficial) | Gratis, primera parte. **Sin modo offline** — es su queja recurrente. Sin voz. |
| **GitHawk**, **CodeHub** | Open source, prácticamente abandonadas. |
| **Working Copy** | Cliente Git de pago, muy querido. Otro trabajo: mover código, no gestionar tareas. |
| **Anywhere Issue** | Competidor nuevo y directo en issues de GitHub. Vigílalo. |

## 2. Tu ventaja real no aparece en la ficha

Ninguna de esas apps hace lo que sí haces tú:

**Capturar sin teclado.** La oficial sirve para *triar* issues que ya existen. La tuya, para
*crear* la tarea en el momento en que se te ocurre — en el sofá, andando, sin escribir. Eso no es
"una app de GitHub con micrófono": es otro momento de uso.

**El bridge MCP.** Dictas un bug desde el móvil y tu agente de código lo lee al abrir el repo en el
Mac. **Nadie más hace esto.** Es el argumento más fuerte que tienes y **no está en la descripción,
ni en el subtítulo, ni salía en las capturas hasta hoy**.

Ese es el nicho: no "gestiona tus repos", sino **el hueco entre tener la idea y sentarte a
programar**. Ahora mismo lo estás vendiendo como si fueras un cliente de GitHub más.

## 3. Qué cambiar en la ficha

Hecho en 1.5.0: nombre `RepoMind: Kanban for GitHub`, subtítulo `Dicta tareas, cierra issues`,
keywords reescritas y cuatro capturas nuevas.

Falta la **descripción**, que sigue abriendo por lo que menos te diferencia. Empieza por el momento
de uso, no por la funcionalidad:

> Se te ocurre el arreglo lejos del teclado. Lo dictas, y cuando abres el proyecto tu agente de
> código ya sabe qué hacer.

Y sube el bridge del último párrafo al segundo bloque.

## 4. Canales, por orden de rentabilidad

El público es "desarrolladores iOS e indies que usan agentes de código". Es pequeño y muy
localizable, así que la publicidad genérica no sirve.

1. **El bridge como producto propio.** Publica `bridge/` como repo independiente con su README:
   *"Lee tus tareas de RepoMind desde Claude Code / Cursor / Codex"*. Los servidores MCP se están
   listando y compartiendo mucho ahora mismo. Es un canal de entrada gratuito que llega exactamente
   al perfil que te interesa.
2. **Escribir el post que ya has vivido.** *"Mi app llevaba meses sin sincronizar y no me enteré"*
   — la historia del esquema de CloudKit sin desplegar, con la explicación técnica de verdad. Ese
   tipo de post circula entre desarrolladores iOS, y presenta la app sin vender nada.
3. **Comunidades donde ya está tu gente:** r/iOSProgramming, Hacker News (Show HN), iOS Dev Weekly,
   y los espacios de Claude Code / Cursor. Un lanzamiento honesto de un dev independiente funciona
   ahí; un anuncio, no.
4. **Product Hunt** — solo cuando el rediseño esté hecho. Se gasta una vez.

## 5. Qué medir

Ver `docs/analytics.md`. Compara cuatro semanas antes y después de la 1.5.0: primero
**Impressions** (¿te encuentran?), luego **Conversion Rate** (¿la ficha convence?), y por último
**Retention día 7** (¿sirve?). Si sube la conversión pero la retención sigue plana, el problema ya
no es de marketing.

## 6. La parte incómoda

La app lleva meses publicada con la sincronización rota en silencio, y eso golpea justo la
retención: alguien la instala, mete tareas, no las ve en su otro dispositivo, la borra y no vuelve.
**La 1.5.0 es la primera versión que merece tráfico.** Empujar canales antes de confirmar que el
esquema de CloudKit está desplegado en Production sería gastar la primera impresión.

---

**Fuentes consultadas**

- [Slant — Best GitHub clients for iOS](https://www.slant.co/topics/1429/~best-github-clients-for-ios)
- [GitHub Mobile — documentación oficial](https://docs.github.com/en/get-started/using-github/github-mobile)
- [Community discussion — Offline access en GitHub Mobile](https://github.com/orgs/community/discussions/157223)
- [Anywhere Issue — App Store](https://apps.apple.com/us/app/anywhere-issue-github-issues/id6748542739)
- [Working Copy](https://workingcopy.app/)
