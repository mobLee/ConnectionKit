//
//  SVMediaGraphic.m
//  Sandvox
//
//  Created by Mike on 04/04/2010.
//  Copyright 2010 Karelia Software. All rights reserved.
//

#import "SVMediaGraphic.h"

#import "SVAudio.h"
#import "SVFlash.h"
#import "SVGraphicFactory.h"
#import "KTMaster.h"
#import "SVMediaGraphicInspector.h"
#import "SVMediaRecord.h"
#import "SVImage.h"
#import "KTPage.h"
#import "SVWebEditorHTMLContext.h"
#import "KSWebLocation.h"
#import "SVVideo.h"

#import "NSError+Karelia.h"
#import "NSString+Karelia.h"
#import "NSURL+Karelia.h"

#import "KSURLUtilities.h"


@interface SVMediaGraphic ()

@property(nonatomic, copy) NSString *externalSourceURLString;

@property(nonatomic, copy, readwrite) NSNumber *constrainedAspectRatio;

@end


#pragma mark -


@implementation SVMediaGraphic

#pragma mark Init

+ (id)insertNewGraphicInManagedObjectContext:(NSManagedObjectContext *)context;
{
    SVMediaGraphic *result = [NSEntityDescription insertNewObjectForEntityForName:@"MediaGraphic"
                                                           inManagedObjectContext:context];
    [result loadPlugInAsNew:YES];
    return result;
}

- (void)willInsertIntoPage:(KTPage *)page;
{
    // Placeholder image
    if (![self media])
    {
        SVMediaRecord *media = [[page master] makePlaceholdImageMediaWithEntityName:[[self class] meditEntityName]];
        [self setMedia:media];
        [self setTypeToPublish:[media typeOfFile]];
        
        [self makeOriginalSize];    // calling super will scale back down if needed
        [self setConstrainProportions:YES];
    }
    
    [super willInsertIntoPage:page];
    
    // Show caption
    if ([[[self textAttachment] placement] intValue] != SVGraphicPlacementInline)
    {
        [self setShowsCaption:YES];
    }
}

#pragma mark Plug-in

- (NSString *)plugInIdentifier;
{
    NSString *type = [[self media] typeOfFile];
    if (!type) type = [NSString UTIForFilenameExtension:[[self externalSourceURL] ks_pathExtension]];
    
    
    if ([type conformsToUTI:(NSString *)kUTTypeMovie] || [type conformsToUTI:(NSString *)kUTTypeVideo])
    {
        return @"com.karelia.sandvox.SVVideo";
    }
    else if ([type conformsToUTI:(NSString *)kUTTypeAudio])
    {
        return @"com.karelia.sandvox.SVAudio";
    }
    else if ([type conformsToUTI:@"com.adobe.shockwave-flash"])
    {
        return @"com.karelia.sandvox.SVFlash";
    }
    else
    {
        return @"com.karelia.sandvox.Image";
    }
}

#pragma mark Placement

- (BOOL)isPagelet;
{
    // Images are no longer pagelets once you turn off all additional stuff like title & caption
    if ([[self placement] intValue] == SVGraphicPlacementInline &&
        ![self showsTitle] &&
        ![self showsIntroduction] &&
        ![self showsCaption])
    {
        return NO;
    }
    else
    {
        return [super isPagelet];
    }
}

#pragma mark Media

- (void)didSetSource;
{
    // Does this change the type?
    NSString *identifier = [self plugInIdentifier];
    SVGraphicFactory *factory = [SVGraphicFactory factoryWithIdentifier:identifier];
    
    if (![[self plugIn] isKindOfClass:[factory plugInClass]])
    {
        [self loadPlugInAsNew:NO];
        [[self plugIn] awakeFromNew];
    }
    
    
    [[self plugIn] didSetSource];
}

@dynamic media;
- (void)setMedia:(SVMediaRecord *)media;
{
    [self willChangeValueForKey:@"media"];
    [self setPrimitiveValue:media forKey:@"media"];
    [self didChangeValueForKey:@"media"];
    
    
    [self didSetSource];
}

@dynamic isMediaPlaceholder;

- (void)setMediaWithURL:(NSURL *)URL;
{
    SVMediaRecord *media = nil;
    if (URL)
    {
        media = [SVMediaRecord mediaWithURL:URL
                                 entityName:[[self class] meditEntityName]
             insertIntoManagedObjectContext:[self managedObjectContext]
                                      error:NULL];
    }
    
    [self replaceMedia:media forKeyPath:@"media"];
}

+ (NSString *)meditEntityName; { return @"GraphicMedia"; }

#pragma mark External URL

@dynamic externalSourceURLString;
- (void) setExternalSourceURLString:(NSString *)source;
{
    [self willChangeValueForKey:@"externalSourceURLString"];
    [self setPrimitiveValue:source forKey:@"externalSourceURLString"];
    [self didChangeValueForKey:@"externalSourceURLString"];
    
    [self didSetSource];
}

- (NSURL *)externalSourceURL
{
    NSString *string = [self externalSourceURLString];
    return (string) ? [NSURL URLWithString:string] : nil;
}
- (void)setExternalSourceURL:(NSURL *)URL
{
    if (URL) [self replaceMedia:nil forKeyPath:@"media"];
    
    [self setExternalSourceURLString:[URL absoluteString]];
}

#pragma mark Source

- (NSURL *)sourceURL;
{
    NSURL *result = nil;
    
    SVMediaRecord *media = [self media];
    if (media)
    {
        result = [media fileURL];
        if (!result) result = [media mediaURL];
    }
    else
    {
        result = [self externalSourceURL];
    }
    
    return result;
}

- (BOOL)hasFile; { return YES; }

+ (BOOL)acceptsType:(NSString *)uti; { return NO; }

+ (NSArray *)allowedTypes;
{
    NSMutableSet *result = [NSMutableSet set];
    [result addObjectsFromArray:[SVImage allowedFileTypes]];
    [result addObjectsFromArray:[SVVideo allowedFileTypes]];
    [result addObjectsFromArray:[SVAudio allowedFileTypes]];
    [result addObjectsFromArray:[SVFlash allowedFileTypes]];
    
	return [result allObjects];
}

+ (NSArray *)readableTypesForPasteboard:(NSPasteboard *)pasteboard
{
    NSArray *result = [SVImage allowedFileTypes]; // want to read by UTI ideally
    result = [result arrayByAddingObjectsFromArray:[KSWebLocation webLocationPasteboardTypes]];
    return result;
}

#pragma mark Poster Frame

@dynamic posterFrame;
- (BOOL)validatePosterFrame:(SVMediaRecord **)media error:(NSError **)error;
{
    BOOL result = [[self plugIn] validatePosterFrame:*media];
    if (!result && error)
    {
        *error = [NSError errorWithDomain:NSCocoaErrorDomain code:NSValidationMissingMandatoryPropertyError localizedDescription:@"Plug-in doesn't want a poster image"];
    }
    
    return result;
}

#pragma mark Media Conversion

@dynamic typeToPublish;
- (BOOL)validateTypeToPublish:(NSString **)type error:(NSError **)error;
{
    BOOL result = [[self plugIn] validateTypeToPublish:*type];
    if (!result && error)
    {
        *error = [NSError errorWithDomain:NSCocoaErrorDomain code:NSValidationMissingMandatoryPropertyError localizedDescription:@"typeToPublish is non-optional for images"];
    }
    
    return result;
}

#pragma mark Size

- (void)setSize:(NSSize)size;
{
    if ([self constrainProportions])
    {
        CGFloat constraintRatio = [[self constrainedAspectRatio] floatValue];
        CGFloat aspectRatio = size.width / size.height;
        
        if (aspectRatio < constraintRatio)
        {
            [self setHeight:[NSNumber numberWithFloat:size.height]];
        }
        else
        {
            [self setWidth:[NSNumber numberWithFloat:size.width]];
        }
    }
    else
    {
        [self setWidth:[NSNumber numberWithFloat:size.width]];
        [self setHeight:[NSNumber numberWithFloat:size.height]];
    }
}

- (BOOL)constrainProportions { return [self constrainedAspectRatio] != nil; }
- (void)setConstrainProportions:(BOOL)constrainProportions;
{
    if (constrainProportions)
    {
        CGFloat aspectRatio = [[self width] floatValue] / [[self height] floatValue];
        [self setConstrainedAspectRatio:[NSNumber numberWithFloat:aspectRatio]];
    }
    else
    {
        [self setConstrainedAspectRatio:nil];
    }
}

+ (NSSet *)keyPathsForValuesAffectingConstrainProportions;
{
    return [NSSet setWithObject:@"constrainedAspectRatio"];
}

@dynamic constrainedAspectRatio;

- (BOOL)isConstrainProportionsEditable; { return YES; }

@dynamic naturalWidth;
@dynamic naturalHeight;

- (void)makeOriginalSize;
{
    BOOL constrainProportions = [self constrainProportions];
    [self setConstrainProportions:NO];  // temporarily turn off so we get desired size.
    
    [super makeOriginalSize];
    
    [self setConstrainProportions:constrainProportions];
}

#pragma mark Size, inherited

- (void)setWidth:(NSNumber *)width;
{
    [self willChangeValueForKey:@"width"];
    [self setPrimitiveValue:width forKey:@"width"];
    [self didChangeValueForKey:@"width"];
    
    NSNumber *aspectRatio = [self constrainedAspectRatio];
    if (aspectRatio)
    {
        NSUInteger height = ([width floatValue] / [aspectRatio floatValue]);
        
        [self willChangeValueForKey:@"height"];
        [self setPrimitiveValue:[NSNumber numberWithUnsignedInteger:height] forKey:@"height"];
        [self didChangeValueForKey:@"height"];
    }
}
- (BOOL)validateWidth:(NSNumber **)width error:(NSError **)error;
{
    // SVGraphic.width is optional. For media graphics it becomes compulsory unless using external URL
    BOOL result = (*width != nil || (![self media] && [self externalSourceURL]));
    if (!result && error)
    {
        *error = [NSError errorWithDomain:NSCocoaErrorDomain
                                     code:NSValidationMissingMandatoryPropertyError
                     localizedDescription:@"width is a mandatory property"];
    }
    
    return result;
}

- (void)setHeight:(NSNumber *)height;
{
    [self willChangeValueForKey:@"height"];
    [self setPrimitiveValue:height forKey:@"height"];
    [self didChangeValueForKey:@"height"];
    
    NSNumber *aspectRatio = [self constrainedAspectRatio];
    if (aspectRatio)
    {
        NSUInteger width = ([height floatValue] * [aspectRatio floatValue]);
        
        [self willChangeValueForKey:@"width"];
        [self setPrimitiveValue:[NSNumber numberWithUnsignedInteger:width] forKey:@"width"];
        [self didChangeValueForKey:@"width"];
    }
}
- (BOOL)validateHeight:(NSNumber **)height error:(NSError **)error;
{
    // Push off validation to plug-in
    return [[self plugIn] validateHeight:height error:error];
}

#pragma mark HTML

- (BOOL)shouldWriteHTMLInline; { return [[self plugIn] shouldWriteHTMLInline]; }

- (BOOL)canWriteHTMLInline; { return true; }		// all of these can be figure-content

#pragma mark Inspector

- (Class)inspectorFactoryClass; { return [[self plugIn] class]; }

- (id)objectToInspect; { return self; }

#pragma mark Thumbnail

- (id <SVMedia>)thumbnailMedia;
{
    return [[self plugIn] thumbnailMedia];	// video may want to return poster frame
}

- (id)imageRepresentation;
{
	return [[self plugIn] imageRepresentation];
}

- (NSString *)imageRepresentationType
{
	return [[self plugIn] imageRepresentationType];
}

- (CGFloat)thumbnailAspectRatio;
{
    CGFloat result;
    
    if ([self constrainedAspectRatio])
    {
        result = [[self constrainedAspectRatio] floatValue];
    }
    else
    {
        result = [[self width] floatValue] / [[self height] floatValue];
    }
    
    return result;
}

+ (NSSet *)keyPathsForValuesAffectingImageRepresentation { return [NSSet setWithObject:@"media"]; }

#pragma mark RSS Enclosure

- (id <SVEnclosure>)enclosure;
{
	return [self plugIn];
}

#pragma mark Serialization

- (void)populateSerializedProperties:(NSMutableDictionary *)propertyList;
{
    [super populateSerializedProperties:propertyList];
    
    // Write image data
    SVMediaRecord *media = [self media];
    
    NSData *data = [NSData newDataWithContentsOfMedia:media];
    [propertyList setValue:data forKey:@"fileContents"];
    [data release];
    
    NSURL *URL = [self sourceURL];
    [propertyList setValue:[URL absoluteString] forKey:@"sourceURL"];
}

- (void)awakeFromPropertyList:(id)propertyList;
{
    [super awakeFromPropertyList:propertyList];
    
    // Pull out image data
    NSData *data = [propertyList objectForKey:@"fileContents"];
    if (data)
    {
        NSString *urlString = [propertyList objectForKey:@"sourceURL"];
        NSURL *url = [NSURL URLWithString:urlString];
        
        SVMediaRecord *media = [SVMediaRecord mediaWithData:data
                                                        URL:url
                                                 entityName:[[self class] meditEntityName]
                             insertIntoManagedObjectContext:[self managedObjectContext]];
        
        [self setMedia:media];
    }
}

#pragma mark Pasteboard

- (void)awakeFromPasteboardItem:(id <SVPasteboardItem>)item;
{
    [super awakeFromPasteboardItem:item];
    
    
    // Can we read a media oject from the pboard?
    SVMediaRecord *media = nil;
    
    NSURL *URL = [item URL];
    if ([URL isFileURL])
    {
        media = [SVMediaRecord mediaWithURL:URL
                                 entityName:[[self class] meditEntityName]
             insertIntoManagedObjectContext:[self managedObjectContext]
                                      error:NULL];
    }
    else
    {
        NSString *type = [item availableTypeFromArray:[SVImage allowedFileTypes]];
        if (type)
        {
            // Invent a URL
            NSString *extension = [NSString filenameExtensionForUTI:type];
            
            NSString *path = [[@"/" stringByAppendingPathComponent:@"pasted-file"]
                              stringByAppendingPathExtension:extension];
            
            NSURL *url = [NSURL URLWithScheme:@"sandvox-fake-url"
                                         host:[NSString UUIDString]
                                         path:path];        
            
            media = [SVMediaRecord mediaWithData:[item dataForType:type]
                                             URL:url
                                      entityName:[[self class] meditEntityName]
                  insertIntoManagedObjectContext:[self managedObjectContext]];
        }
        else if (URL)
        {
            [self setExternalSourceURL:URL];
        }
    }
    
    
    // Swap in the new media
    if (media || URL)
    {
        if (media) [self replaceMedia:media forKeyPath:@"media"];
        
        // Reset size
        self.naturalWidth = nil;
        self.naturalHeight = nil;
        
        NSNumber *oldWidth = [self width];
        [self makeOriginalSize];
        [self setConstrainProportions:YES];
        [self setWidth:oldWidth];
    }
    
    
    [[self plugIn] awakeFromPasteboardItem:item];
}

@end
