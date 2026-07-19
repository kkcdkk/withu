import java.util.Properties

plugins {
    alias(libs.plugins.android.application)
    alias(libs.plugins.kotlin.android)
    alias(libs.plugins.kotlin.compose)
    alias(libs.plugins.kotlin.serialization)
}

// local.properties 의 WITHU_API_TOKEN → BuildConfig (커밋 제외 — iOS APIConfig 와 같은 정책)
val localProps = Properties().apply {
    val f = rootProject.file("local.properties")
    if (f.exists()) f.inputStream().use { load(it) }
}

android {
    namespace = "com.seoyoung.withu"
    compileSdk = 35

    defaultConfig {
        applicationId = "com.seoyoung.withu"
        minSdk = 28
        targetSdk = 35
        versionCode = 1
        versionName = "0.1.0"
        buildConfigField("String", "WITHU_API_TOKEN",
            "\"${localProps.getProperty("WITHU_API_TOKEN", "")}\"")
    }

    // 릴리스 서명 (업로드 키) — local.properties 에서 읽음(커밋 제외). keystore 없으면 미서명 빌드.
    signingConfigs {
        val storePath = localProps.getProperty("WITHU_UPLOAD_STORE_FILE")
        if (storePath != null && rootProject.file(storePath).exists()) {
            create("release") {
                storeFile = rootProject.file(storePath)
                storePassword = localProps.getProperty("WITHU_UPLOAD_STORE_PASSWORD")
                keyAlias = localProps.getProperty("WITHU_UPLOAD_KEY_ALIAS")
                keyPassword = localProps.getProperty("WITHU_UPLOAD_KEY_PASSWORD")
            }
        }
    }

    buildTypes {
        release {
            isMinifyEnabled = false
            signingConfigs.findByName("release")?.let { signingConfig = it }
        }
    }
    buildFeatures {
        compose = true
        buildConfig = true
    }
    testOptions {
        unitTests {
            // Robolectric — CharacterImageStore 파일/비트맵 테스트에 실제 리소스/Context 필요
            isIncludeAndroidResources = true
            isReturnDefaultValues = true
        }
    }
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    kotlinOptions {
        jvmTarget = "17"
    }
}

dependencies {
    implementation(libs.androidx.core.ktx)
    implementation(libs.androidx.activity.compose)
    implementation(platform(libs.androidx.compose.bom))
    implementation(libs.androidx.compose.ui)
    implementation(libs.androidx.compose.material3)
    implementation(libs.androidx.compose.icons.extended)
    implementation(libs.androidx.compose.preview)
    implementation(libs.androidx.lifecycle.runtime)
    implementation(libs.androidx.lifecycle.viewmodel.compose)
    implementation(libs.androidx.navigation.compose)
    // 위젯(Glance)·배치 큐(WorkManager)·건강(Health Connect)·카메라·위치 — 00-PLAN §4 F1 확정 목록
    implementation(libs.androidx.glance.appwidget)
    implementation(libs.androidx.work.runtime)
    implementation(libs.androidx.health.connect)
    implementation(libs.androidx.camera.core)
    implementation(libs.androidx.camera.camera2)
    implementation(libs.androidx.camera.lifecycle)
    implementation(libs.androidx.camera.view)
    implementation(libs.androidx.concurrent.futures.ktx)
    implementation(libs.androidx.exifinterface)
    implementation(libs.play.services.location)
    // 폰→워치 상태·이미지 push (Data Layer) — iOS ConnectivityManager 대응
    implementation(libs.play.services.wearable)
    implementation(libs.okhttp)
    implementation(libs.kotlinx.serialization.json)
    debugImplementation(libs.androidx.compose.tooling)
    testImplementation(libs.junit)
    testImplementation(libs.robolectric)
    testImplementation(libs.androidx.test.core)
}
