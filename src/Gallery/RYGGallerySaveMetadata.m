#import "RYGGallerySaveMetadata.h"
#import "RYGGalleryFile.h"

@implementation RYGGallerySaveMetadata

- (instancetype)init {
	if ((self = [super init])) {
		_source = (int16_t)RYGGallerySourceFeed;
	}
	return self;
}

- (NSDictionary *)dictionaryRepresentation {
	NSMutableDictionary *d = [NSMutableDictionary dictionary];
	if (_sourceUsername) d[@"username"] = _sourceUsername;
	if (_sourceUserPK) d[@"userPK"] = _sourceUserPK;
	if (_sourceProfileURLString) d[@"profileURL"] = _sourceProfileURLString;
	if (_sourceMediaPK) d[@"mediaPK"] = _sourceMediaPK;
	if (_sourceMediaCode) d[@"mediaCode"] = _sourceMediaCode;
	if (_sourceMediaURLString) d[@"mediaURL"] = _sourceMediaURLString;
	d[@"source"] = @(_source);
	d[@"pixelWidth"] = @(_pixelWidth);
	d[@"pixelHeight"] = @(_pixelHeight);
	d[@"duration"] = @(_durationSeconds);
	d[@"skipDedup"] = @(_skipDedup);
	return d;
}

+ (instancetype)metadataFromDictionary:(NSDictionary *)dict {
	if (![dict isKindOfClass:NSDictionary.class]) return nil;
	RYGGallerySaveMetadata *m = [self new];
	m.sourceUsername = dict[@"username"];
	m.sourceUserPK = dict[@"userPK"];
	m.sourceProfileURLString = dict[@"profileURL"];
	m.sourceMediaPK = dict[@"mediaPK"];
	m.sourceMediaCode = dict[@"mediaCode"];
	m.sourceMediaURLString = dict[@"mediaURL"];
	if (dict[@"source"]) m.source = (int16_t)[dict[@"source"] intValue];
	m.pixelWidth = (int32_t)[dict[@"pixelWidth"] intValue];
	m.pixelHeight = (int32_t)[dict[@"pixelHeight"] intValue];
	m.durationSeconds = [dict[@"duration"] doubleValue];
	m.skipDedup = [dict[@"skipDedup"] boolValue];
	return m;
}

@end
