//
//  ImageElementDelegate.m
//  Sandvox SDK
//
//  Copyright 2004-2009 Karelia Software. All rights reserved.
//
//  Redistribution and use in source and binary forms, with or without
//  modification, are permitted provided that the following conditions are met:
//
//  *  Redistribution of source code must retain the above copyright notice,
//     this list of conditions and the follow disclaimer.
//
//  *  Redistributions in binary form must reproduce the above copyright notice,
//     this list of conditions and the following disclaimer in the documentation
//     and/or other material provided with the distribution.
//
//  *  Neither the name of Karelia Software nor the names of its contributors
//     may be used to endorse or promote products derived from this software
//     without specific prior written permission.
//
//  THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS-IS"
//  AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
//  IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
//  ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE
//  LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR 
//  CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
//  SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
//  INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
//  CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
//  ARISING IN ANY WAY OUR OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
//  POSSIBILITY OF SUCH DAMAGE.
//
//  Community Note: This code is distrubuted under a modified BSD License.
//  We encourage you to share your Sandvox Plugins similarly.
//

#import "ImageElementDelegate.h"

#import "SandvoxPlugin.h"


#import <QuartzCore/QuartzCore.h>
#import <WebKit/WebKit.h>


// LocalizedStringInThisBundle(@"Please use the Inspector to enter the URL of an image", "Prompt when no URL has been entered")
// LocalizedStringInThisBundle(@"Order prints of this image from dotphoto.com", "Title of dot photo link");
// LocalizedStringInThisBundle(@"dotphoto", "alt text of dot photo link");
// LocalizedStringInThisBundle(@"View this image full-size", "Title of mag link");
// LocalizedStringInThisBundle(@"magnify", "alt text of mag link");

// LocalizedStringInThisBundle(@"This is a placeholder for the image at:", "followed by URL of externally loaded image, for when we are not loading in external resources.");



@interface ImageElementDelegate ()
- (NSSize)boundingImageBox;
@end


#pragma mark -


@implementation ImageElementDelegate

#pragma mark -
#pragma mark Initialization

- (void)awakeFromBundleAsNewlyCreatedObject:(BOOL)isNewObject
{
	[super awakeFromBundleAsNewlyCreatedObject:isNewObject];
    
	if (isNewObject)
	{
		// set default properties
		[[self propertiesStorage] setValue:[NSNumber numberWithInt:AutomaticSize] forKey:@"imageSize"];
		
		BOOL shouldIncludeLinkInitially = [[NSUserDefaults standardUserDefaults] boolForKey:@"shouldIncludeLink"];
		[[self propertiesStorage] setValue:[NSNumber numberWithBool:shouldIncludeLinkInitially] forKey:@"shouldIncludeLink"];
        
		BOOL shouldLinktoOriginalInitially = [[NSUserDefaults standardUserDefaults] boolForKey:@"linkImageToOriginal"];
		[[self propertiesStorage] setValue:[NSNumber numberWithBool:shouldLinktoOriginalInitially] forKey:@"linkImageToOriginal"];
        
		BOOL shouldUseExternalImage = [[NSUserDefaults standardUserDefaults] boolForKey:@"preferExternalImage"];
		[[self propertiesStorage] setValue:[NSNumber numberWithBool:shouldUseExternalImage] forKey:@"preferExternalImage"];
    }
}

- (void)awakeFromDragWithDictionary:(NSDictionary *)aDataSourceDictionary
{
	[super awakeFromDragWithDictionary:aDataSourceDictionary];
    
    // Add the dragged image into the DB
	KTMediaContainer *image =
		[[self mediaManager] mediaContainerWithDataSourceDictionary:aDataSourceDictionary];
	
	[[self propertiesStorage] setValue:image forKey:@"image"];
	
	
	// grab any other properties from aDragSourceDictionary
	NSString *title = [aDataSourceDictionary valueForKey:kKTDataSourceTitle];
	if ( nil == title )
	{
		// No title specified; use file name (minus extension)
		title = [[aDataSourceDictionary valueForKey:kKTDataSourceFileName] stringByDeletingPathExtension];
	}
	if (nil != title)
	{
		[[self propertiesStorage] setObject:title forKey:@"altText"];
	}
    
	if (nil != [aDataSourceDictionary objectForKey:kKTDataSourceImageURLString])
	{
		[[self propertiesStorage] setObject:[aDataSourceDictionary objectForKey:kKTDataSourceImageURLString] forKey:@"externalImageURL"];
	}
    
	if (nil != [aDataSourceDictionary objectForKey:kKTDataSourceURLString])
	{
		[[self propertiesStorage] setObject:[aDataSourceDictionary objectForKey:kKTDataSourceURLString] forKey:@"externalURL"];
	}
    
	if (nil != [aDataSourceDictionary objectForKey:kKTDataSourceCaption])
	{
		[[self propertiesStorage] setObject:[[aDataSourceDictionary objectForKey:kKTDataSourceCaption] stringByEscapingHTMLEntities] forKey:@"captionHTML"];
	}
	
	// override defaults if set in aDragSourceDictionary
	if (nil != [aDataSourceDictionary objectForKey:@"kKTDataSourcePreferExternalImageFlag"])
	{
		[[self propertiesStorage] setValue:[aDataSourceDictionary objectForKey:@"kKTDataSourcePreferExternalImageFlag"] forKey:@"preferExternalImage"];
	}
    
	if (nil != [aDataSourceDictionary objectForKey:@"kKTDataSourceShouldIncludeLinkFlag"])
	{
		[[self propertiesStorage] setValue:[aDataSourceDictionary objectForKey:@"kKTDataSourceShouldIncludeLinkFlag"] forKey:@"shouldIncludeLink"];
	}
    
	if (nil != [aDataSourceDictionary objectForKey:@"kKTDataSourceLinkToOriginalFlag"])
	{
		[[self propertiesStorage] setValue:[aDataSourceDictionary objectForKey:@"kKTDataSourceLinkToOriginalFlag"] forKey:@"linkImageToOriginal"];
	}
}

- (void)dealloc
{
	[myImage release];
	[myImagePath release];
	
	[super dealloc];
}

#pragma mark -
#pragma mark Media Storage

- (NSSet *)requiredMediaIdentifiers
{
	NSMutableSet *result = [NSMutableSet setWithCapacity:2];
	
	KTMediaContainer *image = [[self propertiesStorage] valueForKey:@"image"];
	[result addObjectIgnoringNil:[image identifier]];
	
	return result;
}

- (IBAction)chooseImage:(id)sender
{
	NSOpenPanel *imageChooser = [NSOpenPanel openPanel];
	[imageChooser setCanChooseDirectories:NO];
	[imageChooser setAllowsMultipleSelection:NO];
	[imageChooser setPrompt:LocalizedStringInThisBundle(@"Choose", "choose button - open panel")];
	
// TODO: Open the panel at a reasonable location
	[imageChooser runModalForDirectory:nil
								  file:nil
								 types:[NSImage imageFileTypes]];
	
	NSArray *selectedPaths = [imageChooser filenames];
	if (!selectedPaths || [selectedPaths count] == 0) {
		return;
	}
	
	KTMediaContainer *image =
		[[self mediaManager] mediaContainerWithPath:[selectedPaths firstObjectKS]];
	
	[[self propertiesStorage] setValue:image forKey:@"image"];
}

- (BOOL)pathInfoField:(KSPathInfoField *)field
 performDragOperation:(id <NSDraggingInfo>)sender
	 expectedDropType:(NSDragOperation)dragOp
{
	BOOL fileShouldBeExternal = NO;
	if (dragOp & NSDragOperationLink)
	{
		fileShouldBeExternal = YES;
	}
	
	KTMediaContainer *image = [[self mediaManager] mediaContainerWithDraggingInfo:sender
																				  preferExternalFile:fileShouldBeExternal];
																				  
	[[self propertiesStorage] setValue:image forKey:@"image"];
	
	return YES;
}

/*	We want to support all image types
 */
- (NSArray *)supportedDragTypesForPathInfoField:(KSPathInfoField *)pathInfoField
{
	return [NSImage imagePasteboardTypes];
}

- (BOOL)pathInfoField:(KSPathInfoField *)filed shouldAllowFileDrop:(NSString *)path
{
	BOOL result = NO;
	
	if ([NSString UTI:[NSString UTIForFileAtPath:path] conformsToUTI:(NSString *)kUTTypeImage])
	{
		result = YES;
	} 
	
	return result;
}

#pragma mark -
#pragma mark HTML Generation

- (NSString *)HTMLString
{
    //  We are generating an enclosing element directly (image/div etc.), and don't want the system to do so for us.
    return [self innerHTMLString];
}

/*	This depends on the chosen image and other factors.
 *	Returns nil if linking is disabled.
 */
- (NSString *)linkURL
{
	NSString *result = nil;
	
	if ([[[self propertiesStorage] valueForKey:@"shouldIncludeLink"] boolValue])
	{
		if ([[[self propertiesStorage] valueForKey:@"linkImageToOriginal"] boolValue])
		{
			if ([[self propertiesStorage] boolForKey:@"preferExternalImage"])
			{
				// Just link straight back to the image's source
				result = [[self propertiesStorage] valueForKey:@"externalImageURL"];
			}
			else
			{
				NSString *path = [[self propertiesStorage] valueForKeyPath:@"image.file.currentPath"];
				if (path)
				{
					result = [[NSURL fileURLWithPath:path] absoluteString];
				}
			}
		}
		else
		{
			// Link to the user-specified URL
			result = [[self propertiesStorage] valueForKey:@"externalURL"];
		}
	}
	
	return result;
}

/*	Depending on how we're being used, the image must fit within a certain bounding box.
 *	e.g. A Photo pagelet has a much smaller box to fit in.
 */
- (NSSize)boundingImageBox
{
	NSDictionary *scalingProperties = nil;
	
	id container = [self delegateOwner];
	if ([container isKindOfClass:[KTPage class]])
	{
		if ([container includeSidebar])
		{
			scalingProperties = [[container master] imageScalingPropertiesForUse:@"KTSidebarPageMedia"];
		}
		else
		{
			scalingProperties = [[container master] imageScalingPropertiesForUse:@"KTPageMedia"];
		}
	}
	
    KTImageScalingSettings *scalingSettings = [scalingProperties objectForKey:@"scalingBehavior"];
    NSSize result = scalingSettings ? [scalingSettings size] : NSZeroSize;
	return result;
}

#pragma mark -
#pragma mark Resources

- (NSString *)dotphotoResource
{
	return [[self bundle] pathForImageResource:@"dotphoto"];
}


- (NSString *)magResource
{
	return [[self bundle] pathForImageResource:@"mag"];
}

#pragma mark -
#pragma mark Summaries

- (NSString *)summaryHTMLKeyPath { return @"captionHTML"; }

- (BOOL)summaryHTMLIsEditable { return YES; }

#pragma mark -
#pragma mark RSS Feed

- (NSArray *)pageWillReturnFeedEnclosures:(KTPage *)page
{
	NSArray *result = nil;
	
	if ([[self propertiesStorage] boolForKey:@"linkImageToOriginal"])
    {
        KTMediaContainer *image = [[self propertiesStorage] valueForKey:@"image"];
        if ([[[image file] currentPath] length] > 0)
        {
            result = [NSArray arrayWithObject:image];
        }
    }
	
	return result;
}

#pragma mark -
#pragma mark Data Migrator

- (BOOL)importPluginProperties:(NSDictionary *)oldPluginProperties
                    fromPlugin:(NSManagedObject *)oldPlugin
                         error:(NSError **)error
{
    KTMediaContainer *image = [[self mediaManager] mediaContainerWithMediaRefNamed:@"ImageElement" element:oldPlugin];
    [[self propertiesStorage] setValue:image forKey:@"image"];
    
    [[self propertiesStorage] setValuesForKeysWithDictionary:oldPluginProperties];
    
    if (error) *error = nil;
    return YES;
}

#pragma mark -
#pragma mark Data Source

+ (NSArray *)supportedPasteboardTypesForCreatingPagelet:(BOOL)isCreatingPagelet;
{
    return [NSArray arrayWithObjects:
            WebArchivePboardType,	// drags from safari, includes links and such
            NSFilenamesPboardType,
            NSTIFFPboardType,
            NSPICTPboardType,
            NSPDFPboardType,
            //		@"Apple PNG pasteboard type",		// not defined in headers, but it's on screenshots!
            nil];
}

+ (unsigned)numberOfItemsFoundOnPasteboard:(NSPasteboard *)sender
{
    return 1;
}

+ (KTSourcePriority)priorityForItemOnPasteboard:(NSPasteboard *)pboard atIndex:(unsigned)dragIndex creatingPagelet:(BOOL)isCreatingPagelet;
{
    [pboard types];
    
	if (nil != [pboard availableTypeFromArray:[NSArray arrayWithObject:NSFilenamesPboardType]])
	{
		NSArray *fileNames = [pboard propertyListForType:NSFilenamesPboardType];
		if (dragIndex < [fileNames count])
		{
			NSString *fileName = [fileNames objectAtIndex:dragIndex];
			if ( nil != fileName )
			{
				// check to see if it's an image file
				NSString *aUTI = [NSString UTIForFileAtPath:fileName];	// takes account as much as possible
                
				if ( [NSString UTI:aUTI conformsToUTI:(NSString *)kUTTypeImage] )
				{
					return KTSourcePriorityIdeal;
				}
				else if (nil != [pboard availableTypeFromArray:[NSArray arrayWithObject:@"ImageDataListPboardType"]])
				{
					return KTSourcePriorityFallback;	// doesn't look like there's an image, but there is image metadata, this must be an image.
				}
				else
				{
					return KTSourcePriorityNone;	// not an image
				}
			}
		}
	}
	else if (nil != [pboard availableTypeFromArray:[NSArray arrayWithObject:NSTIFFPboardType]])
	{
		return KTSourcePriorityTypical;	// there is an image, so it's probably OK
	}
    
    return KTSourcePriorityNone;	// doesn't actually have any image data
}

+ (BOOL)populateDataSourceDictionary:(NSMutableDictionary *)aDictionary
                      fromPasteboard:(NSPasteboard *)pasteboard
                             atIndex:(unsigned)dragIndex
				  forCreatingPagelet:(BOOL)isCreatingPagelet;

{
	BOOL result = [NSImage populateDictionary:aDictionary
                    orderedImageTypesAccepted:[self supportedPasteboardTypesForCreatingPagelet:isCreatingPagelet]
                               fromPasteboard:pasteboard
                                        index:dragIndex];
    return result;
}

@end

