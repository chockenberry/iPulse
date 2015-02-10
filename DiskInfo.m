//
//	DiskInfo.m - Disk Usage History Container Class
//


#import "sys/mount.h"
#import "string.h"
#import "mach/mach_host.h"
#import "DiskInfo.h"

void getDiskCounts(io_iterator_t drivelist, UInt64 *readCount, UInt64 *readBytes, UInt64 *writeCount, UInt64 *writeBytes);


@implementation DiskInfo


- (id)initWithCapacity:(unsigned)numItems
{
	self = [super init];
	size = numItems;
	diskdata = calloc(numItems, sizeof(DiskData));
	if (diskdata == NULL) {
		NSLog (@"Failed to allocate buffer for DiskInfo");
		return (nil);
	}
	inptr = 0;
	outptr = -1;
	return (self);
}

- (void)refresh
{
	OSErr osErr = noErr;
	int insertIndex = 0;
	int insertIndexRO = 0;
	ItemCount volumeIndex = 1;
	while (osErr == noErr)
	{
		HFSUniStr255 volumeName;
		FSVolumeInfoBitmap volumeInfoBitmap = ( kFSVolInfoSizes | kFSVolInfoBlocks | kFSVolInfoFlags | kFSVolInfoFSInfo );

		FSVolumeInfo volumeInfo;
		
		osErr = FSGetVolumeInfo(kFSInvalidVolumeRefNum, volumeIndex,
				NULL, volumeInfoBitmap, &volumeInfo, &volumeName, NULL);
		
		if (osErr == noErr)
		{
			//NSLog(@"flags: %x,  %llu free bytes, %lu block size, type %d ", volumeInfo.flags, volumeInfo.freeBytes, volumeInfo.blockSize, volumeInfo.filesystemID);

			char *typeString = NULL;

			switch (volumeInfo.signature)
			{
			default:
				break;
			case 0x4244: // 'BD'
				switch (volumeInfo.filesystemID)
				{
				case 0x0:
					typeString = "hfs";
					break;
				case 0x4953: // 'IS'
					typeString = "msdos";
					break;
				case 0x6375: // 'cu'
					typeString = "smb";
					break;
				case 0x4a48: // 'JH'
					typeString = "Audio";
					break;
				}
				break;
			case 0x4e54: // 'NT'
				typeString = "ntfs";
				break;
			case 0x482b: // 'H+'
				switch (volumeInfo.filesystemID)
				{
				default:
					typeString = "hfs+";
					break;
				case 0x6173: // 'as'
					typeString = "afp";
					break;
				}
				break;
			case 0xd2d7:
				typeString = "mfs";
				break;
			case 0x4147: // 'AG'
				typeString = "ISO9660";
				break;
			case 0x4242: // 'BB'
				typeString = "hs"; // HighSierra won't fit!
				break;
			case  0x4a48: // 'JH'
				typeString = "Audio";
				break;
			case 0x75df:
				typeString = "DVD"; // DVD-ROM won't fit!
				break;
			case 0x4b48: // 'KH'
				typeString = "ufs";
				break;
			case 0x4e4a: // 'NJ'
				typeString = "nfs";
				break;
			case 0x4341: // 'CA'
				typeString = "dav"; // WebDAV won't fit!
				break;
			}

			if (! (volumeInfo.flags & (kFSVolFlagHardwareLockedMask | kFSVolFlagSoftwareLockedMask)))
			{
				if (insertIndex < MAX_DISK_COUNT && volumeInfo.totalBlocks > 0)
				{
					// add the unlocked volume
					if (volumeInfo.blockSize > INT_MAX)
					{
						// not a valid block size (because it's probably unknown like with WebDAV)
						diskdata[inptr].unlocked.blockSize[insertIndex] = 0;
						diskdata[inptr].unlocked.freeBlocks[insertIndex] = 0;
						diskdata[inptr].unlocked.availableBlocks[insertIndex] = 0;
					}
					else
					{
						diskdata[inptr].unlocked.blockSize[insertIndex] = volumeInfo.blockSize;
						diskdata[inptr].unlocked.freeBlocks[insertIndex] = volumeInfo.freeBlocks;
						diskdata[inptr].unlocked.availableBlocks[insertIndex] = volumeInfo.totalBlocks;
					}
					diskdata[inptr].unlocked.used[insertIndex] = 1.0 - ((double)volumeInfo.freeBlocks / (double)volumeInfo.totalBlocks);

					diskdata[inptr].unlocked.fsMountName[insertIndex] = volumeName;
					if (typeString != NULL)
					{
						strcpy(diskdata[inptr].unlocked.fsTypeName[insertIndex], typeString);
					}
					else
					{
						sprintf(diskdata[inptr].unlocked.fsTypeName[insertIndex], "0x%04x 0x%04x", volumeInfo.filesystemID, volumeInfo.signature);
					}
					insertIndex += 1;
				}
			}
			else
			{
				if (insertIndexRO < MAX_DISK_COUNT && volumeInfo.totalBlocks > 0)
				{
					// add the locked volume
					
					if (volumeInfo.blockSize > INT_MAX)
					{
						// not a valid block size (because it's probably unknown like with WebDAV)
						diskdata[inptr].unlocked.blockSize[insertIndex] = 0;
						diskdata[inptr].unlocked.freeBlocks[insertIndex] = 0;
						diskdata[inptr].unlocked.availableBlocks[insertIndex] = 0;
					}
					else
					{
						diskdata[inptr].locked.blockSize[insertIndexRO] = volumeInfo.blockSize;
						diskdata[inptr].locked.freeBlocks[insertIndexRO] = volumeInfo.freeBlocks;
						diskdata[inptr].locked.availableBlocks[insertIndexRO] = volumeInfo.totalBlocks;
					}
					diskdata[inptr].locked.used[insertIndexRO] = 1.0 - ((double)volumeInfo.freeBlocks / (double)volumeInfo.totalBlocks);

					diskdata[inptr].locked.fsMountName[insertIndexRO] = volumeName;
					if (typeString != NULL)
					{
						strcpy(diskdata[inptr].locked.fsTypeName[insertIndexRO], typeString);
					}
					else
					{
						sprintf(diskdata[inptr].locked.fsTypeName[insertIndexRO], "0x%04x 0x%04x", volumeInfo.filesystemID, volumeInfo.signature);
					}
					insertIndexRO += 1;
				}
			}
		}

		volumeIndex += 1;
	}

	diskdata[inptr].unlocked.count = insertIndex;
	diskdata[inptr].locked.count = insertIndexRO;


	mach_port_t masterPort;
	io_iterator_t drivelist;
	UInt64 readCount;
	UInt64 readBytes;
	UInt64 writeCount;
	UInt64 writeBytes;

	IOMasterPort(MACH_PORT_NULL, &masterPort);
	IOServiceGetMatchingServices(masterPort, IOServiceMatching("IOBlockStorageDriver"), &drivelist);
	getDiskCounts(drivelist, &readCount, &readBytes, &writeCount, &writeBytes);
	IOObjectRelease(drivelist);
	mach_port_deallocate(mach_task_self(), masterPort);

	// current counts can be lower than last counts if a disk is unmounted -- if they are, ignore sample
	SInt64 readCountDelta = readCount - lastReadCount;
	SInt64 readBytesDelta = readBytes - lastReadBytes;
	SInt64 writeCountDelta = writeCount - lastWriteCount;
	SInt64 writeBytesDelta = writeBytes - lastWriteBytes;	
	if (readCountDelta < 0 || readBytesDelta < 0 || writeCountDelta < 0 || writeBytesDelta < 0)
	{
		readCountDelta = 0;
		readBytesDelta = 0;
		writeCountDelta = 0;
		writeBytesDelta = 0;
	}
	diskdata[inptr].readCount = readCountDelta;
	diskdata[inptr].readBytes = readBytesDelta;
	diskdata[inptr].writeCount = writeCountDelta;
	diskdata[inptr].writeBytes = writeBytesDelta;

	
	//NSLog(@"read: count = %llu bytes = %llu  write: count = %llu bytes = %llu", diskdata[inptr].readCount, diskdata[inptr].readBytes, diskdata[inptr].writeCount, diskdata[inptr].writeBytes);
		
	lastReadCount = readCount;
	lastReadBytes = readBytes;
	lastWriteCount = writeCount;
	lastWriteBytes = writeBytes;

	if (++inptr >= size)
		inptr = 0;
}

- (void)startIterate
{
	outptr = inptr;
}


- (BOOL)getNext:(DiskDataPtr)ptr
{
	if (outptr == -1)
		return (FALSE);
	*ptr = diskdata[outptr++];
	if (outptr >= size)
		outptr = 0;
	if (outptr == inptr)
		outptr = -1;
	return (TRUE);
}

- (void)getCurrent:(DiskDataPtr)ptr
{
	*ptr = diskdata[inptr ? inptr - 1 : size - 1];
}

- (void)getLast:(DiskDataPtr)ptr
{
	*ptr = diskdata[inptr > 1 ? inptr - 2 : size + inptr - 2];
}


- (int)getSize
{
	return (size);
}


void getDiskCounts(io_iterator_t drivelist, UInt64 *readCount, UInt64 *readBytes, UInt64 *writeCount, UInt64 *writeBytes)
{
	io_registry_entry_t drive = 0; // needs release
	UInt64 totalReadBytes  = 0;
	UInt64 totalReadCount  = 0;
	UInt64 totalWriteBytes = 0;
	UInt64 totalWriteCount = 0;

	kern_return_t status = 0;
	Boolean ok;
	
	while ((drive = IOIteratorNext(drivelist)))
	{
		CFNumberRef number = 0;  // don't release
		CFDictionaryRef properties = 0;  // needs release
		CFDictionaryRef statistics = 0;  // don't release
		UInt64 value = 0;

		// obtain the properties for this drive object
		status = IORegistryEntryCreateCFProperties(drive, (CFMutableDictionaryRef *) &properties, kCFAllocatorDefault, kNilOptions);
		if (status == KERN_SUCCESS)
		{
			// obtain the statistics from the drive properties
			statistics = (CFDictionaryRef) CFDictionaryGetValue(properties, CFSTR(kIOBlockStorageDriverStatisticsKey));
			if (statistics)
			{
				// obtain the number of bytes read from the drive statistics
				number = (CFNumberRef)CFDictionaryGetValue(statistics, CFSTR(kIOBlockStorageDriverStatisticsBytesReadKey));
				if (number)
				{
					ok = CFNumberGetValue(number, kCFNumberSInt64Type, &value);
					if (ok)
					{
						totalReadBytes += value;
						//NSLog(@"readBytes = %llu", value);
					}
				}
				// obtain the number of reads from the drive statistics
				number = (CFNumberRef)CFDictionaryGetValue(statistics, CFSTR(kIOBlockStorageDriverStatisticsReadsKey));
				if (number)
				{
					ok = CFNumberGetValue(number, kCFNumberSInt64Type, &value);
					if (ok)
					{
						totalReadCount += value;
						//NSLog(@"readCount = %llu", value);
					}
				}

				// obtain the number of writes from the drive statistics
				number = (CFNumberRef) CFDictionaryGetValue (statistics, CFSTR(kIOBlockStorageDriverStatisticsWritesKey));
				if (number)
				{
					ok = CFNumberGetValue(number, kCFNumberSInt64Type, &value);
					if (ok)
					{
						totalWriteCount += value;
						//NSLog(@"writeCount = %llu", value);
					}
				}
				// obtain the number of bytes written from the drive statistics
				number = (CFNumberRef) CFDictionaryGetValue (statistics, CFSTR(kIOBlockStorageDriverStatisticsBytesWrittenKey));
				if (number)
				{
					ok = CFNumberGetValue(number, kCFNumberSInt64Type, &value);
					if (ok)
					{
						totalWriteBytes += value;
						//NSLog(@"writeBytes = %llu", value);
					}
				}
			}
			
			CFRelease(properties);
			properties = 0;
		}
		
		IOObjectRelease(drive);
	}
	IOIteratorReset(drivelist);

	//NSLog(@"totalReadBytes = %llu, totalReadCount = %llu, totalWriteBytes = %llu, totalWriteCount = %llu", totalReadBytes, totalReadCount, totalWriteBytes, totalWriteCount);

	*readBytes = totalReadBytes;
	*readCount = totalReadCount;
	*writeBytes = totalWriteBytes;
	*writeCount = totalWriteCount;
}


@end
