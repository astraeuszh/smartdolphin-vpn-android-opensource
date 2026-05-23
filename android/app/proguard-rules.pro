# Preserve GSON TypeToken generic signatures (required by flutter_local_notifications)
# See: https://github.com/MaikuB/flutter_local_notifications/issues/2392
-keep,allowobfuscation,allowshrinking class com.google.gson.reflect.TypeToken
-keep,allowobfuscation,allowshrinking class * extends com.google.gson.reflect.TypeToken

# kotlinx.coroutines internal class referenced by shared_preferences plugin (Flutter 3.27+).
-dontwarn kotlin.coroutines.jvm.internal.SpillingKt
-keep class kotlin.coroutines.jvm.internal.** { *; }
