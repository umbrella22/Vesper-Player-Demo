pluginManagement {
    run {
        val localGradlePropertiesFile = file("gradle-local.properties")
        if (localGradlePropertiesFile.isFile) {
            val localGradleProperties = java.util.Properties()
            localGradlePropertiesFile
                .inputStream()
                .use(localGradleProperties::load)
            localGradleProperties.forEach { key, value ->
                val propertyName = key.toString()
                val propertyValue = value.toString()
                if (propertyValue.isEmpty()) {
                    System.clearProperty(propertyName)
                } else {
                    System.setProperty(propertyName, propertyValue)
                }
            }
        }
    }

    val flutterSdkPath =
        run {
            val properties = java.util.Properties()
            file("local.properties").inputStream().use { properties.load(it) }
            val flutterSdkPath = properties.getProperty("flutter.sdk")
            require(flutterSdkPath != null) { "flutter.sdk not set in local.properties" }
            flutterSdkPath
        }

    includeBuild("$flutterSdkPath/packages/flutter_tools/gradle")

    resolutionStrategy {
        eachPlugin {
            when (requested.id.id) {
                "com.android.application",
                "com.android.library",
                "com.android.dynamic-feature",
                "com.android.test", ->
                    useModule("com.android.tools.build:gradle:${requested.version}")
            }
        }
    }

    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}

plugins {
    id("dev.flutter.flutter-plugin-loader") version "1.0.0"
    id("com.android.application") version "9.1.0" apply false
    id("com.android.library") version "9.1.0" apply false
    id("org.jetbrains.kotlin.android") version "2.4.10" apply false
}

include(":app")
