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
    src/tourney.c
    src/gamelog.c
    src/icon.c
)
target_link_libraries(DefenderOfTheCrown PRIVATE SDL3::SDL3)

if(MSVC)
    target_compile_options(DefenderOfTheCrown PRIVATE /W4)
else()
    target_compile_options(DefenderOfTheCrown PRIVATE -Wall -Wextra)
endif()

# The app icon is drawn at build time from your own copy of the game (the
# title picture), so no original artwork is kept in the repository. Set
# DOTC_GAME_DIR to the folder with GAME.DAT (or with ega/GAME.DAT), or keep the
# files in ../Original. Without them the app has no icon in Finder (the game
# still sets its window icon when it runs).
set(DOTC_GAME_DIR "" CACHE PATH "Folder with your original game files (for the app icon)")
if(NOT DOTC_GAME_DIR AND EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/../Original/ega/GAME.DAT")
    set(DOTC_GAME_DIR "${CMAKE_CURRENT_SOURCE_DIR}/../Original")
endif()
if(APPLE AND DOTC_GAME_DIR)
    add_executable(make_icon tools/make_icon.c src/icon.c src/assets.c src/dat.c)
    target_link_libraries(make_icon PRIVATE SDL3::SDL3)
    set(DOTC_ICONSET "${CMAKE_CURRENT_BINARY_DIR}/AppIcon.iconset")
    set(DOTC_ICNS "${CMAKE_CURRENT_BINARY_DIR}/AppIcon.icns")
    add_custom_command(OUTPUT "${DOTC_ICNS}"
        COMMAND "${CMAKE_COMMAND}" -E remove_directory "${DOTC_ICONSET}"
        COMMAND make_icon "${DOTC_GAME_DIR}" "${DOTC_ICONSET}"
        COMMAND iconutil -c icns "${DOTC_ICONSET}" -o "${DOTC_ICNS}"
        DEPENDS make_icon
        COMMENT "Drawing the app icon from ${DOTC_GAME_DIR}"
        VERBATIM)
    target_sources(DefenderOfTheCrown PRIVATE "${DOTC_ICNS}")
    set_source_files_properties("${DOTC_ICNS}" PROPERTIES MACOSX_PACKAGE_LOCATION Resources)
    set_target_properties(DefenderOfTheCrown PROPERTIES MACOSX_BUNDLE_ICON_FILE AppIcon)
endif()

set_target_properties(DefenderOfTheCrown PROPERTIES
    MACOSX_BUNDLE_BUNDLE_NAME "Defender of the Crown"
    MACOSX_BUNDLE_GUI_IDENTIFIER "org.defenderofthecrown.remake"
    MACOSX_BUNDLE_SHORT_VERSION_STRING "${PROJECT_VERSION}"
    MACOSX_BUNDLE_BUNDLE_VERSION "${PROJECT_VERSION}"
)
