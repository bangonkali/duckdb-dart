# Spatial Demo for DuckDB Dart

This example demonstrates how to use the **spatial** extension with `duckdb-dart` in a Flutter application. It mirrors the functionality of the Capacitor DuckDB spatial demo.

## Prerequisites

-   Flutter SDK
-   DuckDB CLI (for database preparation)
-   Node.js (for data download script)

## Setup

1.  **Prepare the Database**
    The app expects a pre-populated database with Natural Earth data. Run the preparation script:

    ```bash
    cd scripts
    npm install # if package.json exists, otherwise just run:
    node prepare-demo-database.mjs
    ```
    *(Note: You might need to adjust the script to not rely on local `duckdb` node bindings if they aren't set up, or just use the CLI).*

    This will create `build/demo.duckdb`.

2.  **Move Database to Device**
    For this demo, we'll push the database to the device or embed it.
    *Option A (Embed):* Copy `build/demo.duckdb` to `assets/` and uncomment the loading logic in `lib/services/spatial_service.dart`.
    *Option B (Push - Android):* `adb push build/demo.duckdb /data/local/tmp/demo.duckdb` (User needs to adjust path in code).

    *For this specific walkthrough, the code currently creates a NEW empty DB if one is not found, and verifies `ST_Point` works. To see full data, follow Option A.*

3.  **Run the App**

    ```bash
    flutter pub get
    flutter run -d <device_id>
    ```

## Features Demonstrated

-   **Initialization**: Loading the `spatial` extension.
-   **Querying**: Executing `ST_` functions like `ST_Point`, `ST_AsText`.
-   **Map Integration**: Using `flutter_map` to visualize results (requires valid geometry data).

## Troubleshooting

-   **"Spatial extension not found"**: Ensure you are building `duckdb-dart` with the custom build scripts (`scripts/build-ios.sh` / `scripts/build-android.sh`) that include the spatial extension. The standard pub version might NOT have it.
-   **Linker Errors**: Check that the `dart_duckdb` dependency is pointing to your local path where you ran the build scripts.
