#ifndef SERVO_DRIVER_H
#define SERVO_DRIVER_H

#include <Arduino.h>
#include <ESP32Servo.h>
#include "../config/config.h"

// Inicializa los temporizadores PWM y asocia el servomotor al pin configurado
void initServo();

// Arranca el servomotor en giro continuo (0°) para dispensar alimento
void startServo();

// Pone el servomotor en el ángulo de retroceso (180°) para desatascar el tornillo;
// queda marcado en movimiento para que stopServo() siga siendo idempotente
void reverseServo();

// Detiene el servomotor (90°); es idempotente
void stopServo();

// Establece un ángulo específico en el servomotor
void setServoAngle(int angle);

#endif // SERVO_DRIVER_H
