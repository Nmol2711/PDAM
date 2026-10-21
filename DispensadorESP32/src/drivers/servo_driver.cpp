#include "servo_driver.h"

// Instancia global del servomotor MG966R
static Servo myServo;

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

void dispensarAlimento() {
  Serial.println("Activando motor... El tornillo sin fin esta girando.");
  
  myServo.write(0); 
  delay(10000); // 10 segundos de dispensación
  myServo.write(90); // Detener
  
  Serial.println("Ciclo completado. Motor detenido con exito.");
}

void setServoAngle(int angle) {
  myServo.write(angle);
}
