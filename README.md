# prudent

An Expense Tracker App built with Flutter.

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
