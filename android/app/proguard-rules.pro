# Preserve GSON TypeToken generic signatures (required by flutter_local_notifications)
# See: https://github.com/MaikuB/flutter_local_notifications/issues/2392
-keep,allowobfuscation,allowshrinking class com.google.gson.reflect.TypeToken
-keep,allowobfuscation,allowshrinking class * extends com.google.gson.reflect.TypeToken

# kotlinx.coroutines internal class referenced by shared_preferences plugin (Flutter 3.27+).
-dontwarn kotlin.coroutines.jvm.internal.SpillingKt
-keep class kotlin.coroutines.jvm.internal.** { *; }

# Dolphin-Core (gomobile libbox) — these classes are bound to Go via JNI and are
# invoked by name from native code (both Java→Go and Go→Java callbacks). R8 must
# not strip or rename them, or the VPN core crashes at runtime.
-keep class com.smartdolphin.libbox.** { *; }
-keep class go.** { *; }
-dontwarn com.smartdolphin.libbox.**
-dontwarn go.**
