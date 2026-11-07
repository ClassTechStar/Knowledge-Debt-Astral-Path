plugins {
    id("com.android.application")
}

android {
    namespace = "com.astralpath.nativeapp"
    compileSdk = 35
    defaultConfig {
        applicationId = "com.astralpath.nativeapp"
        minSdk = 26
        targetSdk = 35
        versionCode = 101
        versionName = "2.6.0"
    }
    buildTypes {
        release {
            isMinifyEnabled = false
            // 原生端 v1 先出 debug 签名的可安装包；正式上架签名沿用 Native 壳的
            // 环境变量方案（ASTRALPATH_KEYSTORE 四件套），未配置时回退 debug 签名
            signingConfig = signingConfigs.getByName("debug")
        }
    }
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
}

dependencies {
    implementation("androidx.core:core-ktx:1.15.0")
    implementation("androidx.appcompat:appcompat:1.7.0")
    testImplementation("junit:junit:4.13.2")
}
