//
//  KTMediaFile.m
//  Marvel
//
//  Created by Mike on 05/11/2007.
//  Copyright 2007 Karelia Software. All rights reserved.
//

#import "KTMediaFile.h"
#import "KTInDocumentMediaFile.h"
#import "KTExternalMediaFile.h"

#import "KTMediaManager.h"
#import "KTMediaPersistentStoreCoordinator.h"
#import "KTMediaFileUpload.h"

#import "NSManagedObject+KTExtensions.h"
#import "NSManagedObjectContext+KTExtensions.h"
#import "NSObject+Karelia.h"
#import "NSSortDescriptor+Karelia.h"
#import "NSString+Karelia.h"

#import "BDAlias.h"
#import <QTKit/QTKit.h>

#import "Debug.h"


@interface KTMediaFile ( Private )
- (KTMediaFileUpload *)insertUploadToPath:(NSString *)path;
- (NSString *)uniqueUploadPath:(NSString *)preferredPath;
@end


#pragma mark -


@implementation KTMediaFile

#pragma mark -
#pragma mark Init

+ (void)initialize
{
	[self setKeys:[NSArray arrayWithObjects:@"filename", @"storageType", nil]
		triggerChangeNotificationsForDependentKey:@"currentPath"];
}

+ (id)insertNewMediaFileWithPath:(NSString *)path inManagedObjectContext:(NSManagedObjectContext *)moc;
{
	id result = [NSEntityDescription insertNewObjectForEntityForName:[self entityName]
											  inManagedObjectContext:moc];
	
	[result setValue:[NSString UUIDString] forKey:@"uniqueID"];
	[result setFileType:[NSString UTIForFileAtPath:path]];
	
	
	// If the file is an image, also store the dimensions when possible
	if ([NSString UTI:[result fileType] conformsToUTI:(NSString *)kUTTypeImage])
	{
		[result cacheImageDimensions];
	}
	
	
	return result;
}

#pragma mark -
#pragma mark Core Data

+ (NSString *)entityName { return @"AbstractMediaFile"; }

#pragma mark -
#pragma mark Accessors

- (KTMediaManager *)mediaManager
{
	KTMediaManager *result = [(KTMediaPersistentStoreCoordinator *)[[self managedObjectContext] persistentStoreCoordinator] mediaManager];
	OBPOSTCONDITION(result);
	return result;
}

- (NSString *)fileType { return [self primitiveValueForKey:@"fileType"]; }

- (void)setFileType:(NSString *)UTI
{
	[self setPrimitiveValue:UTI forKey:@"fileType"];
}

- (NSString *)filename
{
    SUBCLASSMUSTIMPLEMENT;
    return nil;
}

- (NSString *)filenameExtension
{
    SUBCLASSMUSTIMPLEMENT;
    return nil;
}

#pragma mark -
#pragma mark Paths

/*	The path where the underlying filesystem object is being kept.
 */
- (NSString *)currentPath
{
	NSString *result = [self _currentPath];
    if (!result)
    {
        result = [[NSBundle mainBundle] pathForImageResource:@"qmark"];
    }
    
	return result;
}

- (NSString *)_currentPath
{
	SUBCLASSMUSTIMPLEMENT;
	return nil;
}

/*	Subclasses implement this to return a <!svxData> pseudo-tag for Quick Look previews
 */
- (NSString *)quickLookPseudoTag
{
	SUBCLASSMUSTIMPLEMENT;
	return nil;
}

- (NSString *)preferredFileName
{
	SUBCLASSMUSTIMPLEMENT;
	return nil;
}

#pragma mark -
#pragma mark Uploading

- (KTMediaFileUpload *)defaultUpload
{
	// Create a MediaFileUpload object if needed
	KTMediaFileUpload *result = [[self valueForKey:@"uploads"] anyObject];
	
	if (!result || [result isDeleted])
	{
		// Find a unique path to upload to
		NSString *sourceFilename = nil;
		if ([self isKindOfClass:[KTInDocumentMediaFile class]])
        {
			sourceFilename = [self valueForKey:@"sourceFilename"];
		}
		else
        {
			sourceFilename = [[[(KTExternalMediaFile *)self alias] fullPath] lastPathComponent];
		}
		
		NSString *preferredFileName = [[sourceFilename stringByDeletingPathExtension] legalizedWebPublishingFileName];
        NSString *preferredFilename = [preferredFileName stringByAppendingPathExtension:[sourceFilename pathExtension]];
        
        NSString *mediaDirectoryPath = [[NSUserDefaults standardUserDefaults] valueForKey:@"DefaultMediaPath"];
		NSString *preferredUploadPath = [mediaDirectoryPath stringByAppendingPathComponent:preferredFilename];
		
        NSString *uploadPath = [self uniqueUploadPath:preferredUploadPath];
		result = [self insertUploadToPath:uploadPath];
	}
    
    
    OBASSERT(result);
    
    
    // Make sure the result is a valid upload. If not, correct the path, or delete the upload and try again.
    // This is because prior to 1.5b4, we could sometimes mistakenly create an invalid path object.
    NSString *path = [result pathRelativeToSite];
    
    NSString *validatedPath = path;
    if (![result validateValue:&validatedPath forKey:@"pathRelativeToSite" error:NULL])
    {
        [[result managedObjectContext] deleteObject:result];        
        result = [self defaultUpload];
    }
    else if (path != validatedPath)
    {
        [result setValue:validatedPath forKey:@"pathRelativeToSite"];
    }
	
	return result;
}

/*	If there isn't already an upload object for this path, create it.
 */
- (KTMediaFileUpload *)uploadForPath:(NSString *)path
{
	OBPRECONDITION(path);
    
    KTMediaFileUpload *result = nil;
	
	// Search for an existing upload
	NSSet *uploads = [self valueForKey:@"uploads"];
	NSEnumerator *uploadsEnumerator = [uploads objectEnumerator];
	KTMediaFileUpload *anUpload;
	
	while (anUpload = [uploadsEnumerator nextObject])
	{
		if ([[anUpload pathRelativeToSite] isEqualToString:path])
		{
			result = anUpload;
			break;
		}
	}
	
	
	// If none was found, create a new upload
	if (!result)
	{
		result = [self insertUploadToPath:path];
	}
	
	
	return result;
}

/*	General, private method for creating a new media file upload.
 */
- (KTMediaFileUpload *)insertUploadToPath:(NSString *)path
{
	KTMediaFileUpload *result = [NSEntityDescription insertNewObjectForEntityForName:@"MediaFileUpload"
															  inManagedObjectContext:[self managedObjectContext]];
	
	[result setValue:path forKey:@"pathRelativeToSite"];
	[result setValue:self forKey:@"file"];
	
	return result;
}

- (NSString *)uniqueUploadPath:(NSString *)preferredPath
{
	NSString *result = preferredPath;
	
	NSString *basePath = [preferredPath stringByDeletingPathExtension];
	NSString *extension = [preferredPath pathExtension];
	unsigned count = 1;
	
	NSManagedObjectContext *moc = [self managedObjectContext];
	NSFetchRequest *fetchRequest = [[NSFetchRequest alloc] init];
	[fetchRequest setEntity:[NSEntityDescription entityForName:@"MediaFileUpload" inManagedObjectContext:moc]];
	[fetchRequest setPredicate:[NSPredicate predicateWithFormat:@"pathRelativeToSite like[c] %@", preferredPath]];
	[fetchRequest setFetchLimit:1];
	
	// Loop through, only ending when the file doesn't exist
	while ([[moc executeFetchRequest:fetchRequest error:NULL] count] > 0)
	{
		count++;
		NSString *aPath = [NSString stringWithFormat:@"%@-%u", basePath, count];
		OBASSERT(extension);
		result = [aPath stringByAppendingPathExtension:extension];
		[fetchRequest setPredicate:[NSPredicate predicateWithFormat:@"pathRelativeToSite == %@", result]];
	}
	
	// Tidy up
	[fetchRequest release];
	return result;
}

#pragma mark -
#pragma mark Other

+ (float)scaleFactorOfSize:(NSSize)sourceSize toFitSize:(NSSize)desiredSize
{
	// Figure the approrpriate scaling factor
	float scale1 = desiredSize.width / sourceSize.width;
	float scale2 = desiredSize.height / sourceSize.height;
	
	float scaleFactor;
	if (scale2 < scale1) {
		scaleFactor = scale2; 
	} else {
		scaleFactor = scale1;
	}
	
	return scaleFactor;
}

+ (NSSize)sizeOfSize:(NSSize)sourceSize toFitSize:(NSSize)desiredSize
{
	// Scale the source image down, being sure to round the figures
	float scaleFactor = [self scaleFactorOfSize:sourceSize toFitSize:desiredSize];
	
	float width = roundf(scaleFactor * sourceSize.width);
	float height = roundf(scaleFactor * sourceSize.height);
	NSSize result = NSMakeSize(width, height);
	
	return result;
}

- (NSSize)dimensions
{
	NSSize result = NSZeroSize;
	
	NSNumber *width = [self wrappedValueForKey:@"width"];
	NSNumber *height = [self wrappedValueForKey:@"height"];
	
	if (width && height)
	{
		result = NSMakeSize([width floatValue], [height floatValue]);
	}
	
	return result;
}

/*  Attempts to read image dimensions in from disk and store them.
 */
- (void)cacheImageDimensions
{
    NSNumber *imageWidth = nil;
    NSNumber *imageHeight = nil;
    
    NSString *imagePath = [self _currentPath];
    if (imagePath)
    {
        NSURL *imageURL = [NSURL fileURLWithPath:imagePath];
        OBASSERT(imageURL);
        
        CIImage *image = [[CIImage alloc] initWithContentsOfURL:imageURL];
        if (image)
        {
            CGSize imageSize = [image extent].size;
            imageWidth = [NSNumber numberWithFloat:imageSize.width];
            imageHeight = [NSNumber numberWithFloat:imageSize.height];
            [image release];
        }
        else
        {
            // BUGSID:31429. Fallback to NSImage which can sometimes handle awkward PICT images etc.
            NSImage *image = [[NSImage alloc] initWithContentsOfURL:imageURL];
            if (image)
            {
                NSSize imageSize = [image size];
                imageWidth = [NSNumber numberWithFloat:imageSize.width];
                imageHeight = [NSNumber numberWithFloat:imageSize.height];
                [image release];
            }
        }
    }
    
    [self setValue:imageWidth forKey:@"width"];
    [self setValue:imageHeight forKey:@"height"];
}

- (float)imageScaleFactorToFitSize:(NSSize)desiredSize;
{
	return [KTInDocumentMediaFile scaleFactorOfSize:[self dimensions] toFitSize:desiredSize];
}

- (NSSize)imageSizeToFitSize:(NSSize)desiredSize
{
	NSSize result = [KTInDocumentMediaFile sizeOfSize:[self dimensions] toFitSize:desiredSize];
	return result;
}

/*	Similar to imageScaleFactorToFitSize: but ONLY takes into account the width
 */
- (float)imageScaleFactorToFitWidth:(float)width
{
	NSSize sourceSize = [self dimensions];
	float result = width / sourceSize.width;
	return result;
}

- (float)imageScaleFactorToFitHeight:(float)height;
{
	NSSize sourceSize = [self dimensions];
	float result = height / sourceSize.height;
	return result;
}

/*	Used by the Missing Media sheet. Assumes that the underlying filesystem object no longer exists so attempts
 *	to retrieve a 128x128 pixel version from the scaled images.
 */
- (NSString *)bestExistingThumbnail
{
	return nil;     // Cheating for the moment and assuming no thumbnails
    
    // Get the list of our scaled images by scale factor
	NSArray *sortDescriptors = [NSSortDescriptor sortDescriptorArrayWithKey:@"scaleFactor" ascending:YES];
	NSArray *scaledImages = [[[self valueForKey:@"scaledImages"] allObjects] sortedArrayUsingDescriptors:sortDescriptors];
	
	if ([scaledImages count] == 0) {
		return nil;
	}
	
	// What scale factor would we like?
	float scaleFactor = [self imageScaleFactorToFitSize:NSMakeSize(128.0, 128.0)];
	
	// Run through the list of scaled images. Bail if a good one is found
	NSEnumerator *scaledImagesEnumerator = [scaledImages objectEnumerator];
	KTMediaFile *bestMatch;
	while (bestMatch = [scaledImagesEnumerator nextObject])
	{
		if ([bestMatch floatForKey:@"scaleFactor"] >= scaleFactor) {
			break;
		}
	}
	if (!bestMatch)
	{
		bestMatch = [scaledImages lastObject];
	}
	
	// Create an NSImage from the scaled image
	NSString *result = [bestMatch currentPath];
	return result;
}

@end
