.PHONY: all test deps fmt fmt-check lint clean help

NVIM ?= nvim
PLENARY_DIR ?= .ci/plenary.nvim
XML2LUA_DIR ?= .ci/xml2lua.nvim
TEST_DIR = tests
MINIMAL_INIT = tests/minimal_init.lua
LOCAL_BIN ?= $(HOME)/.local/bin
CI_BIN ?= $(CURDIR)/.ci/bin
LUACHECK_BIN ?= $(shell command -v luacheck 2>/dev/null || ( [ -x "$(LOCAL_BIN)/luacheck" ] && echo "$(LOCAL_BIN)/luacheck" ) || ( [ -x "$(CI_BIN)/luacheck" ] && echo "$(CI_BIN)/luacheck" ))

all: test

help:
	@echo "Available targets:"
	@echo "  make test                 Run all tests"
	@echo "  make test FILE=<path>     Run a single test file (e.g. make test FILE=tests/webdav_spec.lua)"
	@echo "  make deps                 Install test dependencies (plenary.nvim, xml2lua.nvim, and luacheck)"
	@echo "  make fmt                  Format Lua files with stylua"
	@echo "  make fmt-check            Check Lua formatting with stylua"
	@echo "  make lint                 Lint Lua files with luacheck"
	@echo "  make clean                Clean temporary cloned dependencies"

deps:
	@if [ ! -d "$(PLENARY_DIR)" ]; then \
		echo "Cloning plenary.nvim into $(PLENARY_DIR)..."; \
		git clone --depth 1 https://github.com/nvim-lua/plenary.nvim $(PLENARY_DIR); \
	else \
		echo "plenary.nvim already present at $(PLENARY_DIR)"; \
	fi
	@if [ ! -d "$(XML2LUA_DIR)" ]; then \
		echo "Cloning xml2lua.nvim into $(XML2LUA_DIR)..."; \
		git clone --depth 1 https://github.com/a-usr/xml2lua.nvim $(XML2LUA_DIR); \
	else \
		echo "xml2lua.nvim already present at $(XML2LUA_DIR)"; \
	fi
	@if command -v luacheck >/dev/null 2>&1; then \
		echo "luacheck is already installed at $$(command -v luacheck)"; \
	elif [ -x "$(LOCAL_BIN)/luacheck" ]; then \
		echo "luacheck is already installed at $(LOCAL_BIN)/luacheck"; \
	elif [ -x "$(CI_BIN)/luacheck" ]; then \
		echo "luacheck is already installed at $(CI_BIN)/luacheck"; \
	elif [ "$$(uname -s)" = "Linux" ] && [ "$$(uname -m)" = "x86_64" ]; then \
		echo "Downloading standalone luacheck binary for Linux x86_64..."; \
		mkdir -p "$(LOCAL_BIN)"; \
		if curl -sSL "https://github.com/lunarmodules/luacheck/releases/download/v1.2.0/luacheck" -o "$(LOCAL_BIN)/luacheck" && chmod +x "$(LOCAL_BIN)/luacheck"; then \
			echo "luacheck installed to $(LOCAL_BIN)/luacheck"; \
		else \
			mkdir -p "$(CI_BIN)"; \
			curl -sSL "https://github.com/lunarmodules/luacheck/releases/download/v1.2.0/luacheck" -o "$(CI_BIN)/luacheck"; \
			chmod +x "$(CI_BIN)/luacheck"; \
			echo "luacheck installed to $(CI_BIN)/luacheck"; \
		fi; \
	elif command -v brew >/dev/null 2>&1; then \
		echo "Installing luacheck via Homebrew..."; \
		brew install luacheck; \
	elif command -v luarocks >/dev/null 2>&1; then \
		echo "Installing luacheck via LuaRocks..."; \
		luarocks install luacheck; \
	else \
		echo "Could not auto-install luacheck for $$(uname -s)-$$(uname -m). Please install luarocks or brew."; \
	fi

test:
ifdef FILE
	$(NVIM) --headless -u $(MINIMAL_INIT) -c "PlenaryBustedFile $(FILE)"
else
	$(NVIM) --headless -u $(MINIMAL_INIT) -c "PlenaryBustedDirectory $(TEST_DIR) {minimal_init = '$(MINIMAL_INIT)', sequential = true}"
endif

fmt:
	@if command -v stylua >/dev/null 2>&1; then \
		stylua .; \
	elif command -v npx >/dev/null 2>&1; then \
		npx --yes @johnnymorganz/stylua-bin .; \
	else \
		echo "Error: stylua is not installed. Install stylua or npm/npx."; exit 1; \
	fi

fmt-check:
	@if command -v stylua >/dev/null 2>&1; then \
		stylua --check .; \
	elif command -v npx >/dev/null 2>&1; then \
		npx --yes @johnnymorganz/stylua-bin --check .; \
	else \
		echo "Error: stylua is not installed. Install stylua or npm/npx."; exit 1; \
	fi

lint:
	@if [ -n "$(LUACHECK_BIN)" ]; then \
		$(LUACHECK_BIN) lua tests --config .luacheckrc; \
	else \
		echo "Error: luacheck is not installed. Run 'make deps' to install it."; exit 1; \
	fi

clean:
	rm -rf $(PLENARY_DIR) $(XML2LUA_DIR) $(CI_BIN)
