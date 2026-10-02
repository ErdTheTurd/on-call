# R8 full mode. kotlinx-serialization and Ktor ship consumer rules; these
# cover the app models and the GoTrue JSON we parse by hand.

-keepattributes *Annotation*, InnerClasses, Signature, EnclosingMethod, RuntimeVisibleAnnotations

-keep,includedescriptorclasses class com.eporthospine.mdshift.**$$serializer { *; }
-keepclassmembers class com.eporthospine.mdshift.** {
    *** Companion;
}
-keepclasseswithmembers class com.eporthospine.mdshift.** {
    kotlinx.serialization.KSerializer serializer(...);
}
-keepclassmembers enum com.eporthospine.mdshift.** { *; }

-dontwarn io.ktor.**
-dontwarn okhttp3.**
-dontwarn org.slf4j.**
-dontwarn org.conscrypt.**
-dontwarn org.bouncycastle.**
-dontwarn org.openjsse.**

-keep class com.eporthospine.mdshift.BuildConfig { *; }
