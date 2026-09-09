import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// The release signing key, if this machine has one.
//
// android/key.properties is gitignored and holds the passwords; the keystore
// it points at never enters the repository. CI writes both from secrets before
// building, so there is one code path rather than a separate CI branch to get
// wrong.
//
// Absent, the release build falls back to the debug key. That keeps
// `flutter build apk --release` working for anyone without the keystore — a
// fresh clone, a contributor — rather than failing on a secret they cannot
// have. The cost is that an unsigned-by-us build is possible, which is why
// the release workflow refuses to publish one.
val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties = Properties().apply {
    if (keystorePropertiesFile.exists()) {
        FileInputStream(keystorePropertiesFile).use { load(it) }
    }
}

android {
    namespace = "io.github.arc084.recipe_book"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "io.github.arc084.recipe_book"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        // Only declared when there is a key to declare. A config holding nulls
        // would fail the build for everyone who does not have the keystore.
        if (keystorePropertiesFile.exists()) {
            create("release") {
                storeFile = file(keystoreProperties.getProperty("storeFile"))
                storePassword = keystoreProperties.getProperty("storePassword")
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            // The real key where there is one, the debug key otherwise. An
            // APK update must be signed with the same key as the install it
            // replaces, so which of these signed a build decides whether it
            // can ever update anything.
            signingConfig =
                signingConfigs.findByName("release")
                    ?: signingConfigs.getByName("debug")
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

dependencies {
    // FileProvider, for handing a downloaded APK to the system installer.
    implementation("androidx.core:core-ktx:1.13.1")
}
