#import <Cocoa/Cocoa.h>
#import <ApplicationServices/ApplicationServices.h>
#import <Carbon/Carbon.h>
#include <assert.h>

// Keep the real callbacks; replace only permission checks and system output.
static void run_shortcut_now(dispatch_time_t when, dispatch_queue_t queue,
                             dispatch_block_t block) {
    (void)when;
    (void)queue;
    block();
}

static bool permission_granted(void) { return true; }

static void discard_event(CGEventTapLocation tap, CGEventRef event) {
    (void)tap;
    (void)event;
}

#define main helper_main
#define dispatch_after run_shortcut_now
#define AXIsProcessTrusted permission_granted
#define CGEventPost discard_event
#include "../src/main.m"
#undef main
#undef dispatch_after
#undef AXIsProcessTrusted
#undef CGEventPost

bool mg_dock_swipe_supported(void) { return false; }

void mg_dock_swipe_begin(MGAxis axis, double delta, bool inverted) {
    (void)axis; (void)delta; (void)inverted;
    assert(!"fallback must not synthesize DockSwipe events");
}
void mg_dock_swipe_change(MGAxis axis, double delta, bool inverted) {
    (void)axis; (void)delta; (void)inverted;
    assert(!"fallback must not synthesize DockSwipe events");
}
void mg_dock_swipe_end(MGAxis axis, bool cancel, bool inverted) {
    (void)axis; (void)cancel; (void)inverted;
    assert(!"fallback must not synthesize DockSwipe events");
}

static MGSymbolicHotKey last_hotkey;
static unsigned hotkey_count;

static bool hotkey_enabled(MGSymbolicHotKey hotkey) {
    (void)hotkey;
    return true;
}

static CGError capture_hotkey(MGSymbolicHotKey hotkey, unichar *equivalent,
                              unichar *keycode,
                              MGSymbolicHotKeyModifiers *modifiers) {
    last_hotkey = hotkey;
    ++hotkey_count;
    *equivalent = 0xffff;
    *keycode = 123;
    *modifiers = kMGSymbolicControlKeyMask;
    return kCGErrorSuccess;
}

static void press(void) {
    CGEventRef event = CGEventCreateKeyboardEvent(NULL, kVK_F20, true);
    assert(event);
    assert(key_event_callback(NULL, kCGEventKeyDown, event, NULL) == NULL);
    CFRelease(event);
}

static void move(int64_t dx, int64_t dy) {
    CGEventRef event = CGEventCreateMouseEvent(NULL, kCGEventMouseMoved,
                                              CGPointZero, kCGMouseButtonLeft);
    assert(event);
    CGEventSetIntegerValueField(event, kCGMouseEventDeltaX, dx);
    CGEventSetIntegerValueField(event, kCGMouseEventDeltaY, dy);
    assert(pointer_event_callback(NULL, kCGEventMouseMoved, event, NULL) == event);
    CFRelease(event);
}

static void release(void) {
    CGEventRef event = CGEventCreateKeyboardEvent(NULL, kVK_F20, false);
    assert(event);
    assert(key_event_callback(NULL, kCGEventKeyUp, event, NULL) == NULL);
    CFRelease(event);
}

int main(void) {
    @autoreleasepool {
        gSymbolicHotKeyAPI.resolved = true;
        gSymbolicHotKeyAPI.available = true;
        gSymbolicHotKeyAPI.isEnabled = hotkey_enabled;
        gSymbolicHotKeyAPI.getValue = capture_hotkey;
        mg_gesture_init(&gGesture, 50.0, 300.0);

        const struct {
            const char *name;
            int64_t dx, dy;
            double horizontal_sign, vertical_sign;
            MGSymbolicHotKey expected;
        } cases[] = {
            {"default: drag right -> left Space", 100, 0, -1, 1, 79},
            {"default: drag left -> right Space", -100, 0, -1, 1, 81},
            {"default: drag up -> Mission Control", 0, -100, -1, 1, 32},
            {"default: drag down -> App Expose", 0, 100, -1, 1, 33},
            {"reversed horizontal: drag right -> right Space", 100, 0, 1, 1, 81},
            {"reversed horizontal: drag left -> left Space", -100, 0, 1, 1, 79},
            {"reversed vertical: drag up -> App Expose", 0, -100, -1, -1, 33},
            {"reversed vertical: drag down -> Mission Control", 0, 100, -1, -1, 32},
            {"zero horizontal sign disables Space switching", 100, 0, 0, 1, 0},
            {"zero vertical sign disables vertical action", 0, 100, -1, 0, 0},
        };
        unsigned failures = 0;
        for (size_t i = 0; i < sizeof(cases) / sizeof(cases[0]); ++i) {
            gHorizontalSign = cases[i].horizontal_sign;
            gVerticalSign = cases[i].vertical_sign;
            last_hotkey = 0;
            hotkey_count = 0;
            press();
            move(cases[i].dx, cases[i].dy);
            assert(hotkey_count == 0); // Only commit on button release.
            release();
            unsigned expected_count = cases[i].expected == 0 ? 0 : 1;
            if (last_hotkey != cases[i].expected || hotkey_count != expected_count) {
                fprintf(stderr, "FAIL %s: expected SHK %d (%u calls), got %d (%u calls)\n",
                        cases[i].name, cases[i].expected, expected_count,
                        last_hotkey, hotkey_count);
                ++failures;
            }
        }
        if (failures) return 1;
        puts("drag direction tests passed");
    }
    return 0;
}
