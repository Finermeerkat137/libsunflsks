#import "../include/SystemStatus.h"
#include <sys/types.h>
#include <sys/stat.h>
#include <sys/sysctl.h>
#include <stdlib.h>
#include <stdbool.h>

#define DYLIB_PATH @"/Library/MobileSubstrate/DynamicLibraries/"

static void get_proc_list(void** buf, int* proccount);

@implementation SunflsksSystemStatus

+(long long)batteryPercent {
    UIDevice* device = [UIDevice currentDevice];
	[device setBatteryMonitoringEnabled:YES];

	float battery = [device batteryLevel] * 100;

	return lroundf(battery);
}

+(NSString*)stringWithChargingStatus {
	NSString* string;
	UIDevice* device = [UIDevice currentDevice];
	[device setBatteryMonitoringEnabled:YES];

	int state = [device batteryState];

	switch (state) {
		case UIDeviceBatteryStateUnplugged: {
			string = @"unplugged";
			break;
		}

		case UIDeviceBatteryStateCharging: {
			string = @"charging";
			break;
		}

		case UIDeviceBatteryStateFull: {
			string = @"full";
			break;
		}

		default: {
			string = @"error";
			break;
		}
	}

	return string;
}

+(NSString*)stringWithUptime {
	NSMutableString* string = [NSMutableString string];
	struct timespec uptime;
	clock_gettime(CLOCK_MONOTONIC_RAW, &uptime);
	
	[string appendString:[NSString stringWithFormat:@"%lu days, %lu hours, %lu minutes, %lu seconds", (uptime.tv_sec % (86400 * 30)) / 86400, (uptime.tv_sec % 86400) / 3600, (uptime.tv_sec % 3600) / 60, uptime.tv_sec % 60]];
	return string;
}

+(long long)tweakCount {
	long long dylibCount = 0;
	NSArray* dylibs = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:DYLIB_PATH error:nil];

	for (NSURL* url in dylibs) {
		if ([[url pathExtension] isEqualToString:@"dylib"]) {
			dylibCount++;
		}
	}

	return dylibCount;
}

+(long long)packageCount {
	FILE* pipe = NULL;
	char* buffer = calloc(500, sizeof(char));
	long long ret = 0;

	pipe = popen("/usr/bin/dpkg -l | grep ii | wc -l", "r");
	if (!pipe) {
		return ret;
	}
	
	fgets(buffer, 500, pipe);
	if (!buffer) {
		return ret;
	}
	
	if (pclose(pipe) != 0) {
		free(buffer);
		return ret;
	}
	
	ret = atoll(buffer);
	free(buffer);
	return ret;
}

+(NSArray*)processes {
	NSMutableArray* array = [NSMutableArray array];
    void* buf;
	int proccount;
	
	get_proc_list(&buf, &proccount);
	struct kinfo_proc* proclist = (struct kinfo_proc*)buf;

	for (int i = 0; i < proccount; i++) {
		[array addObject:[[SunflsksProcessInfo alloc] initWithProc:proclist[i].kp_proc]];
	}

    return array;
}

+(long long)processCount {
		int proccount;
		void* buf;

		get_proc_list(&buf, &proccount);
		free(buf);

		return (long long)proccount;
}

@end

static void get_proc_list(void** buf, int* proccount) {
	size_t buffer_size = 0;
	int err;
	bool finished = false;
	// MIB for getting all running processes
	int mib[3] = {
		CTL_KERN,
		KERN_PROC,
		KERN_PROC_ALL,
	};
	do {
		// Divide sizeof mib by sizeof *mib (which is int) to get the total number of items in mib[]
		err = sysctl(mib, sizeof(mib) / sizeof(int), NULL, &buffer_size, NULL, 0);
		if (err == -1) {
			err = errno;
		}

		else if (err == 0) {
			*buf = malloc(buffer_size);
			if (*buf == NULL) {
				err = errno;
			}
		}

		if (err == 0) {
			err = sysctl(mib, sizeof(mib) / sizeof(int), *buf, &buffer_size, NULL, 0);

			if (err == -1) {
				err = errno;
			}

			else if (err == 0) {
				finished = true;
			}

			else if (errno == ENOMEM) {
				if (buf != NULL) {
					free(&buf);
				}
			}
		}
	} while (!finished);

	*proccount = buffer_size / sizeof(struct kinfo_proc);
}

@implementation SunflsksProcessInfo {
	NSString* name;
	pid_t pid;
	char niceness;
	int uptime;
}

-(SunflsksProcessInfo*)initWithProc:(struct extern_proc)proc {
	self = [super init];

	if (!self) {
		return nil;
	}

	pid = proc.p_pid;
	name = [NSString stringWithFormat:@"%s", proc.p_comm];
	niceness = proc.p_nice;
	uptime = proc.p_cpticks / sysconf(_SC_CLK_TCK);

	return self;
}

-(pid_t)pid {
	return pid;
}

-(char)niceness {
	return niceness;
}

-(int)uptime {
	return uptime;
}

-(NSString*)name {
	return name;
}

-(NSString*)description {
	return [NSString stringWithFormat:@"Name: %@, PID: %d, Niceness:%d, Uptime:%d"];
}

@end