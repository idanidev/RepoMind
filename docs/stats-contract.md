# Contrato de estadísticas — versión 1

RepoMind no recoge estadísticas: las lee. Cada app sirve un JSON con esta forma en una URL
protegida por un token, y RepoMind lo pinta igual para todas, en la página Estadísticas del
tablero y, la cifra principal, en la tarjeta del repo. La URL y el token se guardan en el
iPhone (el token en el Keychain) y se refrescan cada hora, sin pasar por ningún tercero.

La primera app que lo sirve es InSync: `supabase/functions/repomind-stats` sobre la función
SQL `estadisticas_para_repomind`, que calcula lo mismo que su panel de admin.

## Petición

```
GET <endpoint>?days=30
Authorization: Bearer <token>
```

`days` es la ventana "actual" (1 a 365, 30 por defecto). La ventana "anterior", para las
flechas, es del mismo tamaño y va justo antes.

## Respuesta

```json
{
  "schema": 1,
  "app": "InSync",
  "generatedAt": "2026-10-27T01:30:00.123456+00:00",
  "periodDays": 30,
  "headline": [
    { "key": "active_week", "label": "Activas 7 días", "value": 31, "previous": null, "primary": true },
    { "key": "paying", "label": "De pago", "value": 4, "previous": 3 }
  ],
  "signals": [
    { "key": "pantalla.compra", "current": 320, "previous": 280 }
  ],
  "features": [
    { "key": "compra", "label": "Compra", "adopters": 30, "activeAdopters": 18, "population": 40 }
  ],
  "series": [
    { "key": "app.abierta", "label": "Aperturas", "points": [ { "date": "2026-10-01", "value": 40 } ] }
  ],
  "versions": [
    { "version": "1.0.12", "current": 300 },
    { "version": null, "current": 12 }
  ],
  "issues": [
    { "kind": "crash", "title": "excepción 6", "at": "2026-10-26T20:11:00+00:00", "count": 3,
      "version": "1.0.12", "url": null, "status": "crash" },
    { "kind": "report", "title": "No me deja invitar", "at": "2026-10-25T09:00:00+00:00", "count": 1,
      "version": "1.0.12", "url": "https://github.com/idanidev/InSync/issues/90", "status": "nuevo" }
  ]
}
```

| Campo | Qué es |
|---|---|
| `schema` | Versión del contrato. RepoMind rechaza lo que no entienda. |
| `app` | Nombre que se enseña. |
| `generatedAt` | Cuándo se calculó, ISO 8601 con zona. |
| `headline[]` | Las cifras de cabecera, en el orden en que se enseñan. `previous` es opcional y pone la flecha; `primary: true` marca la que va en la tarjeta del repo (una como mucho). |
| `signals[]` | Contadores por señal, periodo actual contra anterior. RepoMind los agrupa por el primer tramo del nombre (`pantalla.compra` → `pantalla`) y los ordena de más a menos usado. |
| `features[]` | Adopción por función: cuántos (`adopters`) de la población (`population`) la han usado alguna vez, y cuántos en los últimos 30 días (`activeAdopters`). |
| `series[]` | Series diarias. `date` es un día (`YYYY-MM-DD`), sin hora. |
| `versions[]` | Reparto por versión en el periodo actual. `version: null` es "sin versión". |
| `issues[]` | Últimos fallos (`kind: "crash"`) y reportes (`kind: "report"`), los más recientes primero. `url` enlaza al issue si existe. |

Todo lo que no sea `schema`, `app` y `generatedAt` puede faltar o venir vacío: una app sin
suscripciones no manda `paying`, y una sin MetricKit no manda `issues`.

## Reglas

- **Solo agregados.** Nunca un identificador de persona, un correo, ni el texto entero de un
  reporte. Lo que sale por aquí acaba en un iPhone y en una caché en disco.
- Las etiquetas (`label`) van en el idioma de la app, y se enseñan tal cual.
- Un endpoint que cambie de forma sube `schema`; RepoMind sigue enseñando la caché anterior
  hasta que la entienda.
