plugins {
    id("com.android.library")
    id("kotlin-android")
}

android {
    namespace = "net.touchcapture.qr.flutterqr"
    compileSdk = 33

    defaultConfig {
        minSdk = 20
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }
}