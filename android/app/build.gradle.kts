import java.util.Properties
import java.io.FileInputStream
import java.net.URI
import java.util.Base64

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
    // fork: свой Firebase оператора для FCM-будильника (PLAN S12). Плагин
    // применяется ниже, только если при сборке есть google-services.json.
    id("com.google.gms.google-services") apply false
}

// ── fork: Tethered ── (docs/history/TOUCHPOINTS.md)
// Своя идентичность, чтобы форк ставился рядом с приложением апстрима и не
// перехватывал его ссылки. namespace (пакет Kotlin-кода) не меняем: это
// внутреннее имя, и смена потянула бы перенос всех исходников.
val forkApplicationId = "io.github.m0nstrum.tethered"
// Хост App Links для приглашений — из тех же --dart-define, что у Dart
// (lib/fork/config/endpoints.dart): SITE_URL, иначе PB_URL. Flutter передаёт
// их в Gradle свойством dart-defines (base64 "KEY=VALUE" через запятую).
val forkDartDefines: Map<String, String> =
    (project.findProperty("dart-defines") as String?).orEmpty()
        .split(",").filter { it.isNotBlank() }
        .map { String(Base64.getDecoder().decode(it)) }
        .filter { "=" in it }
        .associate { it.substringBefore("=") to it.substringAfter("=") }
// .invalid (RFC 2606) не резолвится никогда: сборка без адреса сервера не
// перехватывает ничьи ссылки (а стартовать её не даст Endpoints).
val forkInviteHost: String = listOf("SITE_URL", "PB_URL")
    .mapNotNull { forkDartDefines[it]?.takeIf { v -> v.isNotBlank() } }
    .firstOrNull()
    ?.let { URI(it).host }
    ?: "unconfigured.invalid"
val forkManifestPlaceholders = mapOf(
    "appLabel" to "Tethered",
    "appScheme" to "tethered",
    "inviteHost" to forkInviteHost,
)

// fork: google-services.json кладёт сборка (fork-release.yml), в репозитории
// его нет. Без него FirebaseApp не поднимается, и пуши идут через сокет.
// Пустой файл тоже «нет»: воркфлоу апстрима пишет его без секрета.
if (file("google-services.json").let { it.exists() && it.length() > 0 }) {
    apply(plugin = "com.google.gms.google-services")
}

val keyPropertiesFile = rootProject.file("key.properties")
val keyProperties = Properties()
if (keyPropertiesFile.exists()) {
    keyProperties.load(FileInputStream(keyPropertiesFile))
}

android {
    namespace = "com.togetherly.love"
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

    signingConfigs {
        if (keyPropertiesFile.exists()) {
            create("release") {
                keyAlias = keyProperties["keyAlias"] as String
                keyPassword = keyProperties["keyPassword"] as String
                storeFile = file(keyProperties["storeFile"] as String)
                storePassword = keyProperties["storePassword"] as String
            }
        }
    }

    // Нативные библиотеки в APK по умолчанию лежат НЕСЖАТЫМИ: 47,8 МБ у arm64,
    // из них libapp 18,3, WebRTC 11,5 и движок Flutter 10,8. Deflate ужимает их
    // до 21,1 МБ (проверено на живых файлах сборки 1.24.0), то есть загрузка
    // падает вдвое — а APK у нас скачивают целиком и по мобильному интернету:
    // самообновление тянет его с релизов GitHub, RuStore тоже отдаёт файл.
    //
    // Расплата — распаковка на устройстве: система кладёт библиотеки ещё и в
    // /data, места занимает больше, установка чуть дольше. Для AAB это чистый
    // вред: Play жмёт при доставке сам, а несжатые .so на устройстве не дублирует
    // — поэтому у сборки бандла флаг снимается. Задачу отличаем по её имени,
    // другого способа увидеть тип выхода в AGP нет.
    val buildingBundle = gradle.startParameter.taskNames.any {
        it.contains("bundle", ignoreCase = true)
    }
    packaging {
        jniLibs {
            useLegacyPackaging = !buildingBundle
        }
    }

    defaultConfig {
        applicationId = forkApplicationId
        manifestPlaceholders += forkManifestPlaceholders
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        // Тесты натива на эмуляторе CI (android-sound-clip.yml)
        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
    }

    buildTypes {
        debug {
        }
        release {
            signingConfig = if (keyPropertiesFile.exists())
                signingConfigs.getByName("release")
            else
                signingConfigs.getByName("debug")

            // Enable R8 code shrinking with Firebase-safe ProGuard rules
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
    }
}

// fork: ресурсы форка (иконка) перекрывают одноимённые из src/main.
// Build-type source set стоит выше main, поэтому дубликатов не будет, а PNG
// апстрима остаются нетронутыми. Генерирует их tool/fork/gen_icon.py.
android.sourceSets.matching { it.name in setOf("debug", "profile", "release") }
    .configureEach { res.srcDir("src/fork/res") }

flutter {
    source = "../.."
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")

    // Пуши. Свой foreground-сервис держал сокет и стоил строки в шторке у
    // каждого плюс шести часов в сутки лимита Android 14 на dataSync — с FCM
    // сокет держит система. Версии тянет BOM, руками их не прописывать.
    // fork: firebase-messaging — только будильник без содержимого (PLAN S12,
    // ForkFcmService.kt); без google-services.json он спит. play-services-base
    // не нужен: сервисы Google проверяются по пакету.
    implementation(platform("com.google.firebase:firebase-bom:33.7.0"))
    implementation("com.google.firebase:firebase-messaging")

    // EXIF в снимки, сохраняемые в галерею (GallerySaver.kt): дата и место
    // воспоминания. Встроенный в систему ExifInterface на старых Android WebP
    // не пишет, а четыре кадра из пяти в Togetherly — WebP.
    implementation("androidx.exifinterface:exifinterface:1.4.1")

    // Разовая задача пакета workmanager из пуша и виджета карты
    // (WidgetRefreshWake.kt). Плагин тянет work-runtime как implementation, и
    // приложению он без этой строки не виден. Версия — как у плагина.
    implementation("androidx.work:work-runtime:2.10.2")

    // Проверка вырезки звука на эмуляторе CI: в приложение не попадает.
    // Версии те же, что уже тянет integration_test: тестовый APK обязан
    // совпадать с приложением, и 1.6.2 падала на строгом 1.3.0.
    androidTestImplementation("androidx.test:runner:1.3.0")
    androidTestImplementation("androidx.test.ext:junit:1.1.2")

    // Google Play Billing тянет плагин in_app_purchase_android (0.5.x = billing 8.x).
    // Свою версию сюда не прописывать: Play отклоняет обновления на библиотеке ниже 8.
}

// fork: native features kept outside the upstream source directory.
android.sourceSets.getByName("main").java.srcDir("src/fork/kotlin")
