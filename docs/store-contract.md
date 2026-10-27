# Contrato de estado de la App Store — versión 1

RepoMind no habla con App Store Connect: la clave de la API (rol Admin) no puede viajar dentro de
una app. Un workflow programado en **tu** repo (`.github/workflows/store-status.yml`) la usa cada día,
escribe este JSON en la rama `store-data` y RepoMind lo lee con tu token de GitHub, igual que lee las
estadísticas de cada app. Quien quiera lo mismo con otras apps copia el script y los secretos.

## Qué responde

- Qué versión de cada app está **publicada**, cuál está **pendiente** (en revisión, rechazada, lista
  para enviar, aprobada sin publicar) y cuál es la última build de **TestFlight**.
- Cuántas **descargas**, actualizaciones y compras hubo por día, si se da el número de proveedor.

## Forma

```json
{
  "schema": 1,
  "generatedAt": "2026-10-27T06:31:00Z",
  "apps": [
    {
      "id": "6740000000",
      "name": "RepoMind: Kanban for GitHub",
      "bundleId": "idanidev.RepoMind",
      "repo": "RepoMind",
      "versions": [
        { "platform": "IOS", "version": "1.5.3", "state": "WAITING_FOR_REVIEW", "createdAt": "2026-10-20T10:00:00Z" },
        { "platform": "IOS", "version": "1.5.2", "state": "READY_FOR_SALE", "createdAt": "2026-09-01T09:00:00Z" }
      ],
      "builds": [
        { "version": "1.5.3", "build": "202610270821", "uploadedAt": "2026-10-27T08:24:00Z",
          "state": "VALID", "expired": false }
      ],
      "sales": {
        "through": "2026-10-25",
        "daily": [ { "date": "2026-10-25", "downloads": 3, "updates": 12, "purchases": 1 } ]
      }
    }
  ]
}
```

- `schema`: siempre `1`. Una versión que RepoMind no conozca se rechaza entera.
- `generatedAt`: ISO 8601 con zona.
- `repo`: el nombre del repo de GitHub al que corresponde la app, si se ha dado en
  `scripts/store-status/apps.json`. Sin él, RepoMind lo adivina por el nombre y el bundle id.
- `versions`: las seis más recientes por fecha de creación, de todas las plataformas. `state` es el
  `appVersionState` de Apple tal cual (o el `appStoreState` antiguo si no viene, y `null` si no viene
  ninguno): `READY_FOR_DISTRIBUTION` (antes `READY_FOR_SALE`) es la publicada;
  `PREPARE_FOR_SUBMISSION`, `WAITING_FOR_REVIEW`, `IN_REVIEW`, `PENDING_DEVELOPER_RELEASE`,
  `REJECTED`, `METADATA_REJECTED`… son pendientes. RepoMind decide qué es cada cosa, no el script, y
  entiende las dos grafías de la publicada; un estado que no conoce es "otro", no un error.
- `builds`: las cinco últimas, con la versión de marketing (`version`) y el número de build.
- `sales`: ausente cuando no hay `ASC_VENDOR_NUMBER` o la clave no puede ver ventas. `daily` tiene un
  día por fecha hasta `through`, con ceros donde Apple no informa ventas. Las fechas son las de Apple,
  en hora del Pacífico, y `through` es el último día ya cerrado.
  - `downloads`: primeras descargas (tipos de producto 1, 1F, 1T, F1, 1E, 1EP, 1EU). Las
    redescargas no cuentan.
  - `updates`: actualizaciones (7, 7F, 7T, F7).
  - `purchases`: compras dentro de la app de una sola vez (IA1), como el Pro de por vida.

## Retraso

Apple publica los informes de ventas de un día a la mañana siguiente, hora del Pacífico. Por eso las
descargas llevan siempre uno o dos días de retraso, y no hay umbral de privacidad como en App
Analytics: son todas.

## Secretos del workflow

| Secreto | Para qué |
|---|---|
| `ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_KEY_P8` | La clave de la API de App Store Connect. Ya existen. |
| `ASC_VENDOR_NUMBER` | Opcional. El número de proveedor, en App Store Connect → Ventas y tendencias → Informes, arriba a la izquierda. Sin él no hay descargas, solo versiones. |
