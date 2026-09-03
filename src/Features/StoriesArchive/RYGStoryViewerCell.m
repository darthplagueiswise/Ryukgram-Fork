#import "RYGStoryViewerCell.h"
#import "RYGStoriesArchiveManager.h"
#import "../../RYGImageCache.h"
#import "../../Settings/RYGSymbol.h"

@interface RYGStoryViewerCell ()
@property (nonatomic, strong) UIImageView *avatarView;
@property (nonatomic, strong) UIImageView *heartView;
@property (nonatomic, strong) UILabel *emojiLabel;
@property (nonatomic, strong) UIView *heartBadge;
@property (nonatomic, strong) UILabel *usernameLabel;
@property (nonatomic, strong) UIImageView *verifiedView;
@property (nonatomic, strong) UILabel *fullNameLabel;
@property (nonatomic, strong) UILabel *detailLabel;
@property (nonatomic, strong) UILabel *relationLabel;
@property (nonatomic, strong) UIStackView *trailingStack;
@property (nonatomic, strong) UIImageView *pinnedView;
@property (nonatomic, copy) NSString *avatarToken;
@end

@implementation RYGStoryViewerCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)rid {
	if (!(self = [super initWithStyle:style reuseIdentifier:rid])) return nil;
	self.backgroundColor = UIColor.clearColor;
	UIView *sel = [UIView new];
	sel.backgroundColor = [UIColor.systemGrayColor colorWithAlphaComponent:0.14];
	self.selectedBackgroundView = sel;

	UIView *avatarWrap = [UIView new];
	[avatarWrap.widthAnchor constraintEqualToConstant:48].active = YES;
	[avatarWrap.heightAnchor constraintEqualToConstant:48].active = YES;
	[avatarWrap setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];

	_avatarView = [UIImageView new];
	_avatarView.contentMode = UIViewContentModeScaleAspectFill;
	_avatarView.clipsToBounds = YES;
	_avatarView.layer.cornerRadius = 24;
	_avatarView.backgroundColor = [UIColor.systemGrayColor colorWithAlphaComponent:0.25];
	_avatarView.translatesAutoresizingMaskIntoConstraints = NO;
	[avatarWrap addSubview:_avatarView];

	// White circle behind the heart keeps it opaque over the avatar.
	_heartBadge = [UIView new];
	_heartBadge.backgroundColor = UIColor.systemBackgroundColor;
	_heartBadge.layer.cornerRadius = 10;
	_heartBadge.translatesAutoresizingMaskIntoConstraints = NO;
	_heartView = [[UIImageView alloc] initWithImage:[[UIImage systemImageNamed:@"heart.fill"] imageWithConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:11 weight:UIImageSymbolWeightBold]]];
	_heartView.tintColor = UIColor.systemRedColor;
	_heartView.contentMode = UIViewContentModeScaleAspectFit;
	_heartView.translatesAutoresizingMaskIntoConstraints = NO;
	[_heartBadge addSubview:_heartView];
	_emojiLabel = [UILabel new];
	_emojiLabel.font = [UIFont systemFontOfSize:13];
	_emojiLabel.textAlignment = NSTextAlignmentCenter;
	_emojiLabel.hidden = YES;
	_emojiLabel.translatesAutoresizingMaskIntoConstraints = NO;
	[_heartBadge addSubview:_emojiLabel];
	[avatarWrap addSubview:_heartBadge];

	[NSLayoutConstraint activateConstraints:@[
		[_avatarView.leadingAnchor constraintEqualToAnchor:avatarWrap.leadingAnchor],
		[_avatarView.trailingAnchor constraintEqualToAnchor:avatarWrap.trailingAnchor],
		[_avatarView.topAnchor constraintEqualToAnchor:avatarWrap.topAnchor],
		[_avatarView.bottomAnchor constraintEqualToAnchor:avatarWrap.bottomAnchor],
		[_heartBadge.widthAnchor constraintEqualToConstant:20],
		[_heartBadge.heightAnchor constraintEqualToConstant:20],
		[_heartBadge.centerXAnchor constraintEqualToAnchor:avatarWrap.trailingAnchor constant:-3],
		[_heartBadge.centerYAnchor constraintEqualToAnchor:avatarWrap.bottomAnchor constant:-3],
		[_heartView.centerXAnchor constraintEqualToAnchor:_heartBadge.centerXAnchor],
		[_heartView.centerYAnchor constraintEqualToAnchor:_heartBadge.centerYAnchor],
		[_emojiLabel.centerXAnchor constraintEqualToAnchor:_heartBadge.centerXAnchor],
		[_emojiLabel.centerYAnchor constraintEqualToAnchor:_heartBadge.centerYAnchor],
	]];

	_usernameLabel = [UILabel new];
	_usernameLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightSemibold];
	_usernameLabel.textColor = UIColor.labelColor;
	[_usernameLabel setContentHuggingPriority:UILayoutPriorityDefaultLow forAxis:UILayoutConstraintAxisHorizontal];

	_verifiedView = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"checkmark.seal.fill"]];
	_verifiedView.tintColor = UIColor.systemBlueColor;
	_verifiedView.contentMode = UIViewContentModeScaleAspectFit;
	[_verifiedView.widthAnchor constraintEqualToConstant:13].active = YES;
	[_verifiedView.heightAnchor constraintEqualToConstant:13].active = YES;
	[_verifiedView setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];

	UIStackView *nameLine = [[UIStackView alloc] initWithArrangedSubviews:@[_usernameLabel, _verifiedView]];
	nameLine.axis = UILayoutConstraintAxisHorizontal;
	nameLine.spacing = 4;
	nameLine.alignment = UIStackViewAlignmentCenter;

	_fullNameLabel = [UILabel new];
	_fullNameLabel.font = [UIFont systemFontOfSize:13];
	_fullNameLabel.textColor = UIColor.secondaryLabelColor;

	UIStackView *textStack = [[UIStackView alloc] initWithArrangedSubviews:@[nameLine, _fullNameLabel]];
	textStack.axis = UILayoutConstraintAxisVertical;
	textStack.spacing = 2;
	textStack.alignment = UIStackViewAlignmentLeading;
	[textStack setContentHuggingPriority:UILayoutPriorityDefaultLow forAxis:UILayoutConstraintAxisHorizontal];

	_detailLabel = [UILabel new];
	_detailLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightSemibold];
	_detailLabel.textColor = UIColor.labelColor;
	_detailLabel.textAlignment = NSTextAlignmentRight;

	_relationLabel = [UILabel new];
	_relationLabel.font = [UIFont systemFontOfSize:11 weight:UIFontWeightMedium];
	_relationLabel.textColor = UIColor.tertiaryLabelColor;
	_relationLabel.textAlignment = NSTextAlignmentRight;

	_trailingStack = [[UIStackView alloc] initWithArrangedSubviews:@[_detailLabel, _relationLabel]];
	_trailingStack.axis = UILayoutConstraintAxisVertical;
	_trailingStack.spacing = 1;
	_trailingStack.alignment = UIStackViewAlignmentTrailing;
	[_trailingStack setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
	[_trailingStack setContentCompressionResistancePriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];

	_pinnedView = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"pin.fill"]];
	_pinnedView.tintColor = UIColor.systemBlueColor;
	_pinnedView.contentMode = UIViewContentModeScaleAspectFit;
	[_pinnedView.widthAnchor constraintEqualToConstant:16].active = YES;
	[_pinnedView.heightAnchor constraintEqualToConstant:16].active = YES;
	[_pinnedView setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];

	UIStackView *root = [[UIStackView alloc] initWithArrangedSubviews:@[avatarWrap, textStack, _trailingStack, _pinnedView]];
	root.axis = UILayoutConstraintAxisHorizontal;
	root.alignment = UIStackViewAlignmentCenter;
	root.spacing = 12;
	root.translatesAutoresizingMaskIntoConstraints = NO;
	[self.contentView addSubview:root];
	[NSLayoutConstraint activateConstraints:@[
		[root.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:16],
		[root.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-16],
		[root.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:8],
		[root.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-8],
	]];
	return self;
}

- (void)prepareForReuse {
	[super prepareForReuse];
	_avatarView.image = nil;
	_avatarToken = nil;
}

- (void)configureWithViewer:(id<RYGStoryViewerDisplay>)v pinned:(BOOL)pinned {
	[self configureWithViewer:v pinned:pinned detail:nil];
}

- (void)configureWithViewer:(id<RYGStoryViewerDisplay>)v pinned:(BOOL)pinned detail:(NSString *)detail {
	self.usernameLabel.text = v.username.length ? v.username : (v.fullName.length ? v.fullName : v.pk);
	self.fullNameLabel.text = v.fullName;
	self.fullNameLabel.hidden = !v.fullName.length;
	self.verifiedView.hidden = !v.isVerified;
	BOOL reacted = v.reactionEmoji.length > 0;
	self.emojiLabel.text = reacted ? v.reactionEmoji : nil;
	self.emojiLabel.hidden = !reacted;
	self.heartView.hidden = reacted;
	self.heartBadge.hidden = !(reacted || v.liked);
	self.pinnedView.hidden = !pinned;

	NSString *rel = nil;
	if (v.following && v.followedBy) rel = RYGLocalized(@"Mutual");
	else if (v.followedBy) rel = RYGLocalized(@"Follows you");
	else if (v.following) rel = RYGLocalized(@"Following");
	self.relationLabel.text = rel;
	self.relationLabel.hidden = !rel.length;
	self.detailLabel.text = detail;
	self.detailLabel.hidden = !detail.length;

	NSString *token = v.pk;
	self.avatarToken = token;
	self.avatarView.image = [UIImage systemImageNamed:@"person.circle.fill"];
	self.avatarView.tintColor = UIColor.systemGray3Color;
	if (!v.profilePicURL.length) {
		[[RYGStoriesArchiveManager shared] queueIdentityRefreshForPK:token];
		return;
	}
	[RYGImageCache loadImageFromURL:[NSURL URLWithString:v.profilePicURL] cacheKey:v.pk completion:^(UIImage *image) {
		// A dead CDN url means the stored avatar expired — pull a fresh one.
		if (!image) { [[RYGStoriesArchiveManager shared] queueIdentityRefreshForPK:token]; return; }
		if ([self.avatarToken isEqualToString:token]) self.avatarView.image = image;
	}];
}

@end
