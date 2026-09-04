export THEOS_DEVICE_IP =
ARCHS = armv7
TARGET = iphone:clang:9.3:6.0

include $(THEOS)/makefiles/common.mk

APPLICATION_NAME = GitHubLegacy

GitHubLegacy_FILES = main.m AppDelegate.m \
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
	Controllers/PullRequestListViewController.m \
	Controllers/PullRequestDetailViewController.m \
	Cells/GHPullRequestCell.m \
	Controllers/ForkListViewController.m \
	Controllers/RepoFilesViewController.m \
	Core/GHAPIClient.m \
	Core/GHAuthManager.m \
	Core/GHMarkdownRenderer.m \
	Core/DownloadManager.m \
	Controllers/SettingsViewController.m \
	Core/GHAvatarLoader.m \
	Core/GHThemeManager.m \
	Core/GHIconRenderer.m \
	Controllers/ProfileRepoListViewController.m \
	Controllers/GHUserListViewController.m \
	Cells/GHStarredRepoCell.m \
	Cells/GHExploreFeedCell.m \
	Controllers/PublicProfileViewController.m \
	Controllers/TokenLoginViewController.m \
	Core/GHLocalization.m \
	Controllers/LanguageViewController.m

GitHubLegacy_FRAMEWORKS = UIKit Foundation CoreGraphics QuartzCore
GitHubLegacy_CFLAGS = -fobjc-arc -Iinclude -IControllers -ICells -ICore

include $(THEOS_MAKE_PATH)/application.mk

after-install::
	install.exec "killall -9 SpringBoard"

STAGED_APP  = $(THEOS_STAGING_DIR)/Applications/$(APPLICATION_NAME).app
STAGED_INFO = $(STAGED_APP)/Info.plist

after-stage::
	@if command -v plistutil >/dev/null 2>&1; then \
		plistutil -i "$(STAGED_INFO)" -o "$(STAGED_INFO).bin" >/dev/null 2>&1 && \
		mv -f "$(STAGED_INFO).bin" "$(STAGED_INFO)" && echo "[*] Info.plist -> binary"; \
	else \
		echo "[!] plistutil missing: sudo apt install libplist-utils"; \
	fi
	@find "$(THEOS_STAGING_DIR)" \( -name ".DS_Store" -o -name "._*" -o -name "Thumbs.db" \) -delete 2>/dev/null || true

ipa: package
	@rm -rf .theos/ipa && mkdir -p .theos/ipa/Payload
	@cp -a "$(STAGED_APP)" .theos/ipa/Payload/
	@rm -f "$(CURDIR)/$(APPLICATION_NAME).ipa"
	@cd .theos/ipa && zip -qr9 -X "$(CURDIR)/$(APPLICATION_NAME).ipa" Payload -x "*.DS_Store" "*__MACOSX*"
	@echo "[*] IPA: $(CURDIR)/$(APPLICATION_NAME).ipa"
