# BORRADOR: política de privacidad y condiciones al día con la app

**No está publicado.** `docs/privacy.html` y `docs/terms.html` son lo que ve Apple y lo que enlazan la
ficha y la app; siguen como en febrero de 2025. Esto es lo que dicen mal hoy y el texto que propongo.
Es tuyo decidir qué entra: son documentos legales y no los toco sin que lo digas. `docs.yml` ya solo
publica `index.html`, `privacy.html` y `terms.html`, así que este fichero no sale a internet.

## Lo que hoy es falso o está incompleto

| Dónde | Dice | La app hace |
|---|---|---|
| privacy · Data Storage | "All your data … is stored locally on your device" y "No cloud storage of personal data" | SwiftData sincroniza con **iCloud (CloudKit, base privada del usuario)**: `RepoMindApp.swift:74`, `cloudKitDatabase: .automatic`. Repos, tableros, tareas e imágenes de tareas viajan por el iCloud de cada usuario. |
| privacy · Voice | "Processed on-device … not transmitted externally" | Reconocimiento en el dispositivo **cuando el idioma lo permite**; si no hay modelo local, Apple lo hace en sus servidores (`VoiceManager.swift:205-211`). |
| privacy · GitHub Access Tokens | "Stored in your Keychain" | Además son sincronizables: pasan al Llavero de iCloud del usuario si lo tiene activo (`kSecAttrSynchronizable`). |
| privacy · Third-party services | GitHub, voz de Apple, StoreKit | Faltan: el estado de la App Store (`raw.githubusercontent.com`, con el token de GitHub del usuario) y las estadísticas de cada app, que se leen de la dirección que **el usuario** configura (con un token que guarda en el Llavero). |
| privacy · todo | No menciona que las tareas se publican como issues | Si el usuario lo activa, cada tarea se crea como issue de GitHub (datos del usuario hacia su propio GitHub). |
| terms · Subscriptions and Payments | "Pro Subscription", "automatically renew", "cancel subscriptions" | Pro es **un pago único** (`com.idanidev.repomind.pro`, no consumible) y la ficha dice "No subscriptions". |
| ambos | "Last updated: February 2025" | La app es la 1.5.x de agosto de 2026. |

Comprobaciones tuyas, que desde aquí no puedo hacer: que la ficha de privacidad de App Store Connect
("App Privacy") diga lo mismo que el texto final, y que el correo `privacy@idanidev.com` / `legal@idanidev.com`
exista y lo leas.

## Texto propuesto: Privacy Policy

> **Last updated: [fecha de publicación]**
>
> RepoMind ("we", "our", "the app") is made by one developer. It has no servers of its own, no
> accounts of its own, no analytics and no advertising. This policy says where your information goes.
>
> **What the app handles**
> - **GitHub access tokens.** Kept in your Keychain. If you use iCloud Keychain, Apple syncs them
>   between your devices. They are only ever sent to GitHub (`api.github.com`), and to
>   `raw.githubusercontent.com` when you use the App Store status card.
> - **Your repositories, boards, tasks and attached images.** Stored on your device with SwiftData and
>   synced through your private iCloud (CloudKit) database, which only you can read. We cannot see it.
> - **Voice.** The microphone is used only while you dictate. Speech is recognised on your device when
>   your language supports it; otherwise Apple's servers do it, under Apple's privacy policy. Audio is not
>   kept by the app. The optional task-shaping feature uses Apple Intelligence **on your device**.
> - **GitHub issues.** If you turn on issue sync, the text of your tasks is sent to GitHub as issues in
>   the repository you chose, and read back. That is your data going to your own GitHub account.
> - **App statistics (optional).** If you give a board a statistics address, the app asks that address
>   (an HTTPS endpoint you control) for numbers and keeps the token you entered in your Keychain.
> - **Preferences and caches.** Stored on the device (UserDefaults) and can be wiped by signing out.
>
> **What we do not do.** We do not collect, sell or share personal data. No third-party SDKs or trackers.
> If you chose "Share with App Developers" in your device settings, Apple may give us aggregated,
> anonymous App Analytics (downloads, sessions, crashes); we receive nothing else.
>
> **Purchases.** Handled by Apple (StoreKit). We never see your payment details.
>
> **Notifications.** They are created on your device from what the app reads; there is no push server.
>
> **Deleting your data.** Signing out removes the tokens and caches from the device. To remove the iCloud
> copy, delete the app's data from your iCloud storage settings.
>
> **Children.** Not directed at children under 13.
>
> **Contact.** privacy@idanidev.com

## Texto propuesto: cambios en Terms of Use

Sustituir la sección **Subscriptions and Payments** por:

> **Purchases**
> - Free tier: 1 GitHub account, 3 repositories and 3 Kanban columns per board.
> - Pro: a single, one-time purchase through the App Store that unlocks unlimited accounts,
>   repositories and columns. It is not a subscription and does not renew.
> - Payment and refunds are handled by Apple under its terms. You can restore a past purchase from
>   the app.

Y actualizar "Last updated". En **User Accounts** puede quedarse tal cual.

## Para publicarlo

1. Decide el texto (o dime qué cambias) y pasa los cambios a `docs/privacy.html` y `docs/terms.html`.
2. Merge a main: `docs.yml` despliega solo si cambian esas páginas.
3. Revisa "App Privacy" en App Store Connect con el mismo texto delante.
