cmake_minimum_required(VERSION 3.16)
project(DefenderOfTheCrown VERSION 0.1.0 LANGUAGES C)

set(CMAKE_C_STANDARD 11)
set(CMAKE_C_STANDARD_REQUIRED ON)

find_package(SDL3 REQUIRED CONFIG COMPONENTS SDL3)

add_executable(DefenderOfTheCrown MACOSX_BUNDLE
    src/main.c
    src/dat.c
    src/assets.c
    src/gfx.c
    src/sound.c
    src/sys.c
    src/game.c
    src/month.c
    src/war.c
    src/ai.c
    src/conquest.c
    src/raid.c
    src/gamelog.c
)
target_link_libraries(DefenderOfTheCrown PRIVATE SDL3::SDL3)

if(MSVC)
    target_compile_options(DefenderOfTheCrown PRIVATE /W4)
else()
    target_compile_options(DefenderOfTheCrown PRIVATE -Wall -Wextra)
endif()

set_target_properties(DefenderOfTheCrown PROPERTIES
    MACOSX_BUNDLE_BUNDLE_NAME "Defender of the Crown"
    MACOSX_BUNDLE_GUI_IDENTIFIER "org.defenderofthecrown.remake"
    MACOSX_BUNDLE_SHORT_VERSION_STRING "${PROJECT_VERSION}"
    MACOSX_BUNDLE_BUNDLE_VERSION "${PROJECT_VERSION}"
)
