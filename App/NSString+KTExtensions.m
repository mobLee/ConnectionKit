//
//  NSString+KTExtensions.m
//  KTComponents
//
//  Copyright 2004-2011 Karelia Software. All rights reserved.
//

#import "NSString+Karelia.h"

#import "KT.h"
#import "Registration.h"

#import "NSCharacterSet+Karelia.h"
#import "NSData+Karelia.h"

@implementation NSString ( KTExtensions )


// TEMPORARY FOR BETA -- HOW IS NSSTRING BEING PASSED THIS METHOD?
//
// Stack trace:
// #3	0x70062534 in -[NSString(KTExtensions) identifier] at NSString+KTExtensions.m:23
// #4	0x001c9a3a in -[IMBNode isEqual:] at IMBNode.m:420. the object asked to compare to is an NSString
// #5	0x96618d9a in CFEqual
// #6	0x96630441 in __CFBasicHashStandardCallback
// #7	0x9661d339 in ___CFBasicHashFindBucket1
// #8	0x966254cc in CFBasicHashFindBucket
// #9	0x96625393 in CFDictionaryGetValue
// #10	0x985d88bd in -[IKCacheDatabase indexForUID:]
// #11	0x985dcbc9 in -[IKImageCell validateDatasource]
// #12	0x9850402e in -[IKImageBrowserCell _computeAspectRatio]
// #13	0x98503fc0 in -[IKImageBrowserCell aspectRatio]
// #14	0x98504537 in -[IKImageBrowserCell imageFrameForImageContainerFrame:]
// #15	0x985062db in -[IKImageBrowserCell _computeImageFrame]
// #16	0x98503b8d in -[IKImageBrowserCell imageFrame]
// #17	0x985a53fe in -[IKImageBrowserView(IKImageBrowserTasks) _sizeToImportForCell:]
// #18	0x985a5519 in -[IKImageBrowserView(IKImageBrowserTasks) _prepareThumbnailBuildersForCells:size:start:quality:rule:arrayOut:]
// #19	0x985a3255 in -[IKImageBrowserView(IKImageBrowserTasks) prepareThumbnailBuildersForCells:size:indexes:quality:rule:]
// #20	0x985a4f66 in -[IKImageBrowserView(IKImageBrowserTasks) performSynchronousTasksIfAny]
// #21	0x984fae95 in -[IKImageBrowserView(ImageBrowserDrawing) drawWithCurrentRendererInRect:]
// #22	0x984fbb12 in -[IKImageBrowserView(ImageBrowserDrawing) drawRect:]
#ifndef VARIANT_RELEASE
- (NSString *)identifier
{
	[NSException raise:NSInternalInconsistencyException format:@"calling identifier on %@", self];
	return self;
}
#endif


+ (NSString *)formattedFileSizeWithBytes:(NSNumber *)filesize
{
	static NSString *suffix[] = { @"B", @"KB", @"MB", @"GB", @"TB", @"PB", @"EB" };
	int i, c = 7;
	long size = [filesize longValue];
	
	for ( i = 0; i < c && size >= 1024; i++ )
	{
		size = size / 1024;
	}
	
	return [NSString stringWithFormat:@"%ld %@", size, suffix[i]];
}


// Show where the cursor is on the text by inserting some >>>> pointing to that spot
- (NSString *)annotatedAtOffset:(unsigned int)anOffset
{
	NSString *string1 = [self substringToIndex:anOffset];
	NSString *string2 = [self substringFromIndex:anOffset];
	return [NSString stringWithFormat:@"%@>>>>%@", string1, string2];
}



/*!	Return the last two components of an email address or host name. Returns nil if no domain name found
 */
- (NSString *)domainName
{
	NSString *result = nil;
	
	NSRange lastDot = [self rangeOfString:@"." options:NSBackwardsSearch];
	if (NSNotFound != lastDot.location)
	{
		static NSCharacterSet *sEarlierDelimSet = nil;
		if (nil == sEarlierDelimSet)
		{
			sEarlierDelimSet = [[NSCharacterSet characterSetWithCharactersInString:@".@"] retain];
		}
		
		NSRange earlierDelim = [self rangeOfCharacterFromSet:sEarlierDelimSet options:NSBackwardsSearch range:NSMakeRange(0,lastDot.location)];
		if (NSNotFound != earlierDelim.location)
		{
			result = [self substringFromIndex:earlierDelim.location+1];
			// return string after the @ or the . to the end of the string
		}
		else
		{
			result = self;	// didn't find earlier delimeter, so string must be domain.tld
		}
	}
	return result;
}

- (BOOL) looksLikeValidHost
{
	if ([self isEqualToString:@"localhost"]) return YES;
	
	static NSCharacterSet *sIllegalHostNameSet = nil;
	static NSCharacterSet *sIllegalIPAddressSet = nil;
	if (nil == sIllegalHostNameSet)
	{
		sIllegalHostNameSet = [[[[NSCharacterSet alphanumericASCIICharacterSet] setByAddingCharactersInString:@".-"] invertedSet] retain];
		sIllegalIPAddressSet = [[[NSCharacterSet characterSetWithCharactersInString:@".0123456789"] invertedSet] retain];
	}
	
	NSRange whereBad = [self rangeOfCharacterFromSet:sIllegalHostNameSet];
	if (NSNotFound != whereBad.location)
	{
		return NO;
	}
	// now more rigorous test.
	NSArray *components = [self componentsSeparatedByString:@"."];
	
	NSRange whereBadIPAddress = [self rangeOfCharacterFromSet:sIllegalIPAddressSet];
	if (NSNotFound == whereBadIPAddress.location)
	{
		if ([components count] != 4)
		{
			return NO;	// we must have at 4 items
		}
		// We have a potential IP address, numbers only between the decimals
		NSEnumerator *theEnum = [components objectEnumerator];
		id num;
		
		while (nil != (num = [theEnum nextObject]) )
		{
			if ([num isEqualToString:@""] || [num intValue] > 255)
			{
				return NO;
			}
		}
	}
	else	// Non IP address, look for foo.bar.baz pattern
	{
		if ([components count] < 2)
		{
			return ([[self lowercaseString] isEqualToString:@"localhost"]);
			// Only localhost works if less than two components
		}
		NSString *lastComponent = [components lastObject];
		if ([lastComponent length] < 2 || ( NSNotFound != [lastComponent rangeOfString:@"-"].location) )
		{
			return NO;	// last item can't be shorter than 2 characters, can't have dash
		}
		if ([((NSString *)[components lastObject]) length] < 2)
		{
			return NO;	// last item can't be shorter than 2 characters
		}
		NSEnumerator *theEnum = [components	objectEnumerator];
		id component;
		
		while (nil != (component = [theEnum nextObject]) )
		{
			if ([component isEqualToString:@""] || [component hasPrefix:@"-"] || [component hasSuffix:@"-"])
			{
				return NO;	// two dots in a row, meaning empty inbetween, is bad.  Prefix or suffix of - is bad.
			}
		}
	}
	return YES;
}


//- (NSString *)pathRelativeToRoot
//{
//    // remove everything up to, but not including, Source
//    // so /Users/ttalbot/Sites/BigSite.site/Contents/Source/whatever becomes Source/whatever
//    NSMutableArray *components = [NSMutableArray arrayWithArray:[self pathComponents]];
//    NSEnumerator *componentsEnumerator = [components objectEnumerator];
//    NSString *component;
//    
//    while ( component = [componentsEnumerator nextObject] ) {
//        if ( ![component isEqualToString:@"Source"] ) {
//            [components removeObject:component];
//        }
//        else {
//            break;
//        }
//    }
//    return [NSString pathWithComponents:components];
//}


@end


@implementation NSAttributedString (KTExtensions)

+ (NSAttributedString *)attributedMenuTitle:(NSString *)aTitle subtitle:(NSString *)aSubtitle;
{
	static NSDictionary *sTitleAttributes = nil;
	static NSDictionary *sSubtitleAttributes = nil;
	if (!sTitleAttributes || !sSubtitleAttributes)
	{
		sTitleAttributes = [[NSDictionary alloc] initWithObjectsAndKeys:
							[NSFont systemFontOfSize:[NSFont smallSystemFontSize]], NSFontAttributeName,
							nil];
		sSubtitleAttributes = [[NSDictionary alloc] initWithObjectsAndKeys:
							   [NSFont systemFontOfSize:[NSFont labelFontSize]], NSFontAttributeName,
							   [NSColor colorWithCalibratedWhite:0.0 alpha:0.4], NSForegroundColorAttributeName, 
							   nil];
	}
	NSMutableAttributedString *nameAndDescription
	= [[[NSMutableAttributedString alloc]
		initWithString:aTitle
		attributes:sTitleAttributes] autorelease];
	if (aSubtitle && ![aSubtitle isEqualToString:@""])
	{
		[nameAndDescription appendAttributedString:
		 [[[NSAttributedString alloc]
		   initWithString:[NSString stringWithFormat:@"\n%@", aSubtitle]
		   attributes:sSubtitleAttributes] autorelease]];
	}
	return nameAndDescription;
}

@end

