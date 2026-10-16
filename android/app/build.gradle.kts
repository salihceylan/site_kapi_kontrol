import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Yayın (release) imzası: android/key.properties (git'e GİRMEZ, bkz. android/.gitignore).
// Beklenen anahtarlar: storeFile, storePassword, keyAlias, keyPassword.
// Dosya yoksa geliştirici derlemeleri bozulmasın diye debug imzasına düşülür ve yüksek sesle uyarılır;
// bu şekilde imzalanan paket Google Play'e YÜKLENEMEZ. Ayrıntı: docs/YAYIN_HAZIRLIGI.md
val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties = Properties()
val hasReleaseKeystore = keystorePropertiesFile.exists()
if (hasReleaseKeystore) {
    keystorePropertiesFile.inputStream().use { keystoreProperties.load(it) }
}

android {
    // Kalıcı paket kimliği (mağaza kaydından sonra DEĞİŞTİRİLEMEZ).
    namespace = "tr.com.gudeteknoloji.siteyonetim"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        applicationId = "tr.com.gudeteknoloji.siteyonetim"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (hasReleaseKeystore) {
            create("release") {
                // Eksik/bozuk key.properties ile sessizce debug imzasına düşmek yerine açık hata ver:
                // yanlış imzalı bir paketin mağazaya gitmesi, derlemenin başarısız olmasından kötüdür.
                fun required(name: String): String =
                    keystoreProperties.getProperty(name)?.trim()?.takeIf { it.isNotEmpty() }
                        ?: throw GradleException("android/key.properties içinde '$name' eksik.")

                val storePath = required("storeFile")
                val store = file(storePath)
                if (!store.exists()) {
                    throw GradleException(
                        "android/key.properties içindeki storeFile bulunamadı: $storePath " +
                            "(anahtar dosyasını yedekten geri yükleyin; bkz. docs/YAYIN_HAZIRLIGI.md)."
                    )
                }
                storeFile = store
                storePassword = required("storePassword")
                keyAlias = required("keyAlias")
                keyPassword = required("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            // R8 küçültme/gizleme ve kaynak daraltma Flutter Gradle eklentisi tarafından açılır;
            // uygulamaya özgü kurallar app/proguard-rules.pro içindedir (eklenti otomatik ekler).
            if (hasReleaseKeystore) {
                signingConfig = signingConfigs.getByName("release")
            } else {
                signingConfig = signingConfigs.getByName("debug")
                logger.warn(
                    """
                    ===========================================================================
                    UYARI: android/key.properties bulunamadı. RELEASE paketi DEBUG anahtarıyla
                    imzalanıyor. Bu paket Google Play'e YÜKLENEMEZ ve yayına UYGUN DEĞİLDİR.
                    Yayın imzası için docs/YAYIN_HAZIRLIGI.md ("Anahtar yönetimi") bölümüne bakın.
                    ===========================================================================
                    """.trimIndent()
                )
            }
        }
    }
}

flutter {
    source = "../.."
}
