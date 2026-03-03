fastlane documentation
----

# Installation

Make sure you have the latest version of the Xcode command line tools installed:

```sh
xcode-select --install
```

For _fastlane_ installation instructions, see [Installing _fastlane_](https://docs.fastlane.tools/#installing-fastlane)

# Available Actions

## iOS

### ios certificates

```sh
[bundle exec] fastlane ios certificates
```

Sincroniza certificados de distribución con match

### ios build

```sh
[bundle exec] fastlane ios build
```

Compila la app en modo Release

### ios beta

```sh
[bundle exec] fastlane ios beta
```

Sube una build a TestFlight

### ios release

```sh
[bundle exec] fastlane ios release
```

Compila y sube el IPA a App Store Connect (sin enviar a revisión)

### ios submit

```sh
[bundle exec] fastlane ios submit
```

Envía a revisión el build ya subido (sin recompilar)

### ios bump_version

```sh
[bundle exec] fastlane ios bump_version
```

Sube la versión de marketing (ej: fastlane bump_version version:1.1)

----


## Mac

### mac certificates

```sh
[bundle exec] fastlane mac certificates
```

Genera el perfil Mac Catalyst

### mac build

```sh
[bundle exec] fastlane mac build
```

Compila la app macOS (Mac Catalyst) en modo Release

### mac release

```sh
[bundle exec] fastlane mac release
```

Compila y sube el PKG a App Store Connect (sin enviar a revisión)

### mac submit

```sh
[bundle exec] fastlane mac submit
```

Envía a revisión el build macOS ya subido (sin recompilar)

----

This README.md is auto-generated and will be re-generated every time [_fastlane_](https://fastlane.tools) is run.

More information about _fastlane_ can be found on [fastlane.tools](https://fastlane.tools).

The documentation of _fastlane_ can be found on [docs.fastlane.tools](https://docs.fastlane.tools).
