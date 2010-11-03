//
//  SVMediaPlugIn.h
//  Sandvox
//
//  Created by Mike on 24/09/2010.
//  Copyright 2010 Karelia Software. All rights reserved.
//

//  Takes the public SVPlugIn API and extends for our private use for media-specific handling. Like a regular plug-in, still hosted by a Graphic object (Core Data modelled), but have full access to it via the -container method. Several convenience methods are provided so you don't have to call -container so much (-media, -externalSourceURL, etc.).


#import "SVPlugIn.h"
#import "SVEnclosure.h"

#import "SVMediaRecord.h"
#import "SVPlugInGraphic.h"


@interface SVMediaPlugIn : SVPlugIn <SVEnclosure>

#pragma mark Source
@property(nonatomic, readonly) SVMedia *media;  // KVO-compliant and everything!
- (NSURL *)externalSourceURL;
- (void)didSetSource;
+ (NSArray *)allowedFileTypes;

@property(nonatomic, readonly) SVMediaRecord *posterFrame;  // KVO-compliant
- (BOOL)validatePosterFrame:(SVMediaRecord *)posterFrame;
- (void)setPosterFrameWithMedia:(SVMedia *)media;   // nil removes poster frame


#pragma mark Publishing
@property(nonatomic, copy) NSString *typeToPublish; // KVO-compliant
- (BOOL)validateTypeToPublish:(NSString *)type;


#pragma mark Metrics

- (NSNumber *)width;
- (NSNumber *)height;

- (BOOL)validateHeight:(NSNumber **)height error:(NSError **)error;

// Please use this API rather than talking to the container
- (NSNumber *)naturalWidth;
- (NSNumber *)naturalHeight;
- (void)setNaturalWidth:(NSNumber *)width height:(NSNumber *)height;
- (CGSize)originalSize;


#pragma mark HTML
- (BOOL)shouldWriteHTMLInline;
- (BOOL)canWriteHTMLInline;   // NO for most graphics. Images and Raw HTML return YES
- (id <SVMedia>)thumbnailMedia;			// usually just media; might be poster frame of movie
- (id)imageRepresentation;
- (NSString *)imageRepresentationType;


@end


@interface SVMediaPlugIn (Inherited)
@property(nonatomic, readonly) SVPlugInGraphic *container;
@end
