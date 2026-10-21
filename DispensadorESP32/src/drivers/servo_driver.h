#ifndef SERVO_DRIVER_H
#define SERVO_DRIVER_H

#include <Arduino.h>
#include <ESP32Servo.h>
#include "../config/config.h"

// Inicializa los temporizadores PWM y asocia el servomotor al pin configurado
void initServo();

// Acciona el servomotor para dispensar alimento (mueve a 0°, espera 10 segundos, detiene a 90°)
void dispensarAlimento();

// Establece un ángulo específico en el servomotor
void setServoAngle(int angle);

#endif // SERVO_DRIVER_H
