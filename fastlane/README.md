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

Sube la app a App Store y la envía a revisión

### ios bump_version

```sh
[bundle exec] fastlane ios bump_version
```

Sube la versión de marketing

----

This README.md is auto-generated and will be re-generated every time [_fastlane_](https://fastlane.tools) is run.

More information about _fastlane_ can be found on [fastlane.tools](https://fastlane.tools).

The documentation of _fastlane_ can be found on [docs.fastlane.tools](https://docs.fastlane.tools).
