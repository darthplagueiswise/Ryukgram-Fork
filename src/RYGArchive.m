#import "RYGArchive.h"
#import "RYGTempFiles.h"
#import <compression.h>

// Final file: 8-byte magic, then a ZLIB stream of the "tar" body below.
// Tar body entries: [u8 type][u32 pathLen][path][u64 dataLen][data], 'F' file /
// 'D' dir, terminated by a 0x00 type byte. Little-endian; same-arch round-trip.
static const uint8_t kRYGArchiveMagic[8] = { 'R', 'Y', 'U', 'K', 'B', 'A', 'K', 0x01 };
#define kRYGChunk (64 * 1024)

static NSError *rygArchiveError(NSInteger code, NSString *msg) {
	return [NSError errorWithDomain:@"com.ryukgram.archive" code:code
						   userInfo:@{ NSLocalizedDescriptionKey: msg ?: RYGLocalized(@"archive error") }];
}

@implementation RYGArchive

#pragma mark - Tar body writers

static BOOL rygWriteBytes(FILE *f, const void *buf, size_t len) {
	return len == 0 || fwrite(buf, 1, len, f) == len;
}

static BOOL rygWriteEntryHeader(FILE *f, uint8_t type, NSString *path, uint64_t dataLen) {
	const char *p = path.fileSystemRepresentation;
	uint32_t plen = (uint32_t)strlen(p);
	if (!rygWriteBytes(f, &type, 1)) return NO;
	if (!rygWriteBytes(f, &plen, sizeof(plen))) return NO;
	if (!rygWriteBytes(f, p, plen)) return NO;
	if (!rygWriteBytes(f, &dataLen, sizeof(dataLen))) return NO;
	return YES;
}

static BOOL rygCopyFileIntoTar(FILE *out, NSString *srcPath) {
	FILE *in = fopen(srcPath.fileSystemRepresentation, "rb");
	if (!in) return NO;
	uint8_t buf[kRYGChunk];
	BOOL ok = YES;
	size_t n;
	while ((n = fread(buf, 1, sizeof(buf), in)) > 0) {
		if (!rygWriteBytes(out, buf, n)) { ok = NO; break; }
	}
	if (ferror(in)) ok = NO;
	fclose(in);
	return ok;
}

static BOOL rygTarRoot(FILE *out, NSString *prefix, NSString *rootDir) {
	NSFileManager *fm = [NSFileManager defaultManager];
	BOOL isDir = NO;
	if (![fm fileExistsAtPath:rootDir isDirectory:&isDir] || !isDir) return YES; // nothing to pack

	NSDirectoryEnumerator *en = [fm enumeratorAtPath:rootDir];
	for (NSString *rel in en) {
		NSString *full = [rootDir stringByAppendingPathComponent:rel];
		NSString *arc = prefix.length ? [prefix stringByAppendingPathComponent:rel] : rel;
		NSString *type = en.fileAttributes.fileType;

		if ([type isEqualToString:NSFileTypeDirectory]) {
			if (!rygWriteEntryHeader(out, 'D', arc, 0)) return NO;
		} else if ([type isEqualToString:NSFileTypeRegular]) {
			uint64_t sz = (uint64_t)en.fileAttributes.fileSize;
			if (!rygWriteEntryHeader(out, 'F', arc, sz)) return NO;
			if (!rygCopyFileIntoTar(out, full)) return NO;
		}
		// symlinks / sockets / devices intentionally skipped
	}
	return YES;
}

#pragma mark - Compression streaming

// Stream `in` through libcompression into `out` (ENCODE / DECODE). Caller writes
// any leading magic first.
static BOOL rygStreamCompression(FILE *in, FILE *out, compression_stream_operation op) {
	compression_stream s;
	if (compression_stream_init(&s, op, COMPRESSION_ZLIB) != COMPRESSION_STATUS_OK) return NO;

	uint8_t inbuf[kRYGChunk], outbuf[kRYGChunk];
	s.src_ptr = inbuf; s.src_size = 0;
	s.dst_ptr = outbuf; s.dst_size = sizeof(outbuf);

	BOOL ok = YES, srcEof = NO;
	for (;;) {
		if (s.src_size == 0 && !srcEof) {
			size_t n = fread(inbuf, 1, sizeof(inbuf), in);
			if (ferror(in)) { ok = NO; break; }
			s.src_ptr = inbuf; s.src_size = n;
			if (n < sizeof(inbuf)) srcEof = YES;
		}

		compression_status st = compression_stream_process(&s, srcEof ? COMPRESSION_STREAM_FINALIZE : 0);

		size_t produced = sizeof(outbuf) - s.dst_size;
		if (produced && fwrite(outbuf, 1, produced, out) != produced) { ok = NO; break; }
		s.dst_ptr = outbuf; s.dst_size = sizeof(outbuf);

		if (st == COMPRESSION_STATUS_END) break;
		if (st == COMPRESSION_STATUS_ERROR) { ok = NO; break; }
	}

	compression_stream_destroy(&s);
	return ok;
}

#pragma mark - Create

+ (BOOL)createArchiveAtURL:(NSURL *)dst
				  rootDirs:(NSDictionary<NSString *, NSString *> *)rootDirs
				extraFiles:(NSDictionary<NSString *, NSData *> *)extraFiles
					 error:(NSError **)error {
	NSURL *tarURL = [RYGTempFiles claimWithExt:@"tar" ttl:300 tag:@"bak"];
	FILE *tar = fopen(tarURL.path.fileSystemRepresentation, "wb");
	if (!tar) {
		[RYGTempFiles releaseURL:tarURL];
		if (error) *error = rygArchiveError(1, RYGLocalized(@"Could not open staging file."));
		return NO;
	}

	BOOL ok = YES;
	for (NSString *arcPath in extraFiles) {
		NSData *d = extraFiles[arcPath];
		if (!rygWriteEntryHeader(tar, 'F', arcPath, (uint64_t)d.length) || !rygWriteBytes(tar, d.bytes, d.length)) {
			ok = NO; break;
		}
	}
	if (ok) {
		for (NSString *prefix in rootDirs) {
			if (!rygTarRoot(tar, prefix, rootDirs[prefix])) { ok = NO; break; }
		}
	}
	if (ok) {
		uint8_t term = 0;
		ok = rygWriteBytes(tar, &term, 1);
	}
	fclose(tar);

	if (ok) {
		FILE *in = fopen(tarURL.path.fileSystemRepresentation, "rb");
		FILE *out = fopen(dst.path.fileSystemRepresentation, "wb");
		if (!in || !out) {
			ok = NO;
		} else {
			ok = rygWriteBytes(out, kRYGArchiveMagic, sizeof(kRYGArchiveMagic)) &&
				 rygStreamCompression(in, out, COMPRESSION_STREAM_ENCODE);
		}
		if (in) fclose(in);
		if (out) fclose(out);
	}

	[RYGTempFiles releaseURL:tarURL];
	if (!ok) {
		[[NSFileManager defaultManager] removeItemAtURL:dst error:nil];
		if (error) *error = rygArchiveError(2, RYGLocalized(@"Could not write archive."));
	}
	return ok;
}

#pragma mark - Extract

+ (BOOL)dataLooksLikeArchive:(NSData *)data {
	return data.length >= sizeof(kRYGArchiveMagic) &&
		   memcmp(data.bytes, kRYGArchiveMagic, sizeof(kRYGArchiveMagic)) == 0;
}

static BOOL rygReadExact(FILE *f, void *buf, size_t len) {
	return len == 0 || fread(buf, 1, len, f) == len;
}

static BOOL rygUntar(FILE *tar, NSString *destDir, NSError **error) {
	NSFileManager *fm = [NSFileManager defaultManager];
	for (;;) {
		uint8_t type = 0;
		size_t got = fread(&type, 1, 1, tar);
		if (got == 0) break;            // tolerate missing terminator
		if (type == 0) break;           // sentinel

		uint32_t plen = 0;
		if (!rygReadExact(tar, &plen, sizeof(plen)) || plen == 0 || plen > 4096) {
			if (error) *error = rygArchiveError(3, RYGLocalized(@"Corrupt entry path."));
			return NO;
		}
		char *pbuf = malloc(plen + 1);
		if (!pbuf || !rygReadExact(tar, pbuf, plen)) {
			free(pbuf);
			if (error) *error = rygArchiveError(3, RYGLocalized(@"Truncated entry path."));
			return NO;
		}
		pbuf[plen] = 0;
		NSString *rel = [fm stringWithFileSystemRepresentation:pbuf length:plen];
		free(pbuf);

		uint64_t dlen = 0;
		if (!rygReadExact(tar, &dlen, sizeof(dlen))) {
			if (error) *error = rygArchiveError(3, RYGLocalized(@"Truncated entry length."));
			return NO;
		}

		// Reject path escapes — entries must stay under destDir.
		if (!rel.length || [rel hasPrefix:@"/"] || [rel.pathComponents containsObject:@".."]) {
			if (error) *error = rygArchiveError(4, RYGLocalized(@"Unsafe entry path."));
			return NO;
		}
		NSString *destPath = [destDir stringByAppendingPathComponent:rel];

		if (type == 'D') {
			[fm createDirectoryAtPath:destPath withIntermediateDirectories:YES attributes:nil error:nil];
			continue;
		}

		[fm createDirectoryAtPath:destPath.stringByDeletingLastPathComponent withIntermediateDirectories:YES attributes:nil error:nil];
		FILE *out = fopen(destPath.fileSystemRepresentation, "wb");
		if (!out) {
			if (error) *error = rygArchiveError(5, RYGLocalized(@"Could not write extracted file."));
			return NO;
		}
		uint8_t buf[kRYGChunk];
		uint64_t remaining = dlen;
		BOOL ok = YES;
		while (remaining > 0) {
			size_t want = remaining < sizeof(buf) ? (size_t)remaining : sizeof(buf);
			size_t n = fread(buf, 1, want, tar);
			if (n == 0 || fwrite(buf, 1, n, out) != n) { ok = NO; break; }
			remaining -= n;
		}
		fclose(out);
		if (!ok) {
			if (error) *error = rygArchiveError(5, RYGLocalized(@"Truncated entry data."));
			return NO;
		}
	}
	return YES;
}

+ (BOOL)extractArchiveAtURL:(NSURL *)src toDirectory:(NSString *)destDir error:(NSError **)error {
	FILE *in = fopen(src.path.fileSystemRepresentation, "rb");
	if (!in) {
		if (error) *error = rygArchiveError(1, RYGLocalized(@"Could not open archive."));
		return NO;
	}
	uint8_t magic[sizeof(kRYGArchiveMagic)];
	if (!rygReadExact(in, magic, sizeof(magic)) || memcmp(magic, kRYGArchiveMagic, sizeof(magic)) != 0) {
		fclose(in);
		if (error) *error = rygArchiveError(6, RYGLocalized(@"Not a RyukGram backup archive."));
		return NO;
	}

	NSURL *tarURL = [RYGTempFiles claimWithExt:@"tar" ttl:300 tag:@"bak"];
	FILE *tar = fopen(tarURL.path.fileSystemRepresentation, "wb");
	BOOL ok = NO;
	if (tar) {
		ok = rygStreamCompression(in, tar, COMPRESSION_STREAM_DECODE);
		fclose(tar);
	}
	fclose(in);

	if (ok) {
		[[NSFileManager defaultManager] createDirectoryAtPath:destDir withIntermediateDirectories:YES attributes:nil error:nil];
		FILE *rtar = fopen(tarURL.path.fileSystemRepresentation, "rb");
		if (rtar) {
			ok = rygUntar(rtar, destDir, error);
			fclose(rtar);
		} else {
			ok = NO;
		}
	} else if (error) {
		*error = rygArchiveError(7, RYGLocalized(@"Could not decompress archive."));
	}

	[RYGTempFiles releaseURL:tarURL];
	return ok;
}

@end
