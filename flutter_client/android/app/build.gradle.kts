import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Private signing material lives outside the checkout. Never fall back to debug signing.
val releaseProperties = Properties()
val signingPath = System.getenv("GCOLLIE_ANDROID_SIGNING_PROPERTIES")
if (!signingPath.isNullOrBlank()) {
    file(signingPath).inputStream().use { releaseProperties.load(it) }
}
val signingFields = listOf("storeFile", "storePassword", "keyAlias", "keyPassword")
val hasReleaseSigning = signingFields.all { !releaseProperties.getProperty(it).isNullOrBlank() }
if (gradle.startParameter.taskNames.any { it.contains("release", ignoreCase = true) } && !hasReleaseSigning) {
    throw GradleException("Release signing is required. Set GCOLLIE_ANDROID_SIGNING_PROPERTIES to a private properties file; see flutter_client/README.md.")
}

android {
    namespace = "dev.giggle.g_collie_flutter"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    sourceSets.getByName("main").jniLibs.srcDir("../../../android/lib")

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "dev.giggle.g_collie_flutter"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = 26
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (hasReleaseSigning) {
            create("production") {
                storeFile = file(releaseProperties.getProperty("storeFile"))
                storePassword = releaseProperties.getProperty("storePassword")
                keyAlias = releaseProperties.getProperty("keyAlias")
                keyPassword = releaseProperties.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            if (hasReleaseSigning) signingConfig = signingConfigs.getByName("production")
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
