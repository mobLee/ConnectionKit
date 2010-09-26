//
//  SVMediaPlugIn.h
//  Sandvox
//
//  Created by Mike on 24/09/2010.
//  Copyright 2010 Karelia Software. All rights reserved.
//

#import "SVPlugIn.h"

#import "SVMediaGraphic.h"


@interface SVMediaPlugIn : SVPlugIn

#pragma mark Source
- (SVMediaRecord *)media;
- (NSURL *)externalSourceURL;


- (BOOL)validateTypeToPublish:(NSString **)type error:(NSError **)error;

- (CGSize)originalSize;

- (BOOL)shouldWriteHTMLInline;
- (BOOL)canWriteHTMLInline;   // NO for most graphics. Images and Raw HTML return YES


#pragma mark Pasteboard
- (void)awakeFromPasteboardContents:(id)contents ofType:(NSString *)type;


@end


@interface SVMediaPlugIn (Inherited)
@property(nonatomic, readonly) SVMediaGraphic *container;
@end
