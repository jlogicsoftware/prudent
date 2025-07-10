# prudent

An Expense Tracker App built with Flutter.

## Prerequisites

- Flutter SDK (version 3.7.0 or later)
- Dart SDK (version 2.19.0 or later)
- Android Studio or Visual Studio Code for development
- An emulator or physical device for testing
- Java 17 (for Android development)
- Xcode (for iOS development, if applicable)
- Web browser (for web development)

### Installation

To install the necessary tools, follow these steps:
1. Install Flutter SDK:
   - Follow the instructions on the [Flutter installation page](https://flutter.dev/docs/get-started/install).
2. Install Dart SDK:
   - Dart is included with Flutter, so installing Flutter will also install Dart.
3. Set up your IDE:
   - For Android Studio, install the Flutter and Dart plugins.
   - For Visual Studio Code, install the Flutter and Dart extensions.

4. Set up an emulator or connect a physical device:
   - For Android, you can use Android Studio's AVD Manager to create an emulator.
   - For iOS, you can use Xcode to set up a simulator or connect a physical device.
   - For web, ensure you have a compatible browser installed.

## Getting Started

To run this project, you need to have Flutter installed on your machine. Follow the steps below to get started:

1. Clone the repository:
   ```bash
   git clone
   cd prudent
   flutter pub get
   ```
2. Install the required dependencies for your platform:
    - For Android, ensure you have Java 17 installed and set up. You might need to set up `org.gradle.java.home=<path-to-java-17>` in `android/gradle.properties`.
    - For iOS, ensure you have Xcode installed and set up.
3. Run the app:
   ```bash
   flutter run
   ```
4. To build the app for release:
   - For Android:
     ```bash
     flutter build apk --release
     ```
   - For iOS:
     ```bash
     flutter build ios --release
     ```
   - For web:
     ```bash
     flutter build web --release
     ```

## Run via VSCode

1. Open the project in Visual Studio Code.
2. Open `main.dart` in the `lib` directory.
3. Set the desired device in the bottom right corner of VSCode.
4. Press `F5` to run the app.
