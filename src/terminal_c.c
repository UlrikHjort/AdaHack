/* ***************************************************************************
 *                   AdaHack - terminal_c.c
 *
 *           Copyright (C) 2026 By Ulrik Hørlyk Hjort
 *
 * Permission is hereby granted, free of charge, to any person obtaining
 * a copy of this software and associated documentation files (the
 * "Software"), to deal in the Software without restriction, including
 * without limitation the rights to use, copy, modify, merge, publish,
 * distribute, sublicense, and/or sell copies of the Software, and to
 * permit persons to whom the Software is furnished to do so, subject to
 * the following conditions:
 *
 * The above copyright notice and this permission notice shall be
 * included in all copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
 * EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
 * MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
 * NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE
 * LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION
 * OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION
 * WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
 **************************************************************************/

#include <termios.h>
#include <unistd.h>
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>

static struct termios saved_attrs;

void set_raw_mode(void) {
    struct termios t;
    tcgetattr(STDIN_FILENO, &saved_attrs);
    t = saved_attrs;
    t.c_lflag &= ~(ECHO | ICANON | ISIG);
    t.c_iflag &= ~(IXON | ICRNL);
    t.c_cc[VMIN]  = 1;
    t.c_cc[VTIME] = 0;
    tcsetattr(STDIN_FILENO, TCSAFLUSH, &t);
}

void restore_terminal(void) {
    tcsetattr(STDIN_FILENO, TCSAFLUSH, &saved_attrs);
}

/* Blocking read -returns byte value or -1 on error */
int read_byte(void) {
    unsigned char c;
    if (read(STDIN_FILENO, &c, 1) == 1)
        return (int)c;
    return -1;
}

/* Non-blocking read -returns byte value or -1 if no data */
int read_byte_nb(void) {
    int flags = fcntl(STDIN_FILENO, F_GETFL, 0);
    fcntl(STDIN_FILENO, F_SETFL, flags | O_NONBLOCK);
    unsigned char c;
    int n = (int)read(STDIN_FILENO, &c, 1);
    fcntl(STDIN_FILENO, F_SETFL, flags);
    if (n == 1) return (int)c;
    return -1;
}
