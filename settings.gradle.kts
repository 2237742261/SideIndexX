pluginManagement {
    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}
dependencyResolutionManagement {
    repositoriesMode.set(RepositoriesMode.PREFER_SETTINGS)
    repositories {
        google()
        mavenCentral()
        maven("https://api.xposed.info/") { content { includeGroup("de.robv.android.xposed") } }
    }
}
rootProject.name = "ColorOSSideIndex"
include(":app")
