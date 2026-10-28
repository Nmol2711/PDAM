#include "servo_driver.h"

// Instancia global del servomotor MG966R
static Servo myServo;

// Indica si el servomotor se encuentra en giro continuo
static bool servoEnGiro = false;

void initServo() {
  Serial.println("Inicializando temporizadores PWM y servomotor MG966R...");
  
  // Asignar temporizadores para el servo en ESP32
  ESP32PWM::allocateTimer(0);
  ESP32PWM::allocateTimer(1);
  ESP32PWM::allocateTimer(2);
  ESP32PWM::allocateTimer(3);
  
  myServo.setPeriodHertz(50); 
  myServo.attach(servoPin, 500, 2400);
  myServo.write(90); // Detenido al arrancar
  
  Serial.println("Servomotor inicializado y detenido en 90° en el Pin 4.");
}

void startServo() {
  myServo.write(0); // Giro continuo
  servoEnGiro = true;
  Serial.println("Servomotor en giro continuo (0°).");
}

void reverseServo() {
  // Giro inverso de desatasco: libera la croqueta cuñada entre la hélice y el
  // tubo. Se marca en movimiento para que stopServo() registre la parada una
  // sola vez, igual que en el avance.
  myServo.write(kReverseAngleDegrees);
  servoEnGiro = true;
  Serial.println("Servomotor en retroceso (180°) para desatascar.");
}

void stopServo() {
  myServo.write(90); // Detenido

  // Solo registra el cambio si el servo estaba girando, para que la parada
  // sea idempotente y no repita el mensaje en llamadas consecutivas.
  if (servoEnGiro) {
    servoEnGiro = false;
    Serial.println("Servomotor detenido en 90°.");
  }
}

void setServoAngle(int angle) {
  myServo.write(angle);
}
