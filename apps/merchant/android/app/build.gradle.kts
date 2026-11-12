plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "iq.wasel.wasel_merchant"
    // 37: مطلوب لمكتبة الإشعارات (androidx.core 1.19). ما يغيّر أقل إصدار أندرويد مدعوم (minSdk).
    compileSdk = maxOf(flutter.compileSdkVersion, 37)
    ndkVersion = flutter.ndkVersion

    compileOptions {
        // مطلوب لمكتبة الإشعارات (flutter_local_notifications)
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
                applicationId = "iq.wasel.merchant"
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

    // التوقيع: مفتاح ثابت من GitHub Secrets حتى تنثبّت التحديثات فوق النسخة القديمة.
    // بدونه يُستخدم مفتاح debug (للتجربة فقط).
    val keystorePath = System.getenv("WASEL_KEYSTORE_PATH")
    val keystorePass = System.getenv("WASEL_KEYSTORE_PASSWORD")
    val hasReleaseKey = !keystorePath.isNullOrEmpty() && !keystorePass.isNullOrEmpty() && file(keystorePath).exists()
    signingConfigs {
        create("release") {
            if (hasReleaseKey) {
                storeFile = file(keystorePath!!)
                storePassword = keystorePass
                keyAlias = System.getenv("WASEL_KEY_ALIAS") ?: "wasel"
                keyPassword = keystorePass
            }
        }
    }

    // فحص lint أثناء بناء الإصدار يتعطل مع بعض المكتبات؛ الكود يُفحص بـ flutter analyze بالـ CI
    lint {
        checkReleaseBuilds = false
        abortOnError = false
    }

    buildTypes {
        release {
            signingConfig = if (hasReleaseKey) signingConfigs.getByName("release") else signingConfigs.getByName("debug")
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
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}
