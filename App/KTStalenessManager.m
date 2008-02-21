//
//  KTStalenessManager.m
//  Marvel
//
//  Created by Mike on 28/11/2007.
//  Copyright 2007 Karelia Software. All rights reserved.
//


/*	We maintain 2 separate lists of pages:
 *
 *		Pages which are already -isStale only have their staleness attribute monitored.
 *		This is the -observedStalePages list.
 *		
 *		All other pages are parsed and have all their keyPaths observed. This is the -observedPages list.
 *
 *	A public API is presented for the overall list of pages. The two separate lists are only exposed internally.
 */
 
/*	There is a rather interesting case that needs to be handled by the staleness manager. Consider a site with a number of pages,
 *	each dependent upon the key "uniqueID" of a particular page. So, the natural behavior would be to observer this key once
 *	for each dependent page and to set the KVO context to be the page the keypath originates from. However, when you then remove
 *	an observer, there is no control over which observer is removed; thereby messing up the KVO contexts.
 *	The solution: ignore context.
 */

#import "KTStalenessManager.h"

#import "KTPage.h"
#import "KTParsedKeyPath.h"
#import "KTStalenessHTMLParser.h"
#import "NSManagedObjectContext+KTExtensions.h"
#import "NSObject+Karelia.h"
#import "NSString+Karelia.h"
#import "NSThread+Karelia.h"


@interface KTStalenessManager (Private)
- (NSMutableDictionary *)nonStalePages;
- (void)addNonStalePage:(KTPage *)page;
- (void)removeNonStalePage:(KTPage *)page;

@end


#pragma mark -


@implementation KTStalenessManager

#pragma mark -
#pragma mark Init & Dealloc

- (id)initWithDocument:(KTDocument *)document
{
	[super init];
	
	myDocument = document;	// Weak ref
	myObservedPages = [[NSMutableSet alloc] init];
	
	[[NSNotificationCenter defaultCenter] addObserver:self
											 selector:@selector(documentWillClose:)
												 name:@"KTDocumentWillClose"
											   object:document];
	
	[[NSNotificationCenter defaultCenter] addObserver:self
											 selector:@selector(mocDidChange:)
												 name:NSManagedObjectContextObjectsDidChangeNotification
											   object:[document managedObjectContext]];
	return self;
}

- (void)dealloc
{
	[[NSNotificationCenter defaultCenter] removeObserver:self];
	[self stopObservingAllPages];
	[myNonStalePages release];
	
	[myObservedPages release];
	
	[super dealloc];
}

#pragma mark -
#pragma mark Public API

- (KTDocument *)document { return myDocument; }

- (void)beginObservingPage:(KTPage *)page
{
	// We observe the staleness of all pages
	if (![myObservedPages containsObject:page])
	{
		[page addObserver:self forKeyPath:@"isStale" options:0 context:NULL];
		[myObservedPages addObject:page];
	}
	
	// Parse and observe component keypaths if non-stale
	if (![page boolForKey:@"isStale"])
	{
		[self addNonStalePage:page];
	}
}

/*	Runs through every page in the document
 *	If the page is not already stale, we parse it to get a list of keypaths and begin
 *	observing them.
 */
- (void)beginObservingAllPages
{
	#ifdef DEBUG
	NSDate *startDate = [NSDate date];
	#endif
	
	
	NSArray *pages = [[[self document] managedObjectContext] allObjectsWithEntityName:@"Page"
																				error:NULL];
	
	// Little trick to make sure the dictionary is a decent size to start with
	if (!myNonStalePages) {
		myNonStalePages = [[NSMutableDictionary alloc] initWithCapacity:[pages count]];
	}
	
	NSEnumerator *pagesEnumerator = [pages objectEnumerator];
	KTPage *aPage;
	while (aPage = [pagesEnumerator nextObject])
	{
		[self beginObservingPage:aPage];
	}
	
	
	#ifdef DEBUG
	NSLog(@"Observing all pages for staleness took %fs", -[startDate timeIntervalSinceNow]);
	#endif
}

- (void)stopObservingPage:(KTPage *)page
{
	[self removeNonStalePage:page];
	
	[page removeObserver:self forKeyPath:@"isStale"];
	[myObservedPages removeObject:page];
}

- (void)stopObservingAllPages
{
	NSEnumerator *pagesEnumerator = [[NSSet setWithSet:myObservedPages] objectEnumerator];
	KTPage *aPage;
	while (aPage = [pagesEnumerator nextObject])
	{
		[self stopObservingPage:aPage];
	}
}

#pragma mark -
#pragma mark Not Stale Pages

- (NSMutableDictionary *)nonStalePages
{
	if (!myNonStalePages)
	{
		myNonStalePages = [[NSMutableDictionary alloc] initWithCapacity:1];
	}
	
	return myNonStalePages;
}

- (NSMutableSet *)observedKeyPathsOfNonStalePageWithID:(NSString *)pageID
{
	NSMutableSet *result = [[self nonStalePages] objectForKey:pageID];
	
	if (!result)
	{
		result = [[NSMutableSet alloc] initWithCapacity:1];
		[[self nonStalePages] setObject:result forKey:pageID];
		[result release];
	}
	
	return result;
}

- (NSMutableSet *)observedKeyPathsOfNonStalePage:(KTPage *)page
{
	return [self observedKeyPathsOfNonStalePageWithID:[page uniqueID]];
}

- (NSSet *)nonStalePagesDependentUponKeyPath:(NSString *)keyPath ofObject:(NSObject *)object
{
	// Run through all non-stale pages to see if they are dependent upon the key
	KTParsedKeyPath *parsedKeyPath = [[KTParsedKeyPath alloc] initWithKeyPath:keyPath ofObject:object];
	NSMutableSet *dependentPageIDs = [[NSMutableSet alloc] init];
	
	NSEnumerator *pageIDsEnumerator = [[self nonStalePages] keyEnumerator];
	NSString *aPageID;
	while (aPageID = [pageIDsEnumerator nextObject])
	{
		NSSet *pageKeyPaths = [self observedKeyPathsOfNonStalePageWithID:aPageID];
		if ([pageKeyPaths containsObject:parsedKeyPath])
		{
			[dependentPageIDs addObject:aPageID];
		}
	}
	
	[parsedKeyPath release];
	
	
	// The list we have thus far is of page IDs. Convert to actual pages and return
	NSMutableSet *result = [NSMutableSet setWithCapacity:[dependentPageIDs count]];
	NSEnumerator *pagesEnumerator = [dependentPageIDs objectEnumerator];
	while (aPageID = [pagesEnumerator nextObject])
	{
		KTPage *page = [[[self document] managedObjectContext] pageWithUniqueID:aPageID];
		[result addObject:page];
	}
	
	
	[dependentPageIDs release];
	return result;
}

- (void)addNonStalePage:(KTPage *)page
{
	// Only begin observing the page if we're not already doing so
	if (![[self nonStalePages] objectForKey:[page uniqueID]])
	{
		// Parse the page as quickly as possible. The parser delegate (us) will pick up observation info.
		KTHTMLParser *parser = [[KTStalenessHTMLParser alloc] initWithPage:page];
		[parser setDelegate:self];
		[parser setHTMLGenerationPurpose:kGeneratingRemote];
		
		[parser parseTemplate];
		
		[parser release];
	}
}

- (void)beginObservingKeyPath:(NSString *)keyPath ofObject:(id)object onNonStalePage:(KTPage *)page;
{
	NSMutableSet *observedKeyPaths = [self observedKeyPathsOfNonStalePage:page];
	KTParsedKeyPath *parsedKeyPath = [[KTParsedKeyPath alloc] initWithKeyPath:keyPath ofObject:object];
	
	if (![observedKeyPaths containsObject:parsedKeyPath])
	{
		[observedKeyPaths addObject:parsedKeyPath];
		[object addObserver:self forKeyPath:keyPath options:0 context:NULL];
	}
	
	[parsedKeyPath release];
}

- (void)removeNonStalePage:(KTPage *)page
{
	// Ignore pages without an ID
	if (![page uniqueID]) {
		return;
	}
	
	
	NSSet *observedKeyPaths = [self observedKeyPathsOfNonStalePage:page];
	NSEnumerator *keypathsEnumerator = [observedKeyPaths objectEnumerator];
	KTParsedKeyPath *keyPath;
	
	while (keyPath = [keypathsEnumerator nextObject])
	{
		[[keyPath parsedObject] removeObserver:self forKeyPath:[keyPath keyPath]];
	}
	
	[[self nonStalePages] removeObjectForKey:[page uniqueID]];
}

- (void)HTMLParser:(KTHTMLParser *)parser didEncounterKeyPath:(NSString *)keyPath ofObject:(id)object
{
	[self beginObservingKeyPath:keyPath ofObject:object onNonStalePage:[parser currentPage]];
}

#pragma mark -
#pragma mark Support

/*	Whenever pages are inserted or deleted 
 */
- (void)mocDidChange:(NSNotification *)notification
{
	NSSet *insertedObjects = [[notification userInfo] objectForKey:NSInsertedObjectsKey];
	NSEnumerator *enumerator = [insertedObjects objectEnumerator];
	NSManagedObject *aManagedObject;
	while (aManagedObject = [enumerator nextObject])
	{
		if ([aManagedObject isKindOfClass:[KTPage class]])
		{
			[self beginObservingPage:(KTPage *)aManagedObject];
		}
	}
	
	NSSet *deletedObjects = [[notification userInfo] objectForKey:NSDeletedObjectsKey];
	enumerator = [deletedObjects objectEnumerator];
	while (aManagedObject = [enumerator nextObject])
	{
		if ([aManagedObject isKindOfClass:[KTPage class]])
		{
			[self stopObservingPage:(KTPage *)aManagedObject];
		}
	}
}

/*	This ensures we don't accidentally keep observing the document after it's been dealloced
 */
- (void)documentWillClose:(NSNotification *)notification
{
	[self stopObservingAllPages];
}

/*	Somewhere a keypath affecting one or more of our pages changed.
 */
- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context
{
	// Ignore notifications in the background
	if (![NSThread isMainThread]) {
		return;
	}
	
	
	// The pages have changed in some way. Mark them stale and move to the stale list.
	NSSet *affectedPages = [self nonStalePagesDependentUponKeyPath:keyPath ofObject:object];
	[affectedPages setBool:YES forKey:@"isStale"];
	
	
	// When page staleness changes, begin or stop observing it as appropriate
	if ([keyPath isEqualToString:@"isStale"] && [object isKindOfClass:[KTPage class]])
	{
		KTPage *page = (KTPage *)object;
		if ([page boolForKey:@"isStale"])	// The delay ensures the rest of the system has caught up first. Otherwise we get
		{									// strange KVO exceptions or the page immediately being set stale again.
			[self performSelector:@selector(removeNonStalePage:) withObject:page afterDelay:0.0];
		}
		else
		{
			[self performSelector:@selector(addNonStalePage:) withObject:page afterDelay:0.0];
		}
	}
}

@end
