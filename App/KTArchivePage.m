//
//  KTArchivePage.m
//  Marvel
//
//  Created by Mike on 29/02/2008.
//  Copyright 2008-2009 Karelia Software. All rights reserved.
//

#import "KTArchivePage.h"
#import "KTPage.h"

#import "KTHTMLParser.h"

#import "NSBundle+KTExtensions.h"
#import "NSSortDescriptor+Karelia.h"

#import "assertions.h"


@implementation KTArchivePage

+ (void)initialize
{
	[self setKeys:[NSArray arrayWithObject:@"archiveStartDate"]
		triggerChangeNotificationsForDependentKey:@"dateDescription"];
}

#pragma mark -
#pragma mark Core Data

+ (NSString *)entityName { return @"ArchivePage"; }

#pragma mark -
#pragma mark Accessors

- (KTElementPlugin *)plugin { return nil; }

- (KTMaster *)master { return [[self parent] master]; }

- (NSString *)dateDescription
{
	NSDate *date = [self valueForKey:@"archiveStartDate"];
	NSString *result = [date descriptionWithCalendarFormat:@"%B %Y" timeZone:nil locale:nil];
	return result;
}

- (NSArray *)sortedPages
{
	NSMutableArray *result = [NSMutableArray arrayWithArray:[[[self parent] children] allObjects]];
	
	// Filter to only pages in our date range
	NSDate *startDate = [self valueForKey:@"archiveStartDate"];
	NSDate *endDate = [self valueForKey:@"archiveEndDate"];
	
	NSPredicate *predicate = [NSPredicate predicateWithFormat:
							  @"editableTimestamp BETWEEN { %@, %@ } AND includeInIndexAndPublish == 1",
							  startDate,
							  endDate];
	
	[result filterUsingPredicate:predicate];
	
	// Sort by date, newest first
	[result sortUsingDescriptors:[NSSortDescriptor reverseChronologicalSortDescriptors]];
	
	return result;
}


#pragma mark -
#pragma mark Title

/*  When updating the page title, also update filename to match
 */
- (void)setTitleHTML:(NSString *)value
{
    [super setTitleHTML:value];
    
    
    // Get the month formatted like "01_2008"
    NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
    [formatter setFormatterBehavior:NSDateFormatterBehavior10_4];
    [formatter setDateFormat:@"'archive_'MM'_'yyyy"];
    
    NSDate *date = [self valueForKey:@"archiveStartDate"];
	NSString *filename = [formatter stringFromDate:date];
    [self setFileName:filename];
    
    [formatter release];
}

/*  Generates a fresh -titleHTML value and stores it
 */
- (void)updateTitle
{
    // Give the archive a decent title
    NSDate *monthStart = [self valueForKey:@"archiveStartDate"];
    NSString *monthDescription = [monthStart descriptionWithCalendarFormat:@"%B %Y" timeZone:nil locale:nil];
    
    NSString *archiveTitle = [NSString stringWithFormat:@"%@ %@",
                              NSLocalizedString(@"Archive", "Part of an archive's page title"),
                              monthDescription];
    
    NSString *collectionTitle = [[self parent] titleText];
    if (collectionTitle && ![collectionTitle isEqualToString:@""])
    {
        archiveTitle = [NSString stringWithFormat:@"%@ %@", collectionTitle, archiveTitle];
    }
    
    [self setTitleText:archiveTitle];
}


/*  Overridden to append date info onto the end
 */

- (NSString *)windowTitle
{
    NSString *result = [[[self parent] windowTitle] stringByAppendingFormat:@" - %@", [self dateDescription]];
    return result;
}

- (NSString *)comboTitleText
{
    NSString *result = [[[self parent] comboTitleText] stringByAppendingFormat:@" - %@", [self dateDescription]];
    return result;
}

- (NSString *)metaDescription
{
    NSString *result = [[[self parent] metaDescription] stringByAppendingFormat:@" - %@", [self dateDescription]];
    return result;
}

#pragma mark -
#pragma mark HTML

/*	Use a different template to most pages
 */
- (NSString *)pageMainContentTemplate
{
	static NSString *sPageTemplateString = nil;
	
	if (!sPageTemplateString)
	{
		NSString *path = [[NSBundle bundleForClass:[self class]] overridingPathForResource:@"KTArchivePageTemplate" ofType:@"html"];
		NSData *data = [NSData dataWithContentsOfFile:path];
		sPageTemplateString = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
	}
	
	return sPageTemplateString;
}

- (BOOL)isXHTML { return [[self parent] isXHTML]; }

@end
