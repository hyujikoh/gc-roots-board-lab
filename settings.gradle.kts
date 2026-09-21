// JDK 21 이 로컬에 없으면 toolchain 이 자동으로 내려받도록 (Gradle 이 실행되는 JDK 는 17 이어도 된다)
plugins {
    id("org.gradle.toolchains.foojay-resolver-convention") version "1.0.0"
}

rootProject.name = "gc-roots-board-lab"
include("app")
