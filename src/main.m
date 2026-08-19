#import <Cocoa/Cocoa.h>
#import <ApplicationServices/ApplicationServices.h>
#import <Carbon/Carbon.h>
#import <CoreGraphics/CoreGraphics.h>
#import <mach/mach_time.h>

#include <dlfcn.h>
#include <math.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>

#include "GestureLogic.h"
#include "DockSwipe.h"

/*
 * MouseGestureHelper
 *
 * Input contract:
 *   - Karabiner maps mouse button 3 -> F20 down/up.
 *   - This helper consumes only F20.
 *   - A short F20 click invokes Mission Control through SymbolicHotKey 32.
 *   - Holding F20 while moving the pointer drives DockSwipe for Space switching.
 *   - Pointer events are observed through a LISTEN-ONLY event tap, so this helper
 *     can never suppress normal mouse movement/drag events.
 *
 * Safety contract:
 *   - Accessibility permission is checked before installing taps.
 *   - Permission revocation while running stops the run loop and tears down taps.
 *   - Event-tap creation failures are fail-closed; there is no infinite retry loop.
 *   - Synthetic shortcut events are tagged and ignored by this helper.
 */

static const int64_t kSyntheticTag = 0x4d475348454c5045LL; // "MGSHELPE"
static const double kTimerHz = 60.0;
static const double kPermissionCheckIntervalSec = 0.50;
static const int64_t kShortcutDelayMs = 12;

static CFMachPortRef gKeyEventTap = NULL;
static CFMachPortRef gPointerEventTap = NULL;
static CFRunLoopSourceRef gKeyEventSource = NULL;
static CFRunLoopSourceRef gPointerEventSource = NULL;
static CFRunLoopTimerRef gTimer = NULL;

static MGGestureState gGesture;
static uint64_t gPressTicks = 0;
static double gFallbackAccumX = 0.0;
static double gFallbackAccumY = 0.0;
static CFAbsoluteTime gNextPermissionCheck = 0.0;
static bool gStopping = false;

static double gHorizontalProgress = 1.6;
static double gVerticalProgress = 1.0;
static double gHorizontalSign = -1.0;
static double gVerticalSign = 1.0;

static double env_double(const char *name, double fallback) {
    const char *value = getenv(name);
    if (!value || !*value) return fallback;

    char *end = NULL;
    double parsed = strtod(value, &end);
    return end != value && isfinite(parsed) ? parsed : fallback;
}

static double monotonic_ms_from_ticks(uint64_t ticks) {
    static mach_timebase_info_data_t info = {0, 0};
    if (info.denom == 0) mach_timebase_info(&info);

    long double nanos =
        (long double)ticks * (long double)info.numer / (long double)info.denom;
    return (double)(nanos / 1000000.0L);
}

static double elapsed_since_press_ms(void) {
    if (!gPressTicks) return 0.0;
    return monotonic_ms_from_ticks(mach_absolute_time() - gPressTicks);
}

static void mark_synthetic(CGEventRef event) {
    if (event) {
        CGEventSetIntegerValueField(event, kCGEventSourceUserData, kSyntheticTag);
    }
}

static bool is_synthetic(CGEventRef event) {
    return event &&
           CGEventGetIntegerValueField(event, kCGEventSourceUserData) ==
               kSyntheticTag;
}

/*
 * Symbolic Hot Keys (private CoreGraphics/SkyLight API)
 *
 * Mission Control and Space switching are system actions with stable symbolic
 * hot-key IDs. Rather than guessing that Mission Control is Control-Up, ask
 * macOS which keyboard binding is attached to the action and post that exact
 * binding. This mirrors the strategy used by Mac Mouse Fix, while keeping this
 * implementation deliberately small and self-contained.
 *
 * If the symbolic hot key has no usable binding (for example, the user disabled
 * the keyboard shortcut), install an "out-of-reach" virtual key code. The key
 * code is far outside the range produced by normal keyboards, so it won't steal
 * a real key from the user. We intentionally DO NOT restore that fallback
 * immediately: temporary set/restore has proven unreliable on recent macOS
 * versions and can accidentally remove the user's shortcut.
 *
 * These APIs are private. Resolve them with dlsym so a missing/changed private
 * symbol fails gracefully instead of preventing the helper from launching.
 */
typedef int32_t MGSymbolicHotKey;
typedef uint32_t MGSymbolicHotKeyModifiers;

enum {
    kSymbolicHotKeyMissionControl = 32,
    kSymbolicHotKeyAppExpose = 33,
    kSymbolicHotKeyMoveLeftASpace = 79,
    kSymbolicHotKeyMoveRightASpace = 81,
    kSymbolicHotKeyOutOfReachOffset = 400,
};

enum {
    kMGSymbolicAlphaShiftKeyMask = 1U << 16,
    kMGSymbolicShiftKeyMask = 1U << 17,
    kMGSymbolicControlKeyMask = 1U << 18,
    kMGSymbolicAlternateKeyMask = 1U << 19,
    kMGSymbolicCommandKeyMask = 1U << 20,
    kMGSymbolicNumericPadKeyMask = 1U << 21,
    kMGSymbolicHelpKeyMask = 1U << 22,
    kMGSymbolicFunctionKeyMask = 1U << 23,
};

static const unichar kSymbolicHotKeyNullKeyEquivalent = (unichar)0xffff;
static const unichar kSymbolicHotKeyNullVKC = (unichar)0xffff;

typedef bool (*MGCGSIsSymbolicHotKeyEnabledFn)(MGSymbolicHotKey hotKey);
typedef CGError (*MGCGSSetSymbolicHotKeyEnabledFn)(MGSymbolicHotKey hotKey,
                                                    bool enabled);
typedef CGError (*MGCGSGetSymbolicHotKeyValueFn)(
    MGSymbolicHotKey hotKey,
    unichar *outKeyEquivalent,
    unichar *outVirtualKeyCode,
    MGSymbolicHotKeyModifiers *outModifiers);
typedef CGError (*MGCGSSetSymbolicHotKeyValueFn)(
    MGSymbolicHotKey hotKey,
    unichar keyEquivalent,
    CGKeyCode virtualKeyCode,
    MGSymbolicHotKeyModifiers modifiers);

typedef struct {
    MGCGSIsSymbolicHotKeyEnabledFn isEnabled;
    MGCGSSetSymbolicHotKeyEnabledFn setEnabled;
    MGCGSGetSymbolicHotKeyValueFn getValue;
    MGCGSSetSymbolicHotKeyValueFn setValue;
    void *skyLightHandle;
    bool resolved;
    bool available;
} MGSymbolicHotKeyAPI;

static MGSymbolicHotKeyAPI gSymbolicHotKeyAPI = {0};

static void *resolve_symbol(const char *name) {
    void *symbol = dlsym(RTLD_DEFAULT, name);
    if (symbol) return symbol;

    if (!gSymbolicHotKeyAPI.skyLightHandle) {
        gSymbolicHotKeyAPI.skyLightHandle = dlopen(
            "/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight",
            RTLD_LAZY | RTLD_LOCAL);
    }

    return gSymbolicHotKeyAPI.skyLightHandle
        ? dlsym(gSymbolicHotKeyAPI.skyLightHandle, name)
        : NULL;
}

static bool resolve_symbolic_hotkey_api(void) {
    if (gSymbolicHotKeyAPI.resolved) return gSymbolicHotKeyAPI.available;
    gSymbolicHotKeyAPI.resolved = true;

    gSymbolicHotKeyAPI.isEnabled =
        (MGCGSIsSymbolicHotKeyEnabledFn)resolve_symbol(
            "CGSIsSymbolicHotKeyEnabled");
    gSymbolicHotKeyAPI.setEnabled =
        (MGCGSSetSymbolicHotKeyEnabledFn)resolve_symbol(
            "CGSSetSymbolicHotKeyEnabled");
    gSymbolicHotKeyAPI.getValue =
        (MGCGSGetSymbolicHotKeyValueFn)resolve_symbol(
            "CGSGetSymbolicHotKeyValue");
    gSymbolicHotKeyAPI.setValue =
        (MGCGSSetSymbolicHotKeyValueFn)resolve_symbol(
            "CGSSetSymbolicHotKeyValue");

    gSymbolicHotKeyAPI.available =
        gSymbolicHotKeyAPI.isEnabled &&
        gSymbolicHotKeyAPI.setEnabled &&
        gSymbolicHotKeyAPI.getValue &&
        gSymbolicHotKeyAPI.setValue;

    if (!gSymbolicHotKeyAPI.available) {
        fprintf(stderr,
                "MouseGestureHelper: SymbolicHotKey private API unavailable; "
                "Mission Control/shortcut fallback cannot be posted.\n");
    }

    return gSymbolicHotKeyAPI.available;
}

static bool post_symbolic_hotkey_keyboard_events(CGKeyCode keycode,
                                                  CGEventFlags modifiers) {
    /*
     * Match the event shape macOS expects for a symbolic hot key: keyDown has
     * the hot-key modifiers; keyUp restores the user's real modifier state.
     * This avoids synthesizing separate Control/Option/Command key presses and
     * therefore does not disturb the user's physical modifier-key state.
     */
    CGEventRef keyDown = CGEventCreateKeyboardEvent(NULL, keycode, true);
    CGEventRef keyUp = CGEventCreateKeyboardEvent(NULL, keycode, false);
    if (!keyDown || !keyUp) {
        fprintf(stderr,
                "MouseGestureHelper: failed to create SymbolicHotKey events.\n");
        if (keyDown) CFRelease(keyDown);
        if (keyUp) CFRelease(keyUp);
        return false;
    }

    CGEventFlags physicalFlags =
        CGEventSourceFlagsState(kCGEventSourceStateCombinedSessionState);

    mark_synthetic(keyDown);
    mark_synthetic(keyUp);
    CGEventSetFlags(keyDown, modifiers);
    CGEventSetFlags(keyUp, physicalFlags);

    CGEventPost(kCGSessionEventTap, keyDown);
    CGEventPost(kCGSessionEventTap, keyUp);

    CFRelease(keyDown);
    CFRelease(keyUp);
    return true;
}

static bool post_symbolic_hotkey(MGSymbolicHotKey hotKey) {
    if (!resolve_symbolic_hotkey_api()) return false;

    unichar keyEquivalent = kSymbolicHotKeyNullKeyEquivalent;
    unichar virtualKeyCode = kSymbolicHotKeyNullVKC;
    MGSymbolicHotKeyModifiers modifiers = 0;

    CGError getError = gSymbolicHotKeyAPI.getValue(
        hotKey, &keyEquivalent, &virtualKeyCode, &modifiers);
    bool enabled = gSymbolicHotKeyAPI.isEnabled(hotKey);

    /*
     * A non-null VKC is directly postable for the overwhelmingly common system
     * bindings (including the default Mission Control/Space bindings). If a
     * keyEquivalent exists, macOS may also care about the current keyboard
     * layout. We deliberately keep the current user binding and try it first;
     * unlike MMF we don't need its large keyboard-layout reverse lookup for the
     * normal Mission Control/arrow-key case.
     */
    bool currentBindingUsable =
        getError == kCGErrorSuccess &&
        enabled &&
        virtualKeyCode != kSymbolicHotKeyNullVKC;

    if (currentBindingUsable) {
        fprintf(stderr,
                "MouseGestureHelper: SHK %d current binding vkc=%u mods=0x%x "
                "keq=0x%x.\n",
                hotKey,
                (unsigned)virtualKeyCode,
                (unsigned)modifiers,
                (unsigned)keyEquivalent);
        return post_symbolic_hotkey_keyboard_events(
            (CGKeyCode)virtualKeyCode, (CGEventFlags)modifiers);
    }

    /*
     * No usable binding: create the same style of unreachable fallback used by
     * Mac Mouse Fix. Keep it installed rather than immediately restoring the
     * old value; temporary restore can be unreliable on recent macOS releases.
     */
    CGKeyCode fallbackVKC =
        (CGKeyCode)(hotKey + kSymbolicHotKeyOutOfReachOffset);
    MGSymbolicHotKeyModifiers fallbackModifiers =
        kMGSymbolicNumericPadKeyMask | kMGSymbolicFunctionKeyMask;

    CGError enableError =
        gSymbolicHotKeyAPI.setEnabled(hotKey, true);
    CGError setError = gSymbolicHotKeyAPI.setValue(
        hotKey,
        kSymbolicHotKeyNullKeyEquivalent,
        fallbackVKC,
        fallbackModifiers);

    if (enableError != kCGErrorSuccess || setError != kCGErrorSuccess) {
        fprintf(stderr,
                "MouseGestureHelper: failed to prepare SHK %d fallback "
                "(enable=%d set=%d).\n",
                hotKey,
                enableError,
                setError);
        return false;
    }

    fprintf(stderr,
            "MouseGestureHelper: SHK %d had no usable binding; installed "
            "out-of-reach vkc=%u mods=0x%x.\n",
            hotKey,
            (unsigned)fallbackVKC,
            (unsigned)fallbackModifiers);

    return post_symbolic_hotkey_keyboard_events(
        fallbackVKC, (CGEventFlags)fallbackModifiers);
}

static void schedule_symbolic_hotkey(MGSymbolicHotKey hotKey) {
    /* Let the consumed F20 key-up finish before posting a system hot key. */
    dispatch_after(
        dispatch_time(DISPATCH_TIME_NOW, kShortcutDelayMs * NSEC_PER_MSEC),
        dispatch_get_main_queue(), ^{
            if (!gStopping && AXIsProcessTrusted()) {
                if (!post_symbolic_hotkey(hotKey)) {
                    fprintf(stderr,
                            "MouseGestureHelper: failed to post SHK %d.\n",
                            hotKey);
                }
            }
        });
}

static void handle_simple_action(MGGestureAction action) {
    if (action.type == MG_ACTION_CLICK) {
        fprintf(stderr,
                "MouseGestureHelper: CLICK -> Mission Control (SHK 32).\n");
        schedule_symbolic_hotkey(kSymbolicHotKeyMissionControl);
    } else if (action.type == MG_ACTION_HOLD) {
        fprintf(stderr,
                "MouseGestureHelper: HOLD -> App Expose (SHK 33).\n");
        schedule_symbolic_hotkey(kSymbolicHotKeyAppExpose);
    }
}

static double horizontal_scale(void) {
    NSScreen *screen = NSScreen.mainScreen;
    double width = screen ? screen.frame.size.width : 1440.0;
    return gHorizontalProgress / (width + 63.0);
}

static double vertical_scale(void) {
    NSScreen *screen = NSScreen.mainScreen;
    double height = screen ? screen.frame.size.height : 900.0;
    return gVerticalProgress / height;
}

static void handle_drag_action(MGGestureAction action) {
    if (action.type != MG_ACTION_DRAG_BEGAN &&
        action.type != MG_ACTION_DRAG_CHANGED &&
        action.type != MG_ACTION_DRAG_ENDED) {
        return;
    }

    if (!mg_dock_swipe_supported()) {
        if (action.type == MG_ACTION_DRAG_ENDED) {
            if (action.axis == MG_AXIS_HORIZONTAL) {
                if (gFallbackAccumX < 0.0) {
                    schedule_symbolic_hotkey(kSymbolicHotKeyMoveLeftASpace);
                } else if (gFallbackAccumX > 0.0) {
                    schedule_symbolic_hotkey(kSymbolicHotKeyMoveRightASpace);
                }
            } else if (action.axis == MG_AXIS_VERTICAL) {
                if (gFallbackAccumY < 0.0) {
                    schedule_symbolic_hotkey(kSymbolicHotKeyMissionControl);
                } else if (gFallbackAccumY > 0.0) {
                    schedule_symbolic_hotkey(kSymbolicHotKeyAppExpose);
                }
            }
        }
        return;
    }

    if (action.type == MG_ACTION_DRAG_ENDED) {
        mg_dock_swipe_end(action.axis, false, true);
        return;
    }

    double delta = 0.0;
    if (action.axis == MG_AXIS_HORIZONTAL) {
        delta = action.dx * horizontal_scale() * gHorizontalSign;
    } else {
        delta = action.dy * vertical_scale() * gVerticalSign;
    }

    if (action.type == MG_ACTION_DRAG_BEGAN) {
        mg_dock_swipe_begin(action.axis, delta, true);
    } else {
        mg_dock_swipe_change(action.axis, delta, true);
    }
}

static void request_stop(const char *reason) {
    if (gStopping) return;
    gStopping = true;

    fprintf(stderr, "MouseGestureHelper: stopping: %s\n", reason);

    /*
     * If an interactive Dock swipe is in flight, cancel it before leaving.
     * We inspect the gesture state before resetting it.
     */
    if (gGesture.pressed && gGesture.dragging &&
        gGesture.axis != MG_AXIS_NONE && mg_dock_swipe_supported()) {
        mg_dock_swipe_end(gGesture.axis, true, true);
    }
    if (gGesture.pressed) {
        (void)mg_gesture_release(&gGesture);
    }
    gPressTicks = 0;
    gFallbackAccumX = 0.0;
    gFallbackAccumY = 0.0;

    if (gKeyEventTap) CGEventTapEnable(gKeyEventTap, false);
    if (gPointerEventTap) CGEventTapEnable(gPointerEventTap, false);

    CFRunLoopStop(CFRunLoopGetMain());
}

static void timer_callback(CFRunLoopTimerRef timer, void *info) {
    (void)timer;
    (void)info;

    CFAbsoluteTime now = CFAbsoluteTimeGetCurrent();
    if (now >= gNextPermissionCheck) {
        gNextPermissionCheck = now + kPermissionCheckIntervalSec;

        if (!AXIsProcessTrusted()) {
            request_stop("Accessibility permission was revoked");
            return;
        }
    }

    if (gGesture.pressed) {
        MGGestureAction hold =
            mg_gesture_tick(&gGesture, elapsed_since_press_ms());
        handle_simple_action(hold);
    }
}

static void handle_tap_disabled(CFMachPortRef tap, const char *tapName) {
    if (!AXIsProcessTrusted()) {
        request_stop("event tap disabled after Accessibility permission loss");
        return;
    }

    /* Timeouts can be transient. Re-enable only while permission is still valid. */
    if (tap && !gStopping) {
        fprintf(stderr,
                "MouseGestureHelper: %s event tap disabled; re-enabling.\n",
                tapName);
        CGEventTapEnable(tap, true);
    }
}

static CGEventRef key_event_callback(CGEventTapProxy proxy,
                                     CGEventType type,
                                     CGEventRef event,
                                     void *userInfo) {
    (void)proxy;
    (void)userInfo;

    if (type == kCGEventTapDisabledByTimeout ||
        type == kCGEventTapDisabledByUserInput) {
        handle_tap_disabled(gKeyEventTap, "keyboard");
        return event;
    }

    if (gStopping || is_synthetic(event)) return event;

    if (type != kCGEventKeyDown && type != kCGEventKeyUp) return event;

    CGKeyCode keycode =
        (CGKeyCode)CGEventGetIntegerValueField(event,
                                               kCGKeyboardEventKeycode);
    if (keycode != kVK_F20) return event;

    /* Ignore keyboard auto-repeat in case F20 is ever generated by a keyboard. */
    if (type == kCGEventKeyDown &&
        CGEventGetIntegerValueField(event, kCGKeyboardEventAutorepeat) != 0) {
        return NULL;
    }

    if (type == kCGEventKeyDown) {
        if (!gGesture.pressed) {
            mg_gesture_press(&gGesture);
            gPressTicks = mach_absolute_time();
            gFallbackAccumX = 0.0;
            gFallbackAccumY = 0.0;
        }
    } else {
        double elapsed = elapsed_since_press_ms();
        MGGestureAction action = mg_gesture_release(&gGesture);

        fprintf(stderr,
                "MouseGestureHelper: F20 UP elapsed=%.1fms action=%d\n",
                elapsed,
                action.type);

        handle_simple_action(action);
        handle_drag_action(action);

        gPressTicks = 0;
        gFallbackAccumX = 0.0;
        gFallbackAccumY = 0.0;
    }

    /* F20 is an internal signal; applications never receive it. */
    return NULL;
}

static CGEventRef pointer_event_callback(CGEventTapProxy proxy,
                                         CGEventType type,
                                         CGEventRef event,
                                         void *userInfo) {
    (void)proxy;
    (void)userInfo;

    if (type == kCGEventTapDisabledByTimeout ||
        type == kCGEventTapDisabledByUserInput) {
        handle_tap_disabled(gPointerEventTap, "pointer");
        return event;
    }

    if (gStopping || is_synthetic(event) || !gGesture.pressed) return event;

    if (type == kCGEventMouseMoved ||
        type == kCGEventLeftMouseDragged ||
        type == kCGEventRightMouseDragged ||
        type == kCGEventOtherMouseDragged) {
        double dx =
            (double)CGEventGetIntegerValueField(event, kCGMouseEventDeltaX);
        double dy =
            (double)CGEventGetIntegerValueField(event, kCGMouseEventDeltaY);

        gFallbackAccumX += dx;
        gFallbackAccumY += dy;

        MGGestureAction action = mg_gesture_move(&gGesture, dx, dy);
        handle_drag_action(action);
    }

    /*
     * This tap is listen-only. Always pass the pointer event through unchanged.
     */
    return event;
}

static CFMachPortRef create_key_event_tap(void) {
    CGEventMask mask = CGEventMaskBit(kCGEventKeyDown) |
                       CGEventMaskBit(kCGEventKeyUp);

    return CGEventTapCreate(kCGSessionEventTap,
                            kCGHeadInsertEventTap,
                            kCGEventTapOptionDefault,
                            mask,
                            key_event_callback,
                            NULL);
}

static CFMachPortRef create_pointer_event_tap(void) {
    CGEventMask mask = CGEventMaskBit(kCGEventMouseMoved) |
                       CGEventMaskBit(kCGEventLeftMouseDragged) |
                       CGEventMaskBit(kCGEventRightMouseDragged) |
                       CGEventMaskBit(kCGEventOtherMouseDragged);

    return CGEventTapCreate(kCGSessionEventTap,
                            kCGHeadInsertEventTap,
                            kCGEventTapOptionListenOnly,
                            mask,
                            pointer_event_callback,
                            NULL);
}

static bool ensure_accessibility_permission(void) {
    NSDictionary *options = @{
        (__bridge NSString *)kAXTrustedCheckOptionPrompt : @YES
    };

    bool trusted = AXIsProcessTrustedWithOptions(
        (__bridge CFDictionaryRef)options);

    if (!trusted) {
        fprintf(stderr,
                "MouseGestureHelper: Accessibility permission is required.\n"
                "Enable this helper in System Settings > Privacy & Security > "
                "Accessibility, then start the helper again.\n");
    }

    return trusted;
}

static void cleanup(void) {
    gStopping = true;

    if (gGesture.pressed && gGesture.dragging &&
        gGesture.axis != MG_AXIS_NONE && mg_dock_swipe_supported()) {
        mg_dock_swipe_end(gGesture.axis, true, true);
    }

    if (gTimer) {
        CFRunLoopTimerInvalidate(gTimer);
        CFRelease(gTimer);
        gTimer = NULL;
    }

    if (gKeyEventSource) {
        CFRunLoopSourceInvalidate(gKeyEventSource);
        CFRelease(gKeyEventSource);
        gKeyEventSource = NULL;
    }

    if (gPointerEventSource) {
        CFRunLoopSourceInvalidate(gPointerEventSource);
        CFRelease(gPointerEventSource);
        gPointerEventSource = NULL;
    }

    if (gKeyEventTap) {
        CGEventTapEnable(gKeyEventTap, false);
        CFRelease(gKeyEventTap);
        gKeyEventTap = NULL;
    }

    if (gPointerEventTap) {
        CGEventTapEnable(gPointerEventTap, false);
        CFRelease(gPointerEventTap);
        gPointerEventTap = NULL;
    }
}

int main(int argc, const char *argv[]) {
    (void)argc;
    (void)argv;

    @autoreleasepool {
        double dragThreshold = env_double("MG_DRAG_THRESHOLD", 7.0);
        double holdMs = env_double("MG_HOLD_MS", 300.0);
        gHorizontalProgress = env_double("MG_HORIZONTAL_PROGRESS", 1.6);
        gVerticalProgress = env_double("MG_VERTICAL_PROGRESS", 1.0);
        gHorizontalSign = env_double("MG_HORIZONTAL_SIGN", -1.0);
        gVerticalSign = env_double("MG_VERTICAL_SIGN", 1.0);

        mg_gesture_init(&gGesture, dragThreshold, holdMs);

        if (!ensure_accessibility_permission()) {
            return 2;
        }

        gKeyEventTap = create_key_event_tap();
        if (!gKeyEventTap) {
            fprintf(stderr,
                    "MouseGestureHelper: failed to create keyboard event tap. "
                    "Check Accessibility/Input Monitoring permissions.\n");
            cleanup();
            return 3;
        }

        gPointerEventTap = create_pointer_event_tap();
        if (!gPointerEventTap) {
            fprintf(stderr,
                    "MouseGestureHelper: failed to create listen-only pointer "
                    "event tap. Check Input Monitoring permission.\n");
            cleanup();
            return 4;
        }

        gKeyEventSource = CFMachPortCreateRunLoopSource(
            kCFAllocatorDefault, gKeyEventTap, 0);
        gPointerEventSource = CFMachPortCreateRunLoopSource(
            kCFAllocatorDefault, gPointerEventTap, 0);

        if (!gKeyEventSource || !gPointerEventSource) {
            fprintf(stderr,
                    "MouseGestureHelper: failed to create event-tap run-loop "
                    "sources.\n");
            cleanup();
            return 5;
        }

        CFRunLoopRef runLoop = CFRunLoopGetCurrent();
        CFRunLoopAddSource(runLoop, gKeyEventSource, kCFRunLoopCommonModes);
        CFRunLoopAddSource(runLoop, gPointerEventSource, kCFRunLoopCommonModes);

        CGEventTapEnable(gKeyEventTap, true);
        CGEventTapEnable(gPointerEventTap, true);

        CFRunLoopTimerContext timerContext = {0, NULL, NULL, NULL, NULL};
        gTimer = CFRunLoopTimerCreate(kCFAllocatorDefault,
                                      CFAbsoluteTimeGetCurrent(),
                                      1.0 / kTimerHz,
                                      0,
                                      0,
                                      timer_callback,
                                      &timerContext);

        if (!gTimer) {
            fprintf(stderr,
                    "MouseGestureHelper: failed to create gesture timer.\n");
            cleanup();
            return 6;
        }

        CFRunLoopAddTimer(runLoop, gTimer, kCFRunLoopCommonModes);
        gNextPermissionCheck =
            CFAbsoluteTimeGetCurrent() + kPermissionCheckIntervalSec;

        fprintf(stderr,
                "MouseGestureHelper: running. click=Mission Control, "
                "horizontal drag=Spaces, DockSwipe=%s.\n",
                mg_dock_swipe_supported() ? "interactive" : "shortcut fallback");

        CFRunLoopRun();
        cleanup();
    }

    return 0;
}
