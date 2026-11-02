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

static CGKeyCode posted_key;
static unsigned posted_down, posted_up;
static bool fail_keyboard_output;

static void discard_event(CGEventTapLocation tap, CGEventRef event) {
    (void)tap;
    if (CGEventGetType(event) == kCGEventKeyDown) {
        posted_key = (CGKeyCode)CGEventGetIntegerValueField(event, kCGKeyboardEventKeycode);
        ++posted_down;
    } else if (CGEventGetType(event) == kCGEventKeyUp) {
        ++posted_up;
    }
}

static CGEventRef keyboard_output(CGEventSourceRef source, CGKeyCode key, bool down) {
    return fail_keyboard_output ? NULL : CGEventCreateKeyboardEvent(source, key, down);
}

#define main helper_main
#define dispatch_after run_shortcut_now
#define AXIsProcessTrusted permission_granted
#define CGEventPost discard_event
#define CGEventCreateKeyboardEvent keyboard_output
#include "../src/main.m"
#undef main
#undef dispatch_after
#undef AXIsProcessTrusted
#undef CGEventPost
#undef CGEventCreateKeyboardEvent

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

static bool paging_button(bool down) {
    CGEventRef event = CGEventCreateKeyboardEvent(NULL, kVK_F19, down);
    assert(event);
    bool consumed = key_event_callback(NULL, down ? kCGEventKeyDown : kCGEventKeyUp,
                                       event, NULL) == NULL;
    CFRelease(event);
    return consumed;
}

static unsigned test_paging(void) {
    const struct {
        const char *name;
        bool held, inverted, continuous, momentum, fail_output;
        int dy, dx;
        CGKeyCode expected;
    } cases[] = {
        {"ordinary wheel up passes", false, false, false, false, false, 1, 0, 0},
        {"ordinary natural wheel passes", false, true, false, false, false, -1, 0, 0},
        {"held + physical up", true, false, false, false, false, 1, 0, 116},
        {"held + physical down", true, false, false, false, false, -1, 0, 121},
        {"held + natural physical up", true, true, false, false, false, -1, 0, 116},
        {"held + natural physical down", true, true, false, false, false, 1, 0, 121},
        {"trackpad passes", true, false, true, false, false, 1, 0, 0},
        {"horizontal wheel passes", true, false, false, false, false, 0, 1, 0},
        {"mixed axes pass", true, false, false, false, false, 1, 1, 0},
        {"momentum passes", true, false, false, true, false, 1, 0, 0},
        {"zero delta passes", true, false, false, false, false, 0, 0, 0},
        {"failed output preserves wheel", true, false, false, false, true, 1, 0, 0},
    };
    unsigned failures = 0;
    for (size_t i = 0; i < sizeof(cases) / sizeof(cases[0]); ++i) {
        if (cases[i].held && !paging_button(true)) {
            fprintf(stderr, "FAIL F19 down was not consumed\n");
            ++failures;
        }
        CGEventRef wheel = CGEventCreateScrollWheelEvent(NULL, kCGScrollEventUnitLine,
                                                         2, cases[i].dy, cases[i].dx);
        assert(wheel);
        // Fixture for NSEvent.isDirectionInvertedFromDevice (no public setter).
        CGEventSetIntegerValueField(wheel, (CGEventField)137, cases[i].inverted);
        CGEventSetIntegerValueField(wheel, kCGScrollWheelEventIsContinuous, cases[i].continuous);
        CGEventSetIntegerValueField(wheel, kCGScrollWheelEventMomentumPhase, cases[i].momentum);
        assert([NSEvent eventWithCGEvent:wheel].isDirectionInvertedFromDevice == cases[i].inverted);
        CFDataRef before = CGEventCreateData(NULL, wheel);
        posted_key = 0;
        posted_down = posted_up = 0;
        fail_keyboard_output = cases[i].fail_output;
        CGEventRef result = key_event_callback(NULL, kCGEventScrollWheel, wheel, NULL);
        fail_keyboard_output = false;
        unsigned expected_count = cases[i].expected ? 1 : 0;
        if (posted_key != cases[i].expected || posted_down != expected_count ||
            posted_up != expected_count || result != (cases[i].expected ? NULL : wheel)) {
            fprintf(stderr, "FAIL %s: expected key %u, got %u (%u down/%u up), consumed=%d\n",
                    cases[i].name, cases[i].expected, posted_key, posted_down, posted_up,
                    result == NULL);
            ++failures;
        }
        if (!cases[i].expected) {
            CFDataRef after = CGEventCreateData(NULL, wheel);
            assert(CFEqual(before, after));
            CFRelease(after);
        }
        CFRelease(before);
        CFRelease(wheel);
        if (cases[i].held && !paging_button(false)) {
            fprintf(stderr, "FAIL F19 up was not consumed\n");
            ++failures;
        }
    }
    paging_button(true);
    paging_button(false);
    CGEventRef released_wheel = CGEventCreateScrollWheelEvent(NULL, kCGScrollEventUnitLine, 1, 1);
    posted_down = posted_up = 0;
    assert(key_event_callback(NULL, kCGEventScrollWheel, released_wheel, NULL) == released_wheel);
    assert(posted_down == 0 && posted_up == 0);
    CFRelease(released_wheel);
    // A lost release during tap interruption must not leave paging enabled.
    paging_button(true);
    (void)key_event_callback(NULL, kCGEventTapDisabledByTimeout, NULL, NULL);
    CGEventRef wheel = CGEventCreateScrollWheelEvent(NULL, kCGScrollEventUnitLine, 1, 1);
    posted_down = posted_up = 0;
    assert(key_event_callback(NULL, kCGEventScrollWheel, wheel, NULL) == wheel);
    assert(posted_down == 0 && posted_up == 0);
    CFRelease(wheel);
    paging_button(false);
    return failures;
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
        failures += test_paging();
        if (failures) return 1;
        puts("drag direction and paging tests passed");
    }
    return 0;
}
