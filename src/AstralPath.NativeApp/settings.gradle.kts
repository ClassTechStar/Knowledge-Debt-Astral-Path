// 知债：星穹学途 · 原生安卓端（Jetpack View 体系 + 自绘图谱），独立 Gradle 工程
// 与 src/AstralPath.Native（Kotlin WebView 壳）并存：壳版加载单文件产物，本模块为无 WebView 的原生实现。
pluginManagement {
    repositories { google(); mavenCentral(); gradlePluginPortal() }
    plugins {
        id("com.android.application") version "9.0.0"
    }
}
dependencyResolutionManagement {
    repositories { google(); mavenCentral() }
}
rootProject.name = "AstralPathNativeApp"
include(":app")
