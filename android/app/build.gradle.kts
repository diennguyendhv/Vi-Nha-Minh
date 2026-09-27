import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.vinhamimh.vi_nha_minh"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.vinhamimh.vi_nha_minh"
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

    // P5: mỗi môi trường = applicationId riêng (sandbox riêng). PROD giữ nguyên id
    // đã phát hành/đang cài trên máy thật; KHÔNG đổi.
    flavorDimensions += "env"
    productFlavors {
        create("dev") {
            dimension = "env"
            applicationIdSuffix = ".dev"
        }
        create("pilot") {
            dimension = "env"
            applicationIdSuffix = ".pilot"
        }
        create("prod") {
            dimension = "env"
        }
    }

    // Khoá ký release nằm NGOÀI repo (không bao giờ commit). Đường dẫn file
    // key.properties: biến môi trường HW_RELEASE_KEY_PROPERTIES, mặc định thư mục khoá
    // của máy phát hành. Thiếu file ⇒ bản release KHÔNG được ký (build fail), không
    // bao giờ lặng lẽ ký bằng debug key.
    val releaseKeyFile = file(
        System.getenv("HW_RELEASE_KEY_PROPERTIES")
            ?: "C:/Users/Admin/Documents/ViNhaMinh_keys/key.properties"
    )
    val releaseKey = Properties().apply {
        if (releaseKeyFile.exists()) releaseKeyFile.inputStream().use { load(it) }
    }
    signingConfigs {
        if (releaseKeyFile.exists()) {
            create("release") {
                storeFile = file(releaseKey.getProperty("storeFile"))
                storePassword = releaseKey.getProperty("storePassword")
                keyAlias = releaseKey.getProperty("keyAlias")
                keyPassword = releaseKey.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.findByName("release")
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
