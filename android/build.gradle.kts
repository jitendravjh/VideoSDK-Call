allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
subprojects {
    // flutter_ringtone_player ships compiled against android-33, but its
    // transitive androidx deps require compileSdk 34+, which fails the AAR
    // metadata check. Force every Android plugin module up to the app's
    // compileSdk. Registered before evaluationDependsOn so the afterEvaluate
    // hook is in place before the plugin's own build script evaluates.
    afterEvaluate {
        (extensions.findByName("android") as? com.android.build.gradle.BaseExtension)
            ?.compileSdkVersion(36)
    }
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
