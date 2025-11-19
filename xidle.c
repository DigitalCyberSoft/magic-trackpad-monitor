#include <X11/Xlib.h>
#include <X11/extensions/scrnsaver.h>
#include <stdio.h>

int main(void) {
    Display *display = XOpenDisplay(NULL);
    if (!display) {
        fprintf(stderr, "Unable to open X display\n");
        return 1;
    }

    XScreenSaverInfo *info = XScreenSaverAllocInfo();
    if (!info) {
        fprintf(stderr, "Unable to allocate XScreenSaverInfo\n");
        XCloseDisplay(display);
        return 1;
    }

    if (!XScreenSaverQueryInfo(display, DefaultRootWindow(display), info)) {
        fprintf(stderr, "XScreenSaverQueryInfo failed\n");
        XFree(info);
        XCloseDisplay(display);
        return 1;
    }

    // Print idle time in milliseconds
    printf("%lu\n", info->idle);

    XFree(info);
    XCloseDisplay(display);
    return 0;
}
