import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Load the local, uncommitted release keystore config when it is present. A
// fresh checkout has no android/key.properties, so this block is skipped and
// the release build falls back to the debug signing config below. The release
// config is only considered usable when every required key is present and
// non-blank, so a half-filled secrets file degrades to the fallback instead of
// failing configuration for all build types.
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    FileInputStream(keystorePropertiesFile).use { keystoreProperties.load(it) }
}

fun String?.isNotBlankProperty() = !this.isNullOrBlank()

val storeFilePath: String? = keystoreProperties.getProperty("storeFile")
val keyAliasValue: String? = keystoreProperties.getProperty("keyAlias")
val keyPasswordValue: String? = keystoreProperties.getProperty("keyPassword")
val storePasswordValue: String? = keystoreProperties.getProperty("storePassword")

val hasReleaseKeystore = storeFilePath.isNotBlankProperty() &&
    keyAliasValue.isNotBlankProperty() &&
    keyPasswordValue.isNotBlankProperty() &&
    storePasswordValue.isNotBlankProperty()
if (keystorePropertiesFile.exists() && !hasReleaseKeystore) {
    logger.warn(
        "android/key.properties is missing one or more of storeFile/keyAlias/" +
            "keyPassword/storePassword; falling back to debug signing.",
    )
}

android {
    namespace = "com.hadi.personalos"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.hadi.personalos"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (hasReleaseKeystore) {
            create("release") {
                keyAlias = keyAliasValue
                keyPassword = keyPasswordValue
                storeFile = storeFilePath?.let { file(it) }
                storePassword = storePasswordValue
            }
        }
    }

    buildTypes {
        release {
            // Sign with the local release keystore when android/key.properties
            // exists; otherwise fall back to the debug signing config so a fresh
            // checkout still builds (personal sideload only).
            signingConfig = if (hasReleaseKeystore) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
