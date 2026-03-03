#ifndef ROLE_KONTROL_H
#define ROLE_KONTROL_H

#define ROLE_PIN 5

unsigned long roleBaslangic = 0;
bool roleAktif = false;
const unsigned long roleSure = 1500; // 1.5 saniye

void roleSetup() {
  pinMode(ROLE_PIN, OUTPUT);
  digitalWrite(ROLE_PIN, HIGH); // LOW aktif röle için başlangıç kapalı
}

void roleTetikle() {
  digitalWrite(ROLE_PIN, LOW);  // Röleyi çek
  roleBaslangic = millis();
  roleAktif = true;
  Serial.println("Röle tetiklendi");
}

void roleLoop() {
  if (roleAktif && millis() - roleBaslangic >= roleSure) {
    digitalWrite(ROLE_PIN, HIGH); // Röleyi bırak
    roleAktif = false;
    Serial.println("Röle bırakıldı");
  }
}

#endif