# WorkManager (the re-register job): Room builds its database by reflection from
# the no-argument constructor. Room 2.6.1's own rule keeps the class only, and
# R8's full mode then drops the constructor: a release build crashes at launch.
-keep class * extends androidx.room.RoomDatabase { <init>(); }
