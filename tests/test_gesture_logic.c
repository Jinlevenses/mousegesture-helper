#include <assert.h>
#include <math.h>
#include <stdio.h>
#include "../src/GestureLogic.h"

static void test_short_click(void) {
    MGGestureState s; mg_gesture_init(&s, 7.0, 300.0);
    mg_gesture_press(&s);
    MGGestureAction a = mg_gesture_release(&s);
    assert(a.type == MG_ACTION_CLICK);
}

static void test_hold_fires_once(void) {
    MGGestureState s; mg_gesture_init(&s, 7.0, 300.0);
    mg_gesture_press(&s);
    assert(mg_gesture_tick(&s, 299.0).type == MG_ACTION_NONE);
    assert(mg_gesture_tick(&s, 300.0).type == MG_ACTION_HOLD);
    assert(mg_gesture_tick(&s, 500.0).type == MG_ACTION_NONE);
    assert(mg_gesture_release(&s).type == MG_ACTION_NONE);
}

static void test_jitter_does_not_activate_drag(void) {
    MGGestureState s; mg_gesture_init(&s, 7.0, 300.0);
    mg_gesture_press(&s);
    assert(mg_gesture_move(&s, 3.0, 2.0).type == MG_ACTION_NONE);
    assert(mg_gesture_move(&s, 2.0, 1.0).type == MG_ACTION_NONE);
    assert(mg_gesture_release(&s).type == MG_ACTION_CLICK);
}

static void test_horizontal_axis_locks(void) {
    MGGestureState s; mg_gesture_init(&s, 7.0, 300.0);
    mg_gesture_press(&s);
    MGGestureAction a = mg_gesture_move(&s, 8.0, 2.0);
    assert(a.type == MG_ACTION_DRAG_BEGAN);
    assert(a.axis == MG_AXIS_HORIZONTAL);
    a = mg_gesture_move(&s, 0.0, 20.0);
    assert(a.type == MG_ACTION_DRAG_CHANGED);
    assert(a.axis == MG_AXIS_HORIZONTAL);
    assert(mg_gesture_release(&s).type == MG_ACTION_DRAG_ENDED);
}

static void test_vertical_axis_locks(void) {
    MGGestureState s; mg_gesture_init(&s, 7.0, 300.0);
    mg_gesture_press(&s);
    MGGestureAction a = mg_gesture_move(&s, 1.0, -8.0);
    assert(a.type == MG_ACTION_DRAG_BEGAN);
    assert(a.axis == MG_AXIS_VERTICAL);
}

static void test_hold_prevents_late_drag(void) {
    MGGestureState s; mg_gesture_init(&s, 7.0, 300.0);
    mg_gesture_press(&s);
    assert(mg_gesture_tick(&s, 350.0).type == MG_ACTION_HOLD);
    assert(mg_gesture_move(&s, 20.0, 0.0).type == MG_ACTION_NONE);
}

int main(void) {
    test_short_click();
    test_hold_fires_once();
    test_jitter_does_not_activate_drag();
    test_horizontal_axis_locks();
    test_vertical_axis_locks();
    test_hold_prevents_late_drag();
    puts("gesture logic tests passed");
    return 0;
}
