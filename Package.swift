// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "Darktime",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "darktime", targets: ["CalendarBridge"])
    ],
    targets: [
        .executableTarget(
            name: "CalendarBridge",
            exclude: ["Info.plist"],
            linkerSettings: [
                .unsafeFlags([
                    "-Xlinker", "-sectcreate",
                    "-Xlinker", "__TEXT",
                    "-Xlinker", "__info_plist",
                    "-Xlinker", "Sources/CalendarBridge/Info.plist"
                ])
            ]
        )
    ]
)
