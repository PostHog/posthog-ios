// https://github.com/nicklockwood/GZIP/blob/master/GZIP/NSData%2BGZIP.m

#import <zlib.h>
#import <dlfcn.h>
#import "NSData+PHGGZIP.h"
#import "NSData+PHGGUNZIPP.h"


@implementation NSData (PHGGUNZIPP)

- (NSData *)phg_gunzippedData
{
    if (self.length == 0 || ![self phg_isGzippedData]) {
        return self;
    }

    void *libz = phg_libzOpen();
    int (*inflateInit2_)(z_streamp, int, const char *, int) =
        (int (*)(z_streamp, int, const char *, int))dlsym(libz, "inflateInit2_");
    int (*inflate)(z_streamp, int) = (int (*)(z_streamp, int))dlsym(libz, "inflate");
    int (*inflateEnd)(z_streamp) = (int (*)(z_streamp))dlsym(libz, "inflateEnd");

    z_stream stream;
    stream.zalloc = Z_NULL;
    stream.zfree = Z_NULL;
    stream.avail_in = (uint)self.length;
    stream.next_in = (Bytef *)self.bytes;
    stream.total_out = 0;
    stream.avail_out = 0;

    NSMutableData *output = nil;
    if (inflateInit2(&stream, 47) == Z_OK) {
        int status = Z_OK;
        output = [NSMutableData dataWithCapacity:self.length * 2];
        while (status == Z_OK) {
            if (stream.total_out >= output.length) {
                output.length += self.length / 2;
            }
            stream.next_out = (uint8_t *)output.mutableBytes + stream.total_out;
            stream.avail_out = (uInt)(output.length - stream.total_out);
            status = inflate(&stream, Z_SYNC_FLUSH);
        }
        if (inflateEnd(&stream) == Z_OK) {
            if (status == Z_STREAM_END) {
                output.length = stream.total_out;
            }
        }
    }

    return output;
}


@end
