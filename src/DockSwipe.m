#import "DockSwipe.h"
#import <Cocoa/Cocoa.h>
#import <CoreGraphics/CoreGraphics.h>
#include <math.h>
#include <stdint.h>
#include <string.h>

// DockSwipe synthesis is derived from Mac Mouse Fix's TouchSimulator.m.
// The numeric fields below are undocumented. Mac Mouse Fix reports that the
// field-only path is ignored on macOS 27+, so this helper disables it there.

enum {
    MG_HID_PHASE_BEGAN = 1 << 0,
    MG_HID_PHASE_CHANGED = 1 << 1,
    MG_HID_PHASE_ENDED = 1 << 2,
    MG_HID_PHASE_CANCELLED = 1 << 3,
    MG_HID_EVENT_TYPE_DOCK_SWIPE = 23,
    MG_DOCK_SWIPE_HORIZONTAL = 1,
    MG_DOCK_SWIPE_VERTICAL = 2
};

static double s_origin_offset = 0.0;
static double s_last_delta = 0.0;

static int dock_type(MGAxis axis) {
    return axis == MG_AXIS_VERTICAL ? MG_DOCK_SWIPE_VERTICAL : MG_DOCK_SWIPE_HORIZONTAL;
}

static int sign_of(double x) {
    return (x > 0.0) - (x < 0.0);
}

bool mg_dock_swipe_supported(void) {
    NSOperatingSystemVersion version = NSProcessInfo.processInfo.operatingSystemVersion;
    return version.majorVersion < 27;
}

static void post_event(MGAxis axis, double delta, int phase, bool inverted_from_device) {
    if (!mg_dock_swipe_supported()) return;

    if (phase == MG_HID_PHASE_BEGAN) {
        s_origin_offset = delta;
    } else if (phase == MG_HID_PHASE_CHANGED) {
        if (delta == 0.0) return;
        s_origin_offset += delta;
    }

    if (phase == MG_HID_PHASE_ENDED) {
        if (sign_of(s_last_delta) != 0 && sign_of(s_origin_offset) != 0 &&
            sign_of(s_last_delta) != sign_of(s_origin_offset)) {
            phase = MG_HID_PHASE_CANCELLED;
        }
    }

    const int type = dock_type(axis);
    const int val_for_41 = 33231;
    const double weird_type = (type == MG_DOCK_SWIPE_HORIZONTAL)
        ? 1.401298464324817e-45
        : 2.802596928649634e-45;

    CGEventRef e29 = CGEventCreate(NULL);
    CGEventRef e30 = CGEventCreate(NULL);
    if (!e29 || !e30) {
        if (e29) CFRelease(e29);
        if (e30) CFRelease(e30);
        return;
    }

    // Type-29 gesture companion event.
    CGEventSetDoubleValueField(e29, (CGEventField)55, 29.0);
    CGEventSetDoubleValueField(e29, (CGEventField)41, (double)val_for_41);

    // Type-30 DockSwipe event.
    CGEventSetDoubleValueField(e30, (CGEventField)55, 30.0);
    CGEventSetDoubleValueField(e30, (CGEventField)110, (double)MG_HID_EVENT_TYPE_DOCK_SWIPE);
    CGEventSetDoubleValueField(e30, (CGEventField)132, (double)phase);
    CGEventSetDoubleValueField(e30, (CGEventField)134, (double)phase);
    CGEventSetDoubleValueField(e30, (CGEventField)124, s_origin_offset);

    float offset_f32 = (float)s_origin_offset;
    uint32_t offset_bits = 0;
    memcpy(&offset_bits, &offset_f32, sizeof(offset_f32));
    CGEventSetIntegerValueField(e30, (CGEventField)135, (int64_t)offset_bits);

    CGEventSetDoubleValueField(e30, (CGEventField)41, (double)val_for_41);
    CGEventSetDoubleValueField(e30, (CGEventField)119, weird_type);
    CGEventSetDoubleValueField(e30, (CGEventField)139, weird_type);
    CGEventSetDoubleValueField(e30, (CGEventField)123, (double)type);
    CGEventSetDoubleValueField(e30, (CGEventField)165, (double)type);
    CGEventSetIntegerValueField(e30, (CGEventField)136, inverted_from_device ? 1 : 0);

    if (phase == MG_HID_PHASE_ENDED || phase == MG_HID_PHASE_CANCELLED) {
        double exit_speed = s_last_delta * 100.0;
        CGEventSetDoubleValueField(e30, (CGEventField)129, exit_speed);
        CGEventSetDoubleValueField(e30, (CGEventField)130, exit_speed);
    }

    CGEventPost(kCGSessionEventTap, e30);
    CGEventPost(kCGSessionEventTap, e29);

    CFRelease(e29);
    CFRelease(e30);
    s_last_delta = delta;
}

void mg_dock_swipe_begin(MGAxis axis, double delta, bool inverted_from_device) {
    s_origin_offset = 0.0;
    s_last_delta = 0.0;
    post_event(axis, delta, MG_HID_PHASE_BEGAN, inverted_from_device);
}

void mg_dock_swipe_change(MGAxis axis, double delta, bool inverted_from_device) {
    post_event(axis, delta, MG_HID_PHASE_CHANGED, inverted_from_device);
}

void mg_dock_swipe_end(MGAxis axis, bool cancel, bool inverted_from_device) {
    post_event(axis, 0.0, cancel ? MG_HID_PHASE_CANCELLED : MG_HID_PHASE_ENDED,
               inverted_from_device);
}
