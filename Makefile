CC ?= cc
CFLAGS ?= -std=c11 -Wall -Wextra -Werror -O2
TEST_DIR := build/tests

.PHONY: test check mac-build clean

test: $(TEST_DIR)/test_gesture_logic
	$(TEST_DIR)/test_gesture_logic

$(TEST_DIR):
	mkdir -p $(TEST_DIR)

$(TEST_DIR)/test_gesture_logic: tests/test_gesture_logic.c src/GestureLogic.c src/GestureLogic.h | $(TEST_DIR)
	$(CC) $(CFLAGS) tests/test_gesture_logic.c src/GestureLogic.c -lm -o $@

check: test
	python3 -m json.tool karabiner/button3-to-f20.json >/dev/null
	python3 tests/check_karabiner.py
	python3 tests/check_no_smooth_scroll.py
	python3 -c "import plistlib; plistlib.load(open('scripts/com.local.mousegesture-helper.plist.template', 'rb'))"
	bash -n scripts/build.sh scripts/install.sh scripts/uninstall.sh

mac-build:
	./scripts/build.sh

clean:
	rm -rf build
