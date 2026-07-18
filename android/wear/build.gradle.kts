plugins {
    alias(libs.plugins.android.application)
    alias(libs.plugins.kotlin.android)
    alias(libs.plugins.kotlin.compose)
}

// Wear OS 컴패니언 앱 — iOS 'withu Watch App' 대응.
// 폰이 Data Layer 로 push 한 상태/캐릭터 이미지를 받아 Tile(위젯)·화면에 표시만 한다.
// 건강데이터 재계산 없음(폰이 두뇌). 결제/생성/카메라 없음.
android {
    namespace = "com.seoyoung.withu.wear"
    compileSdk = 35

    defaultConfig {
        // applicationId 는 폰과 동일해야 Data Layer 페어링이 된다 (같은 앱의 워치 짝).
        applicationId = "com.seoyoung.withu"
        minSdk = 30
        targetSdk = 35
        versionCode = 1
        versionName = "0.1.0"
    }

    buildTypes {
        release {
            isMinifyEnabled = false
        }
    }
    buildFeatures {
        compose = true
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
    implementation(libs.androidx.compose.preview)
    // Wear 전용 Compose (Material)
    implementation(libs.androidx.wear.compose.material)
    implementation(libs.androidx.wear.compose.foundation)
    // Tile(위젯) — protolayout
    implementation(libs.androidx.wear.tiles)
    implementation(libs.androidx.wear.protolayout)
    implementation(libs.androidx.wear.protolayout.material)
    // 컴플리케이션(시계 페이스)
    implementation(libs.androidx.wear.complications.datasource)
    implementation(libs.guava)
    // 폰↔워치 Data Layer
    implementation(libs.play.services.wearable)
    debugImplementation(libs.androidx.compose.tooling)
}
