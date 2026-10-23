#include <unity.h>
#include "config/provisioning_utils.h"

void setUp(void) {}

void tearDown(void) {}

void test_format_mac_address_returns_colon_separated_uppercase(void) {
  const unsigned char mac[6] = {0xA4, 0xCF, 0x12, 0x7B, 0x3C, 0x9E};
  char output[18];

  formatMacAddress(mac, output, sizeof(output));

  TEST_ASSERT_EQUAL_STRING("A4:CF:12:7B:3C:9E", output);
}

void test_build_ble_device_name_uses_pdam_config_prefix(void) {
  const unsigned char mac[6] = {0x24, 0x6F, 0x28, 0xAB, 0xCD, 0xEF};
  char output[30];

  buildBleDeviceName(mac, output, sizeof(output));

  TEST_ASSERT_EQUAL_STRING("PDAM-Config-246F28ABCDEF", output);
}

void test_build_ble_device_name_respects_buffer_size(void) {
  const unsigned char mac[6] = {0x24, 0x6F, 0x28, 0xAB, 0xCD, 0xEF};
  char output[10];

  buildBleDeviceName(mac, output, sizeof(output));

  TEST_ASSERT_EQUAL_STRING("PDAM-Conf", output);
}

void test_are_credentials_complete_requires_both_values(void) {
  TEST_ASSERT_TRUE(areCredentialsComplete("MiRed_2.4G", "clave-segura"));
  TEST_ASSERT_FALSE(areCredentialsComplete("", "clave-segura"));
  TEST_ASSERT_FALSE(areCredentialsComplete("MiRed_2.4G", ""));
  TEST_ASSERT_FALSE(areCredentialsComplete("", ""));
  TEST_ASSERT_FALSE(areCredentialsComplete(nullptr, "clave-segura"));
  TEST_ASSERT_FALSE(areCredentialsComplete("MiRed_2.4G", nullptr));
}

void test_format_mac_address_handles_null_and_empty_buffer(void) {
  const unsigned char mac[6] = {0x01, 0x02, 0x03, 0x04, 0x05, 0x06};
  char output[18];

  formatMacAddress(nullptr, output, sizeof(output));
  TEST_ASSERT_EQUAL_STRING("", output);

  output[0] = 'X';
  formatMacAddress(mac, output, 0);
  TEST_ASSERT_EQUAL_CHAR('X', output[0]);
}

int main(int argc, char **argv) {
  UNITY_BEGIN();
  RUN_TEST(test_format_mac_address_returns_colon_separated_uppercase);
  RUN_TEST(test_build_ble_device_name_uses_pdam_config_prefix);
  RUN_TEST(test_build_ble_device_name_respects_buffer_size);
  RUN_TEST(test_are_credentials_complete_requires_both_values);
  RUN_TEST(test_format_mac_address_handles_null_and_empty_buffer);
  return UNITY_END();
}
