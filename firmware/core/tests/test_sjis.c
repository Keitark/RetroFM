/* SPDX-License-Identifier: GPL-3.0-or-later */

#include "retrofm_sjis.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define CHECK(condition) do { if (!(condition)) {                            \
    fprintf(stderr, "CHECK failed %s:%d: %s\n", __FILE__, __LINE__,         \
            #condition); return EXIT_FAILURE; } } while (0)

int main(void) {
    const uint8_t title[] = {
        'A', ' ', 0x83U, 0x65U, 0x83U, 0x58U, 0x83U, 0x67U, ' ', 0xA6U
    };
    const char expected[] = "A \xE3\x83\x86\xE3\x82\xB9\xE3\x83\x88 "
                            "\xEF\xBD\xA6";
    const uint8_t broken[] = { 0x82U };
    char output[64];
    size_t output_size;

    CHECK(retrofm_sjis_to_utf8(title, sizeof(title), output, sizeof(output),
                               &output_size) == RETROFM_SJIS_OK);
    CHECK(strcmp(output, expected) == 0);
    CHECK(output_size == strlen(expected));
    CHECK(retrofm_sjis_to_utf8(broken, sizeof(broken), output, sizeof(output),
                               &output_size) == RETROFM_SJIS_REPLACED);
    CHECK(strcmp(output, "?") == 0);
    CHECK(retrofm_sjis_to_utf8(title, sizeof(title), output, 4U,
                               &output_size) ==
          RETROFM_SJIS_OUTPUT_TOO_SMALL);
    puts("retrofm CP932/Shift-JIS title tests passed");
    return EXIT_SUCCESS;
}
