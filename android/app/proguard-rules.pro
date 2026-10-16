# Uygulamaya özgü R8/ProGuard kuralları (release derlemesinde Flutter Gradle eklentisi bu dosyayı
# otomatik ekler). Eklentilerin kendi tüketici kuralları (flutter_reactive_ble, mobile_scanner vb.)
# ayrıca geçerlidir.

# Manifest'te adıyla anılan bileşenler (ana etkinlik, kapı widget'ı).
-keep class tr.com.gudeteknoloji.siteyonetim.** { *; }

# Ana ekran widget'ı (home_widget): receiver/servis sınıfları manifest + PendingIntent ile çağrılır.
-keep class es.antonborri.home_widget.** { *; }

# Yığın izlerinin okunabilir kalması için satır numaraları ve temel öznitelikler.
-keepattributes SourceFile,LineNumberTable,*Annotation*,Signature,InnerClasses,EnclosingMethod

# Flutter gömme katmanı Play Core (ertelenmiş bileşenler) sınıflarına başvurur; kullanılmıyor.
-dontwarn com.google.android.play.core.**
