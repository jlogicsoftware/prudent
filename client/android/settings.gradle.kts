pluginManagement {
    val flutterSdkPath = run {
        val properties = java.util.Properties()
        file("local.properties").inputStream().use { properties.load(it) }
        val flutterSdkPath = properties.getProperty("flutter.sdk")
        require(flutterSdkPath != null) { "flutter.sdk not set in local.properties" }
        flutterSdkPath
    }

    includeBuild("$flutterSdkPath/packages/flutter_tools/gradle")

    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}

plugins {
    id("dev.flutter.flutter-plugin-loader") version "1.0.0"
    // These three move together and cannot be bumped independently: AGP 9.x requires Gradle 9.x,
    // and AGP 9 requires KGP 2.x.
    //
    // The Gradle version is the one that matters for which JDK can run the build, and the reason is
    // easy to get wrong. Gradle compiles build.gradle.kts with the Kotlin compiler embedded in the
    // Gradle DISTRIBUTION — org.gradle.kotlin.dsl.support.KotlinCompiler — which is not swappable,
    // overridable or pinnable. The kotlin.android version below governs only the app's own Kotlin
    // sources and has no bearing on it. Under Gradle 8.x that embedded compiler cannot parse a
    // two-digit Java feature version and dies with `IllegalArgumentException: 25.0.3`, which Gradle
    // surfaces as a build failure whose entire message is "25.0.3" — naming neither Java, nor
    // Kotlin, nor a version being unsupported. Java 25 support arrives in Gradle 9.1.
    //
    // After changing the distribution, kill the daemon: one started under the old distribution
    // survives a wrapper change and keeps serving the old Gradle.
    id("com.android.application") version "9.0.1" apply false
    id("org.jetbrains.kotlin.android") version "2.3.20" apply false
}

include(":app")
