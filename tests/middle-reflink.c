#define _GNU_SOURCE
#include <sys/types.h>
#include <sys/stat.h>
#include <fcntl.h>
#include <unistd.h>
#include <stdio.h>
#include <stdlib.h>
#include <sys/ioctl.h>
#include <unistd.h>
#include <string.h>
#include <errno.h>
#include <linux/fs.h>

void fail(char *prefix) {
        fprintf(stderr, "%s: %s\n", prefix, strerror(errno));
        exit(1);
}

int main(int argc, char *argv[]) {
        int i = open(argv[1], O_RDONLY|O_NOFOLLOW);
        int o;
        int align = 1 << 12; /* assume 4k page size / block size */
        char *oname;
        struct stat is;
        struct file_clone_range fcr;
        loff_t size, pad;
        if (fstat(i, &is)) {
                fail("fstat");
        };
        fcr.src_offset = align;
        fcr.src_fd = i;
        fcr.dest_offset = 0;
        for (int i = 3; i < argc; i++) {
                if (asprintf(&oname, "%s.%d", argv[2], i) == -1) {
                        fail("unable to allocate name");
                }
                o = open(oname, O_CREAT|O_WRONLY|O_TRUNC, S_IRWXU);
                size = atoi(argv[i]);
                fcr.src_length = size;
                pad = align - (size % align);
                if (pad < align) {
                        fcr.src_length += pad;
                }
                printf("%d, %d to %s\n", fcr.src_offset, size, oname);
                if (ioctl(o, FICLONERANGE, &fcr)) {
                        fail("ioctl");
                }
                if (ftruncate(o, size)) {
                        fail("ftruncate");
                }
                fcr.src_offset += fcr.src_length;
                free(oname);
                close(o);
        }
        close(i);
}
