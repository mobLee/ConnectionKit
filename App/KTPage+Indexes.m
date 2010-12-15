//
//  KTPage+Indexes.m
//  Marvel
//
//  Created by Mike on 30/01/2008.
//  Copyright 2008-2009 Karelia Software. All rights reserved.
//

#import <CoreFoundation/CoreFoundation.h>

#import "KTPage+Paths.h"

#import "SVArticle.h"
#import "SVArchivePage.h"
#import "SVHTMLContext.h"
#import "SVHTMLTemplateParser.h"
#import "SVMediaGraphic.h"
#import "SVPagesController.h"
#import "SVTextAttachment.h"

#import "NSString+Karelia.h"
#import "NSArray+Karelia.h"
#import "NSBundle+Karelia.h"
#import "NSBundle+KTExtensions.h"
#import "NSCharacterSet+Karelia.h"
#import "NSError+Karelia.h"
#import "NSManagedObjectContext+KTExtensions.h"
#import "NSObject+Karelia.h"
#import "NSSortDescriptor+Karelia.h"
#import "NSString+KTExtensions.h"
#import "KSURLUtilities.h"
#import "SVWebEditorHTMLContext.h"
#import "KSStringHTMLEntityUnescaping.h"

@interface KTPage (IndexesPrivate)
- (NSString *)pathRelativeToSiteWithCollectionPathStyle:(KTCollectionPathStyle)collectionPathStyle;
@end


#pragma mark -


@implementation KTPage (Indexes)

#pragma mark Basic Properties

@dynamic collectionSummaryType;

#pragma mark Index

- (BOOL)pagesInIndexAllowComments
{
	BOOL result = NO;
	
	if ([self isCollection])
	{
		NSArray *pages = [[SVPagesController controllerWithPagesToIndexInCollection:self] arrangedObjects];
		for ( SVSiteItem *page in pages )
		{
			if ( [page allowComments] )
			{
				result = YES;
				break;
			}
		}
	}
	
	return result;
}

#pragma mark -
#pragma mark Navigation Arrows

/*	All those pages which are suitable for linking to with navigation arrows.
 */
- (NSArray *)navigablePages;
{
	// How to sort the pages? Generally this is the same as usual, but for chronological collections, the arrows need to always be the same. #32341
    SVCollectionSortOrder sorting = [[self collectionSortOrder] integerValue];
    BOOL ascending = [self isSortedChronologically] ? NO : [[self collectionSortAscending] boolValue];
    
    NSArray *result = [self childrenWithSorting:sorting ascending:ascending inIndex:YES];
	return result;
}

- (KTPage *)previousPage
{
    SVHTMLContext *context = [[SVHTMLTemplateParser currentTemplateParser] HTMLContext];
    
	NSArray *siblings = [[self parentPage] childPages];
    [context addDependencyOnObject:self keyPath:@"parentPage.childPages"];
    
	unsigned index = [siblings indexOfObjectIdenticalTo:self];
	while (index > 0)
	{
        index--;
		
        KTPage *result = [siblings objectAtIndex:index];
        [context addDependencyOnObject:result keyPath:@"shouldIncludeInIndexes"];
        
        if ([result shouldIncludeInIndexes]) return result;
	}
	
	return nil;
}
+ (NSSet *) keyPathsForValuesAffectingPreviousPage; { return [NSSet setWithObject:@"parentPage.childPages"]; }

- (KTPage *)nextPage
{
	SVHTMLContext *context = [[SVHTMLTemplateParser currentTemplateParser] HTMLContext];
    
	NSArray *siblings = [[self parentPage] childPages];
	[context addDependencyOnObject:self keyPath:@"parentPage.childPages"];
    
	unsigned index = [siblings indexOfObjectIdenticalTo:self] + 1;
	while (index < [siblings count])
	{
		KTPage *result = [siblings objectAtIndex:index];
        [context addDependencyOnObject:result keyPath:@"shouldIncludeInIndexes"];

        if ([result shouldIncludeInIndexes]) return result;
        
        index++;
	}
	
	return nil;
}
+ (NSSet *) keyPathsForValuesAffectingNextPage; { return [NSSet setWithObject:@"parentPage.childPages"]; }

#pragma mark Syndication

@dynamic collectionSyndicationType;
- (void)setCollectionSyndicationType:(NSNumber *)type;
{
    [self willChangeValueForKey:@"collectionSyndicationType"];
    [self setPrimitiveValue:type forKey:@"collectionSyndicationType"];
    [self didChangeValueForKey:@"collectionSyndicationType"];
    
    
    // #93646
    if ([type boolValue])
    {
        if ([[self collectionMaxSyndicatedPagesCount] integerValue] < 1)
        {
            [self setCollectionMaxSyndicatedPagesCount:[NSNumber numberWithUnsignedInteger:20]];
        }
    }
    
    
    [[self childItems] makeObjectsPerformSelector:@selector(guessEnclosures)];
}

@dynamic collectionMaxSyndicatedPagesCount;
- (BOOL)validateCollectionMaxSyndicatedPagesCount:(NSNumber **)max error:(NSError **)outError;
{
    // Mandatory for syndicated collections, optional otherwise
    if ([self isCollection] && [[self collectionSyndicationType] boolValue])
    {
        if (!*max)
        {
            if (outError) *outError = [NSError errorWithDomain:NSCocoaErrorDomain
                                                          code:NSValidationMissingMandatoryPropertyError
                                          localizedDescription:@"collectionMaxSyndicatedPagesCount is non-optional for collections"];
            
            return NO;
        }
    }
    
    return YES;
}

@dynamic collectionTruncateFeedItems;
@dynamic collectionMaxFeedItemLength;

@dynamic RSSFileName;

- (NSURL *)feedURL
{
	NSURL *result = nil;
	
	if ([[self collectionSyndicationType] boolValue])
	{
		result = [NSURL ks_URLWithPath:[self RSSFileName] relativeToURL:[self URL] isDirectory:NO];
	}
	
	return result;
}
+ (NSString *)keyPathsForValuesAffectingFeedURL;
{
    return [NSSet setWithObjects:@"collectionSyndicationType", @"URL", @"RSSFileName", nil];
}

/*  The pages that will go into the RSS feed. Sort chronologically and apply the limit
 */
- (NSArray *)pagesInRSSFeed
{
	NSArray *result = [self childrenWithSorting:SVCollectionSortByDateCreated ascending:NO inIndex:YES];
    
    NSUInteger max = [[self collectionMaxSyndicatedPagesCount] unsignedIntegerValue];
    if ([result count] > max)
    {
        result = [result subarrayToIndex:max];
    }
    
	return result;
}

/*!	Return the HTML.
 */
- (NSString *)RSSFeed;
{
	NSMutableString *result = [NSMutableString string];
    SVHTMLContext *context = [[SVHTMLContext alloc] initWithOutputWriter:result];
    
    [self writeRSSFeed:context];
	[context release];
		
	// We won't do any "stringByEscapingCharactersOutOfEncoding" since we are using UTF8, which means everything is OK, and we
	// don't want to introduce any entities into the XML anyhow.
	
	OBPOSTCONDITION(result);
    return result;
}


// This will be a private API for use by General index
- (void)writeComments:(SVHTMLContext *)context;
{
	SVHTMLTemplateParser *parser = [[SVHTMLTemplateParser alloc] initWithTemplate:self.commentsTemplate component:self];
    [parser parseIntoHTMLContext:context];
	[parser release];
}

- (void)writeRSSFeed:(SVHTMLContext *)context;
{
    // Find the template
	NSString *template = [[NSBundle mainBundle] templateRSSAsString];
	OBASSERT(template);
	
	
    // Generate XML
	SVHTMLTemplateParser *parser = [[SVHTMLTemplateParser alloc] initWithTemplate:template component:self];
	
    [parser parseIntoHTMLContext:context];
    [parser release];
}

- (NSSize)RSSFeedThumbnailsSize { return NSMakeSize(128.0, 128.0); }

#pragma mark RSS Enclosures

- (NSArray *)feedEnclosures
{
    NSSet *attachments = [[self article] attachments];
    
    NSSet *graphics = [[attachments valueForKey:@"graphic"] filteredSetUsingPredicate:[NSPredicate predicateWithFormat:@"includeAsRSSEnclosure == 1"]];
    
	NSMutableArray *result = [NSMutableArray arrayWithCapacity:[attachments count]];
    
    for (SVGraphic *anAttachment in graphics)
    {
        id <SVEnclosure> enclosure = [anAttachment enclosure];
        if (enclosure) [result addObject:enclosure];
    }
    
	return result;
}

- (void)guessEnclosures;    // searches for enclosures if feed expects them
{
    if ([[[self parentPage] collectionSyndicationType] intValue] > 1)
    {
        NSArray *enclosures = [self feedEnclosures];
        if ([enclosures count] == 0)
        {
            for (SVTextAttachment *anAttachment in [[self article] attachments])
            {
                SVGraphic *graphic = [anAttachment graphic];
                if ([graphic isKindOfClass:[SVMediaGraphic class]])
                {
                    [graphic setIncludeAsRSSEnclosure:[NSNumber numberWithBool:YES]];
                    break;
                }
            }
        }
    }
}

- (void)writeEnclosures;
{
    NSArray *enclosures = [self feedEnclosures];
    
    for (id <SVEnclosure> anEnclosure in enclosures)
    {
        SVHTMLContext *context = [[SVHTMLTemplateParser currentTemplateParser] HTMLContext];
        [context writeEnclosure:anEnclosure];
    }
}

#pragma mark -
#pragma mark Raw Char Count (exp of slider) <--> Truncate Count & Units

#define kCharsPerWord 5
#define kWordsPerSentence 10
#define kSentencesPerParagraph 5
#define kMaxTruncationParagraphs 10
// 5 * 10 * 5 * 10 = 5000 characters in 20 paragraphs, so this is our range

#define LOGFUNCTION log2
#define EXPFUNCTION(x) exp2(x)

const NSUInteger kTruncationMin = kWordsPerSentence * kCharsPerWord;
const NSUInteger kTruncationMax = kMaxTruncationParagraphs * kSentencesPerParagraph * kWordsPerSentence * kCharsPerWord;
double kTruncationMinLog;
double kTruncationMaxLog;

double kOneThirdTruncationLog;
double kTwoThirdsTruncationLog;

NSUInteger kOneThirdTruncation;
NSUInteger kTwoThirdsTruncation;

+ (void) initialize
{
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];

	kTruncationMinLog = LOGFUNCTION(kTruncationMin);
	kTruncationMaxLog = LOGFUNCTION(kTruncationMax);
	
	kOneThirdTruncationLog = kTruncationMinLog + (kTruncationMaxLog - kTruncationMinLog)/3.0;
	kTwoThirdsTruncationLog = kTruncationMinLog + (kTruncationMaxLog - kTruncationMinLog)/3.0*2.0;
	
	kOneThirdTruncation = EXPFUNCTION(kOneThirdTruncationLog);
	kTwoThirdsTruncation = EXPFUNCTION(kTwoThirdsTruncationLog);
	
	[pool release];
}

// Based on raw number of characters (derived from slider value) and decsired truncation type, figure out an appropriate value in those units.
+ (NSUInteger) truncateCountFromMaxItemLength:(NSUInteger)maxItemLength forType:(SVTruncationType)truncType round:(BOOL)wantRound;
{
	NSUInteger result = 0;
	float divided = 0.0;
	switch(truncType)
	{
		case kTruncateCharacters:
			divided = (float)maxItemLength;
			break;
		case kTruncateWords:
			divided = (float)maxItemLength / (kCharsPerWord);
			break;
		case kTruncateSentences:
			divided = (float)maxItemLength / (kCharsPerWord * kWordsPerSentence);
			break;
		case kTruncateParagraphs:
			divided = (float)maxItemLength / (kCharsPerWord * kWordsPerSentence * kSentencesPerParagraph);
			break;
		default:
			break;
	}
	
	if (wantRound)
	{
		// Not sure if there is any sophisticated mathematical way to do this.  Basically,
		// show nice rounded numbers approximately corresponding to the order of magnitude
		if (divided >= 800)
		{
			result = 100 * roundf(divided / 100);
		}
		else if (divided >= 200)
		{
			result = 50 * roundf(divided / 50);
		}
		else if (divided >= 80)
		{
			result = 10 * roundf(divided / 10);
		}
		else if (divided >= 20)
		{
			result = 5 * roundf(divided / 5);
		}
		else result = round(divided);
	}
	else
	{
		result = round(divided);
	}
	
	if (0 == result) result = 1;		// do not let result go to zero
	
	return result;
}

// Even smarter than above, it figures out units based on which third of the slider is in range.
// Convert slider floating value to approprate truncation types.
// Depending on which third the value is in, we round to a count of words, sentence, or paragraphs.

+ (NSUInteger) truncCountFromMaxItemLength:(NSUInteger)maxItemLength choosingTruncType:(SVTruncationType *)outTruncType
{
	
	SVTruncationType type = 0;
	if (maxItemLength < kOneThirdTruncation)
	{
		type = kTruncateWords;			// First third: truncate words
	}
	else if (maxItemLength < kTwoThirdsTruncation)
	{
		type = kTruncateSentences;		// Second third: truncate sentences
	}
	else if (maxItemLength > 0.99 * kTruncationMax)		// If at the end, 99th percentile, 
	{
		type = kTruncateNone;
	}
	else
	{
		type = kTruncateParagraphs;		// Third third, truncate paragraphs.
	}
	
	NSUInteger truncCount = [[self class] truncateCountFromMaxItemLength:maxItemLength
														 forType:type
														   round:YES];		// nice rounded number
	if (outTruncType)
	{
		*outTruncType = type;
	}
	return truncCount;
}

#pragma mark Standard Summary

// Returns YES if truncated.

- (BOOL)writeSummary:(SVHTMLContext *)context includeLargeMedia:(BOOL)includeLargeMedia truncation:(NSUInteger)maxItemLength;
{
	SVTruncationType truncationType = kTruncateNone;
	NSUInteger truncCount = [[self class] truncCountFromMaxItemLength:maxItemLength choosingTruncType:&truncationType];
	BOOL truncated = NO;
	
	[context willWriteSummaryOfPage:self];
    [context startElement:@"div" className:@"article-summary"];

	// do we have a custom summary? if so just write it
    if ( nil != [self customSummaryHTML] )
    {
        [context writeHTMLString:[self customSummaryHTML]];
		truncated = YES;		// A custom summary means we want to make an obvious link to more
    }
    else
	{
		NSAttributedString *html = nil;
		
		if ( truncCount > 0 && kTruncateNone != truncationType )
		{
			html = [[self article] attributedHTMLStringWithTruncation:truncCount
                                                                 type:truncationType
                                                    includeLargeMedia:includeLargeMedia
                                                          didTruncate:&truncated];
		}
		else
		{
			// no truncation, just process the complete, normal summary
			html = [[self article] attributedHTMLString];
		}
		NSMutableAttributedString *summary = [html mutableCopy];
		
		if (!includeLargeMedia)
		{
			
			NSMutableArray *attachments = [[NSMutableArray alloc] initWithCapacity:
										   [[[self article] attachments] count]];

			// Strip out large attachments .... WHY?
			NSUInteger location = 0;
			
			while (location < summary.length)
			{
				NSRange effectiveRange;
				SVTextAttachment *attachment = [summary attribute:@"SVAttachment"
														  atIndex:location
												   effectiveRange:&effectiveRange];
				
				if (attachment && [[attachment causesWrap] boolValue])
				{
					[attachments addObject:[attachment graphic]];
					[summary deleteCharactersInRange:effectiveRange];
				}
				else
				{
					location = location + effectiveRange.length;
				}
			}

			// Are we left with only whitespace? If so, fallback to graphic captions
			NSString *text = [[summary string] stringByConvertingHTMLToPlainText];
			if ([text isWhitespace])
			{
				[summary release]; summary = nil;
				
				for (SVGraphic *aGraphic in attachments)
				{
					if ([aGraphic showsCaption])
					{
						summary = [[[aGraphic caption] attributedHTMLString] retain];
						break;
					}
				}
			}
			[attachments release];
		}
		
		
		
		// Write it
		[context writeAttributedHTMLString:summary];
		
		[summary release];
		
	}


    [context endElement];

	return truncated;
}

/*!	Here is the main information about how summaryHTML works.

A page is asked for ds summaryHTML to populate its parent's general index page, if it exists.
Exactly how that summary is generated is a bit complex.

First off -- if this is a collection (with some children), there is a behavior flag which is
consulted.  Depending on this flag, the summary may be generated to do one of the following:
* Show the summaryHTML of the most recently added item in that collection.  This is useful
in the case of a link to a blog, where the latest article is a teaser.
* Show a small list of titles of recent articles, limited to N articles.  Sort of a mini-index.
* Show an alphabetical list of items.  (Limited to N articles, like Yahoo subcategories?)

If the collection is instead marked "automatic", or the page is not a collection, then the
summaryHTML is generated as follows.

We use valueForUndefinedKey to cause the page to check, in this order:
* its delegate, for a summaryHTML method
* the page's plugin properties
* the element --which will also check first its delegate than its plugin properties

The idea is that you give subclasses a chance to "override" the method to calculate the value,
or look it up if not found.

A few known places where a delegate overrides summaryHTML to provide us with something:
* Image element delegate returns a photo's caption.
* Rich text element delegate returns the entire rich text article (possibly truncated)
if no override value has been set in the properties dictionary.

The general idea is that summaryHTML is automatically derived as much as possible, but the site
creator has the ability to override that and replace it with some other text.

For setting Summary HTML, the idea is that if the page has its own summary HTML value of non-nil,
meaning that the summary has been "split off", then go ahead and set that property.  Otherwise,
ask its original source to set its original value.

QUESTION: WHAT IF SUMMARY IS DERIVED -- WHAT DOES THAT MEAN TO SET?

*/
/*
- (NSString *)summaryHTML
{
	NSString *result = [self summaryHTMLAllowingTruncation:YES];	
	return result;
}

- (NSString *)summaryHTMLAllowingTruncation:(BOOL)inAllowTruncation
{
	USESDEPRECATEDAPI;
	
	NSString *result = @"";
	KTCollectionSummaryType summaryType;
	if ([self hasChildren]
		&&
		KTSummarizeAutomatic != (summaryType = [self integerForKey:@"collectionSummaryType"]))
	{
		NSArray *descriptors;
		if (summaryType == KTSummarizeAlphabeticalList)
		{
			descriptors = gAlphaSort;
		}
		else
		{
			descriptors = (KTTimestampModificationDate == [[self master] integerForKey:@"timestampType"])
			   ? gModNewTop
			   : gCreationNewTop;
		}
		
		[self lockPSCAndMOC];
		NSArray *sortedChildren = [[[self childrenInIndexSet] allObjects] sortedArrayUsingDescriptors:descriptors];
		[self unlockPSCAndMOC];
		
		if (summaryType == KTSummarizeMostRecent)
		{
			if ([sortedChildren count])
			{
				KTPage *topPage = [sortedChildren objectAtIndex:0];
				result = [topPage summaryHTML];
			}
		}
		else if (summaryType == KTSummarizeFirstItem)
		{
			if ([sortedChildren count])
			{
				KTPage *topPage = [sortedChildren lastObject];
				result = [topPage summaryHTML];
			}
		}
		else
		{
			int maxForSummary = [[NSUserDefaults standardUserDefaults] integerForKey:@"MaximumTitlesInCollectionSummary"];
			NSMutableString *s = [NSMutableString stringWithString:@"<ul>\n"];
			NSEnumerator *theEnum = [sortedChildren objectEnumerator];
			KTPage *page;
			int count = 1;

			while (nil != (page = [theEnum nextObject]) )
			{
				[s appendFormat:@"\t<li>%@</li>\n", [page wrappedValueForKey:@"titleHTML"]];
				if (count++ >= maxForSummary)
				{
					break;
				}
			}
			[s appendFormat:@"</ul>"];
			result = s;
		}
	}
	
	return result;
}
*/


/*	The key path to generate a summary from. If the delegate does not implement this we return nil
 */
- (NSString *)summaryHTMLKeyPath
{
	NSString *result = @"titleHTMLString";
	
	return result;
}

/*	Whether the page's summary should be editable. Generally this is true, but in some cases (e.g. Raw HTML page)
 *	we want a non-editable summary.
 *	The default is NO to be on the safe side.
 */
- (BOOL)summaryHTMLIsEditable
{
	BOOL result = NO;
	
	return result;
}

#pragma mark Archives

@dynamic collectionGenerateArchives;

- (NSArray *)archivePages;
{
    if (![[self collectionGenerateArchives] boolValue]) return nil;
    
    
    NSMutableArray *result = [NSMutableArray array];
    NSMutableArray *currentPages = [NSMutableArray array];
    NSDateComponents *currentMonth = nil;
    NSCalendar *calendar = [NSCalendar currentCalendar];
    
    NSArray *pages = [self childrenWithSorting:SVCollectionSortByDateCreated ascending:NO inIndex:YES];
    for (SVSiteItem *anItem in pages)
    {
        // If this page is into a different archive period, generate an archive for the pages processed so far
        NSDateComponents *components = [calendar components:(kCFCalendarUnitYear | kCFCalendarUnitMonth)
                                                   fromDate:[anItem creationDate]];
        
        if (![components isEqual:currentMonth] && currentMonth)
        {
            SVArchivePage *archivePage = [[SVArchivePage alloc] initWithPages:currentPages];
            [currentPages removeAllObjects];
            
            [result addObject:archivePage];
            [archivePage release];
        }
        
        [currentPages addObject:anItem];
        currentMonth = components;
    }
    
    
    // Create an archive page for the remaining pages
    if ([currentPages count])
    {
        SVArchivePage *archivePage = [[SVArchivePage alloc] initWithPages:currentPages];
        [currentPages removeAllObjects];
        
        [result addObject:archivePage];
        [archivePage release];
    }
    
    
    return result;
}

@end
