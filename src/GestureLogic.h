#ifndef MOUSEGESTURE_GESTURE_LOGIC_H
#define MOUSEGESTURE_GESTURE_LOGIC_H

#include <stdbool.h>

typedef enum {
    MG_AXIS_NONE = 0,
    MG_AXIS_HORIZONTAL,
    MG_AXIS_VERTICAL
} MGAxis;

typedef enum {
    MG_ACTION_NONE = 0,
    MG_ACTION_CLICK,
    MG_ACTION_HOLD,
    MG_ACTION_DRAG_BEGAN,
    MG_ACTION_DRAG_CHANGED,
    MG_ACTION_DRAG_ENDED
} MGGestureActionType;

typedef struct {
    MGGestureActionType type;
    MGAxis axis;
    double dx;
    double dy;
} MGGestureAction;

typedef struct {
    bool pressed;
    bool dragging;
    bool hold_fired;
    double threshold_px;
    double hold_ms;
    double accum_x;
    double accum_y;
    MGAxis axis;
} MGGestureState;

void mg_gesture_init(MGGestureState *state, double threshold_px, double hold_ms);
MGGestureAction mg_gesture_press(MGGestureState *state);
MGGestureAction mg_gesture_move(MGGestureState *state, double dx, double dy);
MGGestureAction mg_gesture_tick(MGGestureState *state, double elapsed_ms);
MGGestureAction mg_gesture_release(MGGestureState *state);

#endif
