plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.jlogicsoftware.prudent"
    compileSdk = flutter.compileSdkVersion
    // Delegated, never a literal — and Flutter itself walks you into the literal. When a plugin
    // needs a newer NDK than the pin, the tool prints "use the highest Android NDK version" and
    // hands you `ndkVersion = "<version>"` interpolated from whatever your plugin set happens to
    // need today. Taking that re-pins to a snapshot of the current dependency graph, and the next
    // plugin that wants newer — or the next Flutter SDK bump — reopens the identical failure.
    //
    // `flutter.ndkVersion` tracks the AGP-default NDK for whatever Flutter is in use (it is a
    // constant in the SDK's own FlutterExtension), which is the version the plugin ecosystem
    // converges on anyway. The previous literal here was 27.0.12077973, the AGP 8.x-era default:
    // drift from the same stale template as the Gradle wrapper, and invisible until the toolchain
    // upgrade got far enough to resolve plugin projects at all.
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.jlogicsoftware.prudent"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

// 17, and NOT raised to match whatever JDK runs the build. This is the bytecode level of the
// shipped APK, which Android's desugaring surface pins; it is independent of the build JDK.
// `compilerOptions`, not the old `kotlinOptions` block, which KGP 2.x removed.
kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
