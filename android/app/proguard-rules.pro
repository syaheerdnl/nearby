# Release build (R8) keep rules.

# WorkManager builds its Room database by reflection (WorkDatabase_Impl()).
# R8 stripped that constructor and the app crashed on launch.
-keep class * extends androidx.room.RoomDatabase { <init>(); }
-keep class androidx.work.impl.WorkDatabase_Impl { *; }

# native_geofence ships no keep rules. Its worker, receivers and
# kotlinx.serialization models are reached by name / reflection.
-keep class com.chunkytofustudios.native_geofence.** { *; }
