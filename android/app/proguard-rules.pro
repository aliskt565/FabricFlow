# Flutter
-keep class io.flutter.** { *; }
-keep class com.google.firebase.** { *; }

# Play Core — missing classes fix
-dontwarn com.google.android.play.core.**
-keep class com.google.android.play.core.** { *; }

# Firebase
-keep class com.google.android.gms.** { *; }
-dontwarn com.google.android.gms.**

# Kotlin
-dontwarn kotlin.**
-keep class kotlin.** { *; }