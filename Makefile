CXX ?= g++
BUILD_DIR := build
PLUGIN := $(BUILD_DIR)/hypr-autoscroll.so
TEST := $(BUILD_DIR)/test-scroll-math

COMMON_FLAGS := -std=c++23 -Wall -Wextra -Wpedantic
PLUGIN_FLAGS := -O2 -shared -fPIC
HYPR_CFLAGS := $(shell pkg-config --cflags hyprland)

ifeq ($(notdir $(CXX)),g++)
PLUGIN_FLAGS += -fno-gnu-unique
endif

.PHONY: all clean test

all: $(PLUGIN)

$(BUILD_DIR):
	mkdir -p $(BUILD_DIR)

$(PLUGIN): src/main.cpp src/button_state.hpp src/control.hpp src/scroll_math.hpp | $(BUILD_DIR)
	$(CXX) $(COMMON_FLAGS) $(PLUGIN_FLAGS) $(CXXFLAGS) $(HYPR_CFLAGS) \
		src/main.cpp -o $(PLUGIN) $(LDFLAGS)

$(TEST): tests/test_scroll_math.cpp src/button_state.hpp src/control.hpp src/scroll_math.hpp | $(BUILD_DIR)
	$(CXX) $(COMMON_FLAGS) -O2 $(CXXFLAGS) tests/test_scroll_math.cpp \
		-o $(TEST) $(LDFLAGS)

test: $(TEST)
	./$(TEST)
	node tests/test_widget_model.js
	bash tests/test_set_sensitivity.sh
	bash tests/test_setup_omarchy.sh

clean:
	rm -f $(PLUGIN) $(TEST)
