import java.util.Properties

plugins {
    id("com.android.application")
    // START: FlutterFire Configuration
    id("com.google.gms.google-services")
    // END: FlutterFire Configuration
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(keystorePropertiesFile.inputStream())
}

android {
    namespace = "com.example.metadata"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        isCoreLibraryDesugaringEnabled = true
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        // The identity Google Play, Firebase and the OS use for this app.
        // Deliberately not the same as `namespace` above, which stays on the
        // original package so the Kotlin sources and the manifest's
        // ".MainActivity" reference don't have to move; the two are
        // independent and only this one is externally visible.
        applicationId = "za.co.contextidentity.metadata"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("release") {
            if (keystorePropertiesFile.exists()) {
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
                storeFile = file(keystoreProperties["storeFile"] as String)
                storePassword = keystoreProperties["storePassword"] as String
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (keystorePropertiesFile.exists()) {
                signingConfigs.getByName("release")
            } else {
                // Fall back to debug keys so `flutter run --release` still works
                // before a release keystore/key.properties has been set up.
                signingConfigs.getByName("debug")
            }
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
    implementation(platform("com.google.firebase:firebase-bom:34.16.0"))
    implementation("com.google.firebase:firebase-analytics")
    // Needed at compile time by VoipMessagingService, which extends the
    // firebase_messaging plugin's FirebaseMessagingService to post the
    // full-screen incoming-call notification natively. The Flutter plugin
    // brings this in at runtime but does not expose it on the app module's
    // compile classpath.
    implementation("com.google.firebase:firebase-messaging")
    // ActivityCompat/ContextCompat/NotificationCompat/RoleManager for the
    // incoming-call screening/notification bridge (CallScreeningServiceImpl,
    // CallPermissions, NativeCallNotification).
    implementation("androidx.core:core-ktx:1.13.1")
}
