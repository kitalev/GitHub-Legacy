export THEOS_DEVICE_IP =
ARCHS = armv7
TARGET = iphone:clang:9.3:6.0

include $(THEOS)/makefiles/common.mk

APPLICATION_NAME = GitHubLegacy

GitHubLegacy_FILES = main.m AppDelegate.m \
	GHTrendingClient.m \
	ExploreViewController.m \
	RepoSearchViewController.m \
	RepoOverviewViewController.m \
	RepoDetailViewController.m \
	ReleaseDetailViewController.m \
	StarredReposViewController.m \
	ProfileViewController.m \
	CommitHistoryViewController.m \
	CommitDetailViewController.m \
	ReadmeViewController.m \
	IssueListViewController.m \
	GHIssueCell.m \
	IssueDetailViewController.m \
	PullRequestListViewController.m \
	PullRequestDetailViewController.m \
	GHPullRequestCell.m \
	ForkListViewController.m \
	RepoFilesViewController.m \
	GHAPIClient.m \
	GHAuthManager.m \
	GHMarkdownRenderer.m \
	DownloadManager.m \
	SettingsViewController.m \
	GHAvatarLoader.m \
	GHThemeManager.m \
	GHIconRenderer.m \
	ProfileRepoListViewController.m \
	GHUserListViewController.m \
	GHStarredRepoCell.m \
	GHExploreFeedCell.m \
	PublicProfileViewController.m \
	TokenLoginViewController.m \
	GHLocalization.m \
	LanguageViewController.m

GitHubLegacy_FRAMEWORKS = UIKit Foundation CoreGraphics QuartzCore
GitHubLegacy_CFLAGS = -fobjc-arc -Iinclude

include $(THEOS_MAKE_PATH)/application.mk

after-install::
	install.exec "killall -9 SpringBoard"
