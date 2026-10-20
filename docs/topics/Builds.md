# Builds

<link-summary>Flutter app builds for every platform, signing, notarization and native Dart binaries.</link-summary>

## Flutter apps

`flutter-build.yml` builds every app (a Flutter package that is not published, with
`lib/main.dart` and a platform directory, or the packages in `build.flutter.apps`) for every
enabled target, each on the runner it needs:

| Target | Runner | Output |
|---|---|---|
| `web` | Linux | `build/web`, also the part `web` of the Pages site |
| `apk`, `appbundle` | Linux | `.apk` (`android-split-per-abi`), `.aab` |
| `ios` | macOS | `Runner.app`, zipped |
| `ipa` | macOS | `.ipa` when signed with an `export-options-plist`, an unsigned `.xcarchive` otherwise |
| `macos` | macOS | the `.app`, zipped, notarized with `build.flutter.macos-notarize` |
| `linux-x64`, `linux-arm64` | Linux x64, Linux ARM | the bundle as `.tar.gz` |
| `windows-x64`, `windows-arm64` | Windows x64, Windows ARM | the runner directory as `.zip` |

```yaml
build:
  flutter:
    targets:
      web: auto
      apk: true
      ipa: true
    flavor: production
    target-file: lib/main_production.dart
    dart-define-from-file: config/production.json
    build-name: pubspec
    build-number: run-number
    obfuscate: true
```

A target is skipped with a notice when the app has no directory for its platform. Every build is
the artifact `flutter-<app>-<target>`; the symbols of obfuscated builds are
`flutter-<app>-<target>-symbols`. In a release, every build is also attached to the GitHub
release.

### Android signing

With the secrets `ANDROID_KEYSTORE_BASE64`, `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS` and
`ANDROID_KEY_PASSWORD` the build writes `android/key.properties`. The app reads it in
`android/app/build.gradle.kts`, as in Flutter's deployment guide:

```kotlin
val keystoreProperties = java.util.Properties().apply {
    val file = rootProject.file("key.properties")
    if (file.exists()) load(file.inputStream())
}

android {
    signingConfigs {
        create("release") {
            keyAlias = keystoreProperties["keyAlias"] as String?
            keyPassword = keystoreProperties["keyPassword"] as String?
            storeFile = (keystoreProperties["storeFile"] as String?)?.let { file(it) }
            storePassword = keystoreProperties["storePassword"] as String?
        }
    }
    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("release")
        }
    }
}
```

### Apple signing

With `APPLE_CERTIFICATE_P12_BASE64`, `APPLE_CERTIFICATE_PASSWORD` and
`APPLE_PROVISIONING_PROFILES_BASE64` (one base64 profile per line) the build imports the
certificate into a temporary keychain, installs the profiles and deletes the keychain at the end
of the job. Notarization needs `APP_STORE_CONNECT_KEY_ID`, `APP_STORE_CONNECT_ISSUER_ID` and
`APP_STORE_CONNECT_KEY_P8_BASE64`.

Secrets stored in an environment reach the build when `build.flutter.environment` names it.

## Native Dart binaries

`dart-compile.yml` compiles every executable of the `pubspec.yaml` files (or
`build.dart-compile.executables`) with `dart compile exe`, on a runner of each target's own
operating system and architecture:

| Target | Runner |
|---|---|
| `linux-x64`, `linux-arm64` | `ubuntu-latest`, `ubuntu-24.04-arm` |
| `macos-arm64`, `macos-x64` | `macos-latest`, `macos-15-intel` |
| `windows-x64`, `windows-arm64` | `windows-latest`, `windows-11-arm` |

Each binary runs once with `smoke-test-args` (`--version`), is packed as `<name>-<target>.zip`
(or `.tar.gz`) with a `.sha256` file and becomes the artifact `release-assets-<name>-<target>`,
which the GitHub release attaches together with a `checksums.txt` and provenance attestations.
