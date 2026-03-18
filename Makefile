THEOS_DEVICE_IP ?= localhost
THEOS_DEVICE_PORT ?= 2222

TARGET := iphone:clang:latest:14.0
ARCHS = arm64

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = VLCrawler

VLCrawler_FILES = \
	Tweak.x \
	VLCrawler.m \
	VLCrawlerResultsVC.m \
	VLCrawlerSettingsVC.m

VLCrawler_CFLAGS = -fobjc-arc -Wno-unused-variable
VLCrawler_FRAMEWORKS = UIKit AVKit AVFoundation Foundation
VLCrawler_PRIVATE_FRAMEWORKS =

# Inject into VidList only
VLCrawler_BUNDLE_ID = com.vh.vhub

include $(THEOS)/makefiles/tweak.mk
