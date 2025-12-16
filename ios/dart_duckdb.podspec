#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html.
# Run `pod lib lint duckdb.podspec' to validate before publishing.
#
Pod::Spec.new do |s|
  s.name             = 'dart_duckdb'
  s.version          = File.read(File.join('..', 'pubspec.yaml')).match(/version:\s+(\d+\.\d+\.\d+)/)[1]
  s.summary          = 'A new flutter plugin project.'
  s.description      = <<-DESC
A new flutter plugin project.
                        DESC
  s.homepage         = 'https://tigereye.com'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Tigereye' => 'email@example.com' }
  s.source           = { :path => '.' }
  s.source_files     = 'Classes/**/*'
  s.dependency 'Flutter'

  s.platform = :ios, '11.0'
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES' }
  s.swift_version = '5.0'

  s.ios.vendored_frameworks = 'Libraries/release/DuckDB.xcframework'

  # Use a pre-install hook to check if the library exists
  s.prepare_command = <<-CMD
    mkdir -p Libraries/release
    
    # Check for local build first (from build-ios.sh)
    if [ -d "Frameworks/DuckDB.xcframework" ]; then
      echo "Found local DuckDB.xcframework in Frameworks/, using it..."
      rm -rf Libraries/release/DuckDB.xcframework
      cp -R Frameworks/DuckDB.xcframework Libraries/release/
    else
      # Fallback to download (OR fail if we strictly want local build for this demo)
      if [ ! -d "Libraries/release/DuckDB.xcframework" ]; then
        echo "No local build found. To use spatial features, you MUST run ./scripts/build-ios.sh first."
        # For now, we can try to download, but the artifact name might be different on release.
        # Assuming we eventually upload DuckDB.xcframework.zip
        
        # NOTE: Commenting out download for now to force local build verification as per user request
        # echo "Downloading DuckDB library..."
        # curl -L -o duckdb-framework-ios.zip "https://github.com/TigerEyeLabs/duckdb-dart/releases/download/v1.4.4/DuckDB.xcframework.zip"
        # unzip -o duckdb-framework-ios.zip -d Libraries/release/
        # rm duckdb-framework-ios.zip
        
        # Create a dummy to prevent pod install hard failure if just testing logic,
        # but really we want it to fail if missing.
        echo "Please run ./scripts/build-ios.sh from the project root."
        exit 1
      fi
    fi
  CMD
end
