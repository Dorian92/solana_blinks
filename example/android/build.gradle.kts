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
    // solana_mobile_client 0.1.2 still sets compileSdk 31, while the AndroidX
    // versions it pulls in require 34 or newer. Register this before
    // evaluationDependsOn so it is not added after the project is evaluated.
    afterEvaluate {
        val android = extensions.findByName("android") ?: return@afterEvaluate
        val setter = android.javaClass.methods.firstOrNull { method ->
            method.name == "compileSdkVersion" &&
                method.parameterCount == 1 &&
                method.parameterTypes[0] == Int::class.javaPrimitiveType
        }
        setter?.invoke(android, 36)
    }
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
