cmake_minimum_required(VERSION 3.16)
project(veya_ui LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

find_package(Qt6 REQUIRED COMPONENTS Core Gui Qml Quick WebSockets Svg)

qt_standard_project_setup()

qt_add_executable(veya_ui
    src/main.cpp
)

qt_add_qml_module(veya_ui
    URI Veya
    VERSION 1.0
    QML_FILES
        qml/Main.qml
        qml/Home.qml
        qml/Drive.qml
        qml/Diagnostic.qml
        qml/DevDiagnostic.qml
        qml/ReportScreen.qml
        qml/LiveSessionScreen.qml
        qml/SettingsScreen.qml
        qml/WifiManager.qml
        qml/providers/VehicleDataProvider.qml
        qml/providers/UserProfile.qml
        qml/components/GaugeRing.qml
        qml/components/StatusIconBar.qml
        qml/components/CarSilhouette.qml
        qml/components/GearIndicator.qml
        qml/components/DemoBadge.qml
        qml/components/SpeedBar.qml
        qml/components/AnimatedRoad.qml
        qml/components/WarningTelltales.qml
        qml/components/OnScreenKeyboard.qml
        qml/onboarding/WelcomeOnboarding.qml
        qml/onboarding/DriverOnboarding.qml
        qml/onboarding/CarOnboarding.qml

    RESOURCES
        qml/qmldir
        qml/assets/icon_music.svg
        qml/assets/icon_menu.svg
        qml/assets/icon_car.svg
        qml/assets/icon_phone.svg
        qml/assets/icon_settings.svg
        qml/assets/icon_headlights.svg
        qml/assets/car_silhouette.png
        qml/assets/car_silhouette.svg
)

target_link_libraries(veya_ui PRIVATE Qt6::Core Qt6::Gui Qt6::Qml Qt6::Quick Qt6::WebSockets Qt6::Svg)
qt_import_plugins(veya_ui INCLUDE Qt6::QSvgPlugin)
