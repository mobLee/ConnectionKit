//
//  SVMediaGatheringHTMLContext.m
//  Sandvox
//
//  Created by Mike on 12/04/2010.
//  Copyright 2010 Karelia Software. All rights reserved.
//

#import "SVMediaGatheringHTMLContext.h"

#import "KTPublishingEngine.h"


@implementation SVMediaGatheringHTMLContext

- (id)initWithStringWriter:(id <KSStringWriter>)writer;
{
    self = [super initWithStringWriter:writer];
    return self;
}

- (void)dealloc;
{
    [super dealloc];
}

- (void)writeString:(NSString *)string;
{
    // Ignore
}

- (void)addResource:(NSURL *)resourceURL; { }   // ignore also

@end
