//
//  SVWebContentItem.m
//  Sandvox
//
//  Created by Mike on 02/09/2009.
//  Copyright 2009 Karelia Software. All rights reserved.
//

#import "SVWebContentItem.h"


@implementation SVWebContentItem

#pragma mark Init & Dealloc

- (id)init
{
    return [self initWithElement:nil];
}

- (id)initWithElement:(DOMHTMLElement *)element;
{
    OBPRECONDITION(element);
    
    self = [super init];
    
    _element = [element retain];
    
    _nodeTracker = [[SVDOMNodeBoundsTracker alloc] initWithDOMNode:element];
    [_nodeTracker setDelegate:self];
    
    return self;
}

- (void)dealloc
{
    [_nodeTracker stopTracking];
    [_nodeTracker setDelegate:nil];
    [_nodeTracker release];
    
    [_element release];
    
    [super dealloc];
}

#pragma mark DOM

@synthesize DOMElement = _element;

- (BOOL)writeToPasteboard:(NSPasteboard *)pasteboard;
{
    [pasteboard declareTypes:[NSArray arrayWithObject:@"com.karelia.Sandvox.pagelet-list"]
                       owner:self];
    
    return YES;
}

#pragma mark Editing Overlay Item

- (void)trackerDidDetectDOMNodeBoundsChange:(NSNotification *)notification;
{
    
}

@end
