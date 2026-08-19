#include "GestureLogic.h"
#include <math.h>

static MGGestureAction action(MGGestureActionType type, MGAxis axis, double dx, double dy) {
    MGGestureAction a = { type, axis, dx, dy };
    return a;
}

void mg_gesture_init(MGGestureState *state, double threshold_px, double hold_ms) {
    state->pressed = false;
    state->dragging = false;
    state->hold_fired = false;
    state->threshold_px = threshold_px;
    state->hold_ms = hold_ms;
    state->accum_x = 0.0;
    state->accum_y = 0.0;
    state->axis = MG_AXIS_NONE;
}

MGGestureAction mg_gesture_press(MGGestureState *state) {
    state->pressed = true;
    state->dragging = false;
    state->hold_fired = false;
    state->accum_x = 0.0;
    state->accum_y = 0.0;
    state->axis = MG_AXIS_NONE;
    return action(MG_ACTION_NONE, MG_AXIS_NONE, 0.0, 0.0);
}

MGGestureAction mg_gesture_move(MGGestureState *state, double dx, double dy) {
    if (!state->pressed || state->hold_fired) {
        return action(MG_ACTION_NONE, MG_AXIS_NONE, 0.0, 0.0);
    }

    state->accum_x += dx;
    state->accum_y += dy;

    if (!state->dragging) {
        double max_abs = fmax(fabs(state->accum_x), fabs(state->accum_y));
        if (max_abs <= state->threshold_px) {
            return action(MG_ACTION_NONE, MG_AXIS_NONE, 0.0, 0.0);
        }
        state->axis = fabs(state->accum_x) >= fabs(state->accum_y)
            ? MG_AXIS_HORIZONTAL : MG_AXIS_VERTICAL;
        state->dragging = true;
        return action(MG_ACTION_DRAG_BEGAN, state->axis, dx, dy);
    }

    return action(MG_ACTION_DRAG_CHANGED, state->axis, dx, dy);
}

MGGestureAction mg_gesture_tick(MGGestureState *state, double elapsed_ms) {
    if (state->pressed && !state->dragging && !state->hold_fired && elapsed_ms >= state->hold_ms) {
        state->hold_fired = true;
        return action(MG_ACTION_HOLD, MG_AXIS_NONE, 0.0, 0.0);
    }
    return action(MG_ACTION_NONE, MG_AXIS_NONE, 0.0, 0.0);
}

MGGestureAction mg_gesture_release(MGGestureState *state) {
    MGGestureAction result = action(MG_ACTION_NONE, MG_AXIS_NONE, 0.0, 0.0);
    if (!state->pressed) {
        return result;
    }
    if (state->dragging) {
        result = action(MG_ACTION_DRAG_ENDED, state->axis, 0.0, 0.0);
    } else if (!state->hold_fired) {
        result = action(MG_ACTION_CLICK, MG_AXIS_NONE, 0.0, 0.0);
    }

    state->pressed = false;
    state->dragging = false;
    state->hold_fired = false;
    state->accum_x = 0.0;
    state->accum_y = 0.0;
    state->axis = MG_AXIS_NONE;
    return result;
}
