export THEOS_DEVICE_IP =
ifeq ($(THEOS_PACKAGE_SCHEME),rootless)
ARCHS = arm64
GitHubLegacySafariRedirect_ARCHS = arm64 arm64e
else
ARCHS = armv6 armv7 arm64
GitHubLegacySafariRedirect_ARCHS = armv7 arm64 arm64e
endif
TARGET = iphone:clang:9.3:4.0
THEOS_PLATFORM_DEB_COMPRESSION_TYPE = gzip
THEOS_PLATFORM_DEB_COMPRESSION_LEVEL = 6

ARMV6_SDK = $(CURDIR)/.theos/armv6/iPhoneOS9.3.sdk
ifneq ($(filter armv6,$(ARCHS)),)
$(shell if [ ! -f "$(ARMV6_SDK)/.ready" ]; then \
	rm -rf "$(ARMV6_SDK)" && mkdir -p "$(dir $(ARMV6_SDK))" && \
	cp -a "$(THEOS)/sdks/iPhoneOS9.3.sdk" "$(ARMV6_SDK)" && \
	mkdir -p "$(ARMV6_SDK)/VendorFrameworks" && \
	cp -a "$(THEOS)/vendor/lib/CydiaSubstrate.framework" "$(ARMV6_SDK)/VendorFrameworks/" && \
	find "$(ARMV6_SDK)" -name '*.tbd' -exec perl -pi -e 's/(?<=[\[ ])armv7(?=\s*[,\]])/armv6, armv7/g' {} + && \
	touch "$(ARMV6_SDK)/.ready"; \
fi)
endif

LEGACY_ARCH_TARGET = $(if $(filter arm64 arm64e,$(THEOS_CURRENT_ARCH)),-target $(THEOS_CURRENT_ARCH)-apple-ios5.0)
LEGACY_ARCH_CFLAGS = $(LEGACY_ARCH_TARGET) $(if $(filter armv6,$(THEOS_CURRENT_ARCH)),-isysroot $(ARMV6_SDK) -marm)
LEGACY_ARCH_LDFLAGS = $(LEGACY_ARCH_TARGET) $(if $(filter armv6,$(THEOS_CURRENT_ARCH)),-isysroot $(ARMV6_SDK) -F$(ARMV6_SDK)/VendorFrameworks)

include $(THEOS)/makefiles/common.mk

APPLICATION_NAME = GitHubLegacy

GitHubLegacy_FILES = main.m AppDelegate.m Core/GHLegacyStart.m \
	Core/GHTrendingClient.m \
	Controllers/ExploreViewController.m \
	Controllers/RepoSearchViewController.m \
	Controllers/RepoOverviewViewController.m \
	Controllers/RepoDetailViewController.m \
	Controllers/ReleaseDetailViewController.m \
	Controllers/StarredReposViewController.m \
	Controllers/ProfileViewController.m \
	Controllers/CommitHistoryViewController.m \
	Controllers/CommitDetailViewController.m \
	Controllers/ReadmeViewController.m \
	Controllers/IssueListViewController.m \
	Cells/GHIssueCell.m \
	Controllers/IssueDetailViewController.m \
	Controllers/IssueTemplatePickerViewController.m \
	Controllers/NewIssueViewController.m \
	Controllers/GHFileBrowserViewController.m \
	Core/GHAttachmentUploader.m \
	Core/GHWebSession.m \
	Controllers/WebLoginViewController.m \
	Core/GHIssueTemplate.m \
	Core/GHYAMLParser.m \
	Controllers/PullRequestListViewController.m \
	Controllers/PullRequestDetailViewController.m \
	Cells/GHPullRequestCell.m \
	Controllers/ForkListViewController.m \
	Controllers/RepoFilesViewController.m \
	Core/GHAPIClient.m \
	Core/GHAuthManager.m \
	Core/GHDeviceLogin.m \
	Core/GHLoginSuccessView.m \
	Core/GHProfileHeaderView.m \
	Core/GHRepoHeaderView.m \
	Core/GHTimelineRenderer.m \
	Controllers/GHProfileBaseViewController.m \
	Cells/GHPinnedReposCell.m \
	Core/GHMarkdownRenderer.m \
	Core/DownloadManager.m \
	Controllers/SettingsViewController.m \
	Core/GHAvatarLoader.m \
	Core/GHThemeManager.m \
	Core/GHIconRenderer.m \
	Core/GHCompat.m \
	Core/GHLegacyRefreshControl.m \
	Core/GHFoundationCompat.m \
	Core/GHARCLite.m \
	Core/GHLegacyPolyfills.m \
	Core/GHJSONSerialization.m \
	Core/GHURLRouter.m \
	Controllers/ProfileRepoListViewController.m \
	Controllers/GHUserListViewController.m \
	Cells/GHStarredRepoCell.m \
	Cells/GHExploreFeedCell.m \
	Controllers/PublicProfileViewController.m \
	Controllers/TokenLoginViewController.m \
	Controllers/DeviceLoginViewController.m \
	Controllers/SignInOptionsViewController.m \
	Core/GHLocalization.m \
	Core/GHQRCode.m \
	Core/GHRecentRepos.m \
	Controllers/LanguageViewController.m

GitHubLegacy_FRAMEWORKS = UIKit Foundation CoreGraphics QuartzCore
GitHubLegacy_CFLAGS = -fobjc-arc -fobjc-runtime=ios-5.0 -Iinclude -IControllers -ICells -ICore $(LEGACY_ARCH_CFLAGS)
GitHubLegacy_LDFLAGS = $(LEGACY_ARCH_LDFLAGS)
Core/GHARCLite.m_CFLAGS = -fno-objc-arc
Core/GHLegacyPolyfills.m_CFLAGS = -fno-objc-arc
ifneq ($(PACKAGE_FORMAT),ipa)
GitHubLegacy_CODESIGN_FLAGS = -Sentitlements.plist
endif

include $(THEOS_MAKE_PATH)/application.mk


TWEAK_NAME = GitHubLegacySafariRedirect
GitHubLegacySafariRedirect_FILES = Tweak/Tweak.xm Core/GHARCLite.m
GitHubLegacySafariRedirect_FRAMEWORKS = UIKit
GitHubLegacySafariRedirect_CFLAGS = -fobjc-arc -fobjc-runtime=ios-5.0 $(LEGACY_ARCH_CFLAGS)
GitHubLegacySafariRedirect_LDFLAGS = $(LEGACY_ARCH_LDFLAGS)
include $(THEOS_MAKE_PATH)/tweak.mk

after-install::
	install.exec "killall -9 SpringBoard"

STAGED_APP  = $(THEOS_STAGING_DIR)/Applications/$(APPLICATION_NAME).app
STAGED_INFO = $(STAGED_APP)/Info.plist

after-stage::
	@if command -v plistutil >/dev/null 2>&1; then \
		plistutil -i "$(STAGED_INFO)" -o "$(STAGED_INFO).bin" >/dev/null 2>&1 && \
		mv -f "$(STAGED_INFO).bin" "$(STAGED_INFO)" && echo "[*] Info.plist -> binary"; \
	else \
		echo "[!] plistutil not found: sudo apt install libplist-utils"; \
	fi
	@find "$(THEOS_STAGING_DIR)" \( -name '.DS_Store' -o -name '._*' -o -name 'Thumbs.db' \) -delete 2>/dev/null || true
	@chmod -R go-w "$(STAGED_APP)"

ipa: package
	@rm -rf .theos/ipa && mkdir -p .theos/ipa/Payload
	@cp -a "$(STAGED_APP)" .theos/ipa/Payload/
	@rm -f "$(CURDIR)/$(APPLICATION_NAME).ipa"
	@cd .theos/ipa && zip -qr9 -X "$(CURDIR)/$(APPLICATION_NAME).ipa" Payload -x "*.DS_Store" "*__MACOSX*"
	@echo "[*] IPA: $(CURDIR)/$(APPLICATION_NAME).ipa"
