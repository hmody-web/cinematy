# Flutter and media_kit keep rules are supplied by their own dependencies.
-keep class io.flutter.** { *; }
-dontwarn io.flutter.embedding.**

# Release hardening: remove app-level Android Log calls from optimized builds.
-assumenosideeffects class android.util.Log {
    public static *** v(...);
    public static *** d(...);
    public static *** i(...);
    public static *** w(...);
    public static *** e(...);
}
