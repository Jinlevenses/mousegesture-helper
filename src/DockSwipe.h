#ifndef MOUSEGESTURE_DOCK_SWIPE_H
#define MOUSEGESTURE_DOCK_SWIPE_H

#include <stdbool.h>
#include "GestureLogic.h"

bool mg_dock_swipe_supported(void);
void mg_dock_swipe_begin(MGAxis axis, double delta, bool inverted_from_device);
void mg_dock_swipe_change(MGAxis axis, double delta, bool inverted_from_device);
void mg_dock_swipe_end(MGAxis axis, bool cancel, bool inverted_from_device);

#endif
