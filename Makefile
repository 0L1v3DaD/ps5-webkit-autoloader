# WebKit Autoloader Installer - Native PS5 ELF Makefile

# Tools
PYTHON := python3
CC     := /opt/ps5-payload-sdk/bin/prospero-clang
STRIP  := /opt/ps5-payload-sdk/bin/prospero-strip

# Paths
SDK      := /opt/ps5-payload-sdk
TARGET   := $(SDK)/target
INCLUDES := -Iinclude -I$(TARGET)/include
LIBS     := $(TARGET)/lib/libmicrohttpd.a \
            -L$(TARGET)/lib -lpthread \
            -lSceNetCtl -lSceUserService -lSceSystemService \
            -lSceAppInstUtil

# Source Files
SRCS := src/main.c src/http_server.c src/app_installer.c \
        src/notification.c src/ps5_launcher.c src/log.c
ELF := installer.elf

# Generated file registry
FILE_REGISTRY_H := include/file_registry.h
FILE_REGISTRY_C := include/file_registry.c
FILE_REGISTRY_STAMP := include/.file_registry.stamp

# Generated version header (stable = base version, dev = + hash/timestamp suffix, see tools/gen_version.py)
VERSION_HEADER := include/wkali_version.h

# Frontend sources — staged into frontend/dist/ before registry generation:
#   installer-page/  → cache/progress entry page at dist root
#   autoloader/      → the actual WKAL app, served under /app/
FRONTEND_INSTALLER_PAGE := frontend/installer-page
FRONTEND_AUTOLOADER := frontend/autoloader
FRONTEND_STAGE := frontend/dist
FRONTEND_FILES := $(shell find $(FRONTEND_INSTALLER_PAGE) $(FRONTEND_AUTOLOADER) -type f 2>/dev/null)

# Generated icon assets (master: assets/icon.svg, see tools/gen_icons.py)
ICON_MASTER := assets/icon.svg
ICON0 := assets/icon0.png
ICON_ICO := assets/icon.ico
FAVICON_INSTALLER := $(FRONTEND_INSTALLER_PAGE)/favicon.svg
FAVICON_AUTOLOADER := $(FRONTEND_AUTOLOADER)/favicon.svg
LOGO_INSTALLER := $(FRONTEND_INSTALLER_PAGE)/logo.svg
LOGO_AUTOLOADER := $(FRONTEND_AUTOLOADER)/logo.svg

# Standalone PC host script (webkit-autoloader-host.py) with the autoloader embedded
WKAL_HOST := webkit-autoloader-host.py
WKAL_HOST_SOURCES := pc-host/host.py $(FRONTEND_FILES)

# Compiler Flags
CFLAGS  := -Os -Wall -ffunction-sections -fdata-sections $(INCLUDES)
LDFLAGS := -Wl,--gc-sections

all: $(ELF)

# Regenerate the version header on every build (cheap, only rewrites on change)
.PHONY: version print-version icons
version:
	$(PYTHON) tools/gen_version.py

print-version:
	@$(PYTHON) tools/gen_version.py --print

# Regenerate all derived icon assets (homescreen icon, .ico, favicons, logos)
icons: $(ICON0) $(ICON_ICO) $(FAVICON_INSTALLER) $(FAVICON_AUTOLOADER) $(LOGO_INSTALLER) $(LOGO_AUTOLOADER)

$(ICON0) $(ICON_ICO) $(FAVICON_INSTALLER) $(FAVICON_AUTOLOADER) $(LOGO_INSTALLER) $(LOGO_AUTOLOADER): $(ICON_MASTER) tools/gen_icons.py
	@echo "Generating icon assets from $(ICON_MASTER)..."
	$(PYTHON) tools/gen_icons.py

$(FILE_REGISTRY_H) $(FILE_REGISTRY_C): $(FILE_REGISTRY_STAMP)

$(FILE_REGISTRY_STAMP): $(FRONTEND_FILES) version icons
	@echo "Staging frontend into $(FRONTEND_STAGE)/..."
	rm -rf $(FRONTEND_STAGE)
	mkdir -p $(FRONTEND_STAGE)/app
	cp -R $(FRONTEND_INSTALLER_PAGE)/. $(FRONTEND_STAGE)/
	cp -R $(FRONTEND_AUTOLOADER)/. $(FRONTEND_STAGE)/app/
	@echo "Generating file registry from $(FRONTEND_STAGE)/..."
	$(PYTHON) tools/gen_file_registry.py $(FRONTEND_STAGE) $(FILE_REGISTRY_H) $(FILE_REGISTRY_C)
	@touch $(FILE_REGISTRY_STAMP)

$(ELF): $(FILE_REGISTRY_H) $(FILE_REGISTRY_C) $(SRCS) $(ICON0)
	@echo "Building $(ELF)..."
	$(CC) $(CFLAGS) $(LDFLAGS) -o $(ELF) $(SRCS) $(FILE_REGISTRY_C) $(LIBS)
	@echo "Stripping $(ELF)..."
	$(STRIP) $(ELF)

$(WKAL_HOST): $(WKAL_HOST_SOURCES) version icons
	@echo "Building $(WKAL_HOST) (embedding frontend/autoloader and overrides)..."
	$(PYTHON) tools/build_host.py --frontend $(FRONTEND_AUTOLOADER) --overrides pc-host/overrides --input pc-host/host.py --output $(WKAL_HOST)

host: $(WKAL_HOST)

# Serve the autoloader frontend locally (browser preview) with the same
# /app/ path mapping and version tokens as the real build.
.PHONY: dev
dev:
	$(PYTHON) tools/dev_server.py

clean:
	rm -rf $(FRONTEND_STAGE)
	rm -f $(ELF) $(FILE_REGISTRY_H) $(FILE_REGISTRY_C) $(FILE_REGISTRY_STAMP)
	rm -f $(WKAL_HOST) $(VERSION_HEADER)

.PHONY: all host dev clean
